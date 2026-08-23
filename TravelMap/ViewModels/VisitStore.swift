import Foundation
import MapKit
import UIKit

/// A visited-versus-total tally, ready to render. Always derived, never stored.
struct VisitProgress: Equatable {
    let visited: Int
    let total: Int

    var fraction: Double { total > 0 ? Double(visited) / Double(total) : 0 }

    /// Whole percent, except that a single visit shouldn't round away to "0%".
    var percentText: String {
        let percent = fraction * 100
        if percent > 0, percent < 1 { return "<1%" }
        return "\(Int(percent.rounded()))%"
    }
}

/// The single source of truth for "where has this user been", shared by the map, the
/// stats tab, and the add-visit flow so a new visit shows up everywhere at once.
@MainActor
@Observable
final class VisitStore {
    private(set) var mapData: CountryMapData?
    private(set) var visits: [Visit] = []
    private(set) var visitedCountryCodes: Set<String> = []
    private(set) var isLoadingVisits = false
    /// Set when the bundled map data can't be read at all — the map then has nothing to
    /// draw, so this has to reach the screen rather than sit behind a spinner forever.
    private(set) var mapDataError: String?
    var errorMessage: String?

    private var hasLoadedMapData = false

    // MARK: - Loading

    func loadMapDataIfNeeded() async {
        guard !hasLoadedMapData else { return }
        do {
            mapData = try await GeoDataService.loadCountries()
            mapDataError = nil
            hasLoadedMapData = true
        } catch {
            mapDataError = error.localizedDescription
        }
    }

    func refreshVisits(userID: UUID) async {
        isLoadingVisits = true
        defer { isLoadingVisits = false }

        do {
            let service = try VisitsService()
            visits = try await service.fetchVisits(for: userID)
            visitedCountryCodes = Set(visits.map(\.countryCode))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Clears everything on sign-out, so the next account never sees the previous one's map.
    func clearUserData() {
        visits = []
        visitedCountryCodes = []
        errorMessage = nil
    }

    // MARK: - Mutations

    func addVisit(
        userID: UUID,
        countryCode: String,
        visitedAt: Date?,
        note: String?,
        photos: [UIImage]
    ) async throws {
        let service = try VisitsService()
        let visit = try await service.createVisit(
            userID: userID,
            countryCode: countryCode,
            visitedAt: visitedAt,
            note: note,
            photos: photos
        )
        visits.insert(visit, at: 0)
        visitedCountryCodes.insert(visit.countryCode)
    }

    func deleteVisit(_ visit: Visit) async {
        do {
            let service = try VisitsService()
            try await service.deleteVisit(id: visit.id)
            visits.removeAll { $0.id == visit.id }
            // A country stays filled in as long as any visit to it remains.
            if !visits.contains(where: { $0.countryCode == visit.countryCode }) {
                visitedCountryCodes.remove(visit.countryCode)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Derived state

    var countries: [Country] { mapData?.countries ?? [] }

    func hasVisited(_ code: String) -> Bool { visitedCountryCodes.contains(code) }

    func country(for code: String) -> Country? { mapData?.shape(for: code)?.country }

    /// Progress for one continent, or the whole world when `continent` is nil.
    func progress(for continent: Continent?) -> VisitProgress {
        guard let mapData else { return VisitProgress(visited: 0, total: 0) }

        guard let continent else {
            return VisitProgress(visited: visitedCountryCodes.count, total: mapData.countries.count)
        }

        let inContinent = mapData.countries.filter { $0.continent == continent }
        let visited = inContinent.filter { visitedCountryCodes.contains($0.code) }.count
        return VisitProgress(visited: visited, total: inContinent.count)
    }

    /// Every continent's progress, in the app's display order.
    var continentProgress: [(continent: Continent, progress: VisitProgress)] {
        Continent.displayOrder.map { ($0, progress(for: $0)) }
    }

    /// Visits to one country, newest first.
    func visits(to countryCode: String) -> [Visit] {
        visits.filter { $0.countryCode == countryCode }
    }
}
