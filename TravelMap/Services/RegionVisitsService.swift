import Foundation
import Supabase
import UIKit

/// Reads and writes visits to a country's local subdivisions.
struct RegionVisitsService: Sendable {
    private let client: SupabaseClient

    init() throws {
        guard let client = SupabaseClientProvider.shared else { throw SupabaseNotConfiguredError() }
        self.client = client
    }

    func fetchRegionVisits(for userID: UUID) async throws -> [RegionVisit] {
        try await client
            .from("region_visits")
            .select()
            .eq("user_id", value: userID)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func createRegionVisit(
        userID: UUID,
        countryCode: String,
        regionCode: String,
        visitedAt: Date?,
        note: String?,
        photos: [UIImage]
    ) async throws -> RegionVisit {
        let visitID = UUID()
        let paths = try await uploadPhotos(photos, userID: userID, visitID: visitID)
        let payload = NewRegionVisit(
            id: visitID,
            userID: userID,
            countryCode: countryCode,
            regionCode: regionCode,
            visitedAt: visitedAt,
            note: note?.isEmpty == true ? nil : note,
            photoURLs: paths
        )

        do {
            return try await client
                .from("region_visits")
                .insert(payload)
                .select()
                .single()
                .execute()
                .value
        } catch {
            await removePhotos(at: paths)
            throw error
        }
    }

    func updateRegionVisit(
        _ visit: RegionVisit,
        visitedAt: Date?,
        note: String?,
        retainedPhotoPaths: [String],
        newPhotos: [UIImage]
    ) async throws -> RegionVisit {
        let retained = retainedPhotoPaths.filter { visit.photos.contains($0) }
        let additions = Array(newPhotos.prefix(max(0, VisitsService.maxPhotos - retained.count)))
        let newPaths = try await uploadPhotos(additions, userID: visit.userID, visitID: visit.id)
        let payload = RegionVisitUpdate(
            visitedAt: visitedAt,
            note: note?.isEmpty == true ? nil : note,
            photoURLs: retained + newPaths
        )

        do {
            let updated: RegionVisit = try await client
                .from("region_visits")
                .update(payload)
                .eq("id", value: visit.id)
                .select()
                .single()
                .execute()
                .value
            await removePhotos(at: visit.photos.filter { !retained.contains($0) })
            return updated
        } catch {
            await removePhotos(at: newPaths)
            throw error
        }
    }

    func deleteRegionVisit(_ visit: RegionVisit) async throws {
        try await client.from("region_visits").delete().eq("id", value: visit.id).execute()
        await removePhotos(at: visit.photos)
    }

    private func uploadPhotos(_ photos: [UIImage], userID: UUID, visitID: UUID) async throws -> [String] {
        var paths: [String] = []
        for (index, photo) in photos.prefix(VisitsService.maxPhotos).enumerated() {
            guard let data = PhotoProcessor.squareJPEGData(from: photo) else { continue }
            let filename = "region-\(index)-\(UUID().uuidString.lowercased()).jpg"
            let path = "\(userID.uuidString.lowercased())/\(visitID.uuidString.lowercased())/\(filename)"
            do {
                try await client.storage
                    .from(SupabaseClientProvider.photoBucket)
                    .upload(path, data: data, options: FileOptions(contentType: "image/jpeg", upsert: true))
            } catch {
                await removePhotos(at: paths)
                throw error
            }
            paths.append(path)
        }
        return paths
    }

    private func removePhotos(at paths: [String]) async {
        guard !paths.isEmpty else { return }
        _ = try? await client.storage.from(SupabaseClientProvider.photoBucket).remove(paths: paths)
    }
}
