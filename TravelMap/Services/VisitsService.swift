import Foundation
import Supabase
import UIKit

/// Reads and writes country-level visits, and the photos attached to them.
struct VisitsService: Sendable {
    /// A visit carries at most four photos, per the design.
    static let maxPhotos = 4

    private let client: SupabaseClient

    init() throws {
        guard let client = SupabaseClientProvider.shared else { throw SupabaseNotConfiguredError() }
        self.client = client
    }

    // MARK: - Visits

    func fetchVisits(for userID: UUID) async throws -> [Visit] {
        try await client
            .from("visits")
            .select()
            .eq("user_id", value: userID)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    /// Inserts the visit first, then uploads its photos under the new row's id so the
    /// Storage path and the database row can't drift apart.
    func createVisit(
        userID: UUID,
        countryCode: String,
        visitedAt: Date?,
        note: String?,
        photos: [UIImage]
    ) async throws -> Visit {
        let payload = NewVisit(
            userID: userID,
            countryCode: countryCode,
            visitedAt: visitedAt,
            note: note?.isEmpty == true ? nil : note,
            photoURLs: []
        )

        let visit: Visit = try await client
            .from("visits")
            .insert(payload)
            .select()
            .single()
            .execute()
            .value

        guard !photos.isEmpty else { return visit }

        let paths = try await uploadPhotos(photos, userID: userID, visitID: visit.id)
        return try await client
            .from("visits")
            .update(["photo_urls": paths])
            .eq("id", value: visit.id)
            .select()
            .single()
            .execute()
            .value
    }

    func deleteVisit(id: UUID) async throws {
        try await client.from("visits").delete().eq("id", value: id).execute()
    }

    // MARK: - Photos

    /// Uploads up to `maxPhotos` images and returns their Storage object paths.
    ///
    /// The bucket is private, so what's stored in `visits.photo_urls` is the object path;
    /// `signedURL(for:)` turns one into something an image view can load.
    private func uploadPhotos(_ photos: [UIImage], userID: UUID, visitID: UUID) async throws -> [String] {
        var paths: [String] = []

        for (index, photo) in photos.prefix(Self.maxPhotos).enumerated() {
            guard let data = PhotoProcessor.squareJPEGData(from: photo) else { continue }
            let path = "\(userID.uuidString)/\(visitID.uuidString)/\(index).jpg"
            try await client.storage
                .from(SupabaseClientProvider.photoBucket)
                .upload(path, data: data, options: FileOptions(contentType: "image/jpeg", upsert: true))
            paths.append(path)
        }

        return paths
    }

    func signedURL(for path: String) async throws -> URL {
        try await client.storage
            .from(SupabaseClientProvider.photoBucket)
            .createSignedURL(path: path, expiresIn: 3600)
    }
}
