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

    /// Uploads the photos, then inserts the row that points at them.
    ///
    /// The visit's id is generated here rather than by Postgres so the Storage path and
    /// the row can share it. Doing the upload first keeps the save atomic from the user's
    /// side: a failed upload leaves no half-saved visit behind, and if the insert is what
    /// fails, the just-uploaded objects are cleaned up.
    func createVisit(
        userID: UUID,
        countryCode: String,
        visitedAt: Date?,
        note: String?,
        photos: [UIImage]
    ) async throws -> Visit {
        let visitID = UUID()
        let paths = photos.isEmpty ? [] : try await uploadPhotos(photos, userID: userID, visitID: visitID)

        let payload = NewVisit(
            id: visitID,
            userID: userID,
            countryCode: countryCode,
            visitedAt: visitedAt,
            note: note?.isEmpty == true ? nil : note,
            photoURLs: paths
        )

        do {
            return try await client
                .from("visits")
                .insert(payload)
                .select()
                .single()
                .execute()
                .value
        } catch {
            await removeUploadedPhotos(at: paths)
            throw error
        }
    }

    func deleteVisit(id: UUID) async throws {
        try await client.from("visits").delete().eq("id", value: id).execute()
    }

    // MARK: - Photos

    /// Uploads up to `maxPhotos` images and returns their Storage object paths.
    ///
    /// The bucket is private, so what's stored in `visits.photo_urls` is the object path;
    /// `signedURL(for:)` turns one into something an image view can load.
    ///
    /// The uuids are lowercased deliberately. Swift renders a `UUID` in uppercase, while
    /// Postgres renders `auth.uid()::text` in lowercase, and the storage policy compares
    /// the two — uppercase paths get rejected as somebody else's folder.
    private func uploadPhotos(_ photos: [UIImage], userID: UUID, visitID: UUID) async throws -> [String] {
        var paths: [String] = []

        for (index, photo) in photos.prefix(Self.maxPhotos).enumerated() {
            guard let data = PhotoProcessor.squareJPEGData(from: photo) else { continue }
            let path = "\(userID.uuidString.lowercased())/\(visitID.uuidString.lowercased())/\(index).jpg"
            do {
                try await client.storage
                    .from(SupabaseClientProvider.photoBucket)
                    .upload(path, data: data, options: FileOptions(contentType: "image/jpeg", upsert: true))
            } catch {
                await removeUploadedPhotos(at: paths)
                throw error
            }
            paths.append(path)
        }

        return paths
    }

    /// Best-effort cleanup, so a failed save doesn't leave photos nothing points at.
    private func removeUploadedPhotos(at paths: [String]) async {
        guard !paths.isEmpty else { return }
        _ = try? await client.storage.from(SupabaseClientProvider.photoBucket).remove(paths: paths)
    }

    func signedURL(for path: String) async throws -> URL {
        try await client.storage
            .from(SupabaseClientProvider.photoBucket)
            .createSignedURL(path: path, expiresIn: 3600)
    }
}
