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
    private(set) var regionMapData: RegionMapData?
    private(set) var visits: [Visit] = []
    private(set) var regionVisits: [RegionVisit] = []
    private(set) var visitedCountryCodes: Set<String> = []
    private(set) var visitedRegionCodes: Set<String> = []
    private(set) var isLoadingVisits = false
    /// Set when the bundled map data can't be read at all — the map then has nothing to
    /// draw, so this has to reach the screen rather than sit behind a spinner forever.
    private(set) var mapDataError: String?
    private(set) var regionDataError: String?
    var errorMessage: String?

    private var hasLoadedMapData = false

    // MARK: - Loading

    func loadMapDataIfNeeded() async {
        guard !hasLoadedMapData else { return }
        do {
            async let countries = GeoDataService.loadCountries()
            async let regions = GeoDataService.loadRegions()
            mapData = try await countries
            mapDataError = nil
            do {
                regionMapData = try await regions
                regionDataError = nil
            } catch {
                regionDataError = error.localizedDescription
            }
            hasLoadedMapData = true
            publishSnapshot()
        } catch {
            mapDataError = error.localizedDescription
        }
    }

    func refreshVisits(userID: UUID) async {
        isLoadingVisits = true
        defer { isLoadingVisits = false }

        do {
            let service = try VisitsService()
            let regionService = try RegionVisitsService()
            async let fetchedVisits = service.fetchVisits(for: userID)
            async let fetchedRegionVisits = regionService.fetchRegionVisits(for: userID)
            visits = try await fetchedVisits
            regionVisits = try await fetchedRegionVisits
            visitedCountryCodes = Set(visits.map(\.countryCode)).union(regionVisits.map(\.countryCode))
            visitedRegionCodes = Set(regionVisits.map(\.regionCode))
            errorMessage = nil
            publishSnapshot()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Clears everything on sign-out, so the next account never sees the previous one's map.
    func clearUserData() {
        visits = []
        regionVisits = []
        visitedCountryCodes = []
        visitedRegionCodes = []
        errorMessage = nil
        TravelSnapshotStore.clear()
        SignedURLCache.shared.clear()
    }

    // MARK: - Mutations

    /// Saves a visit and reports what it changed, so the caller can react proportionally —
    /// a repeat visit and a country that just went from gray to colour are not the same
    /// event, and neither is the save that finishes a continent.
    @discardableResult
    func addVisit(
        userID: UUID,
        countryCode: String,
        title: String,
        visitedAt: Date?,
        datePrecision: VisitDatePrecision?,
        note: String?,
        photos: [UIImage]
    ) async throws -> SaveOutcome {
        let service = try VisitsService()
        let visit = try await service.createVisit(
            userID: userID,
            countryCode: countryCode,
            title: title,
            visitedAt: visitedAt,
            datePrecision: datePrecision,
            note: note,
            photos: photos
        )

        let before = visitedCountryCodes
        visits.insert(visit, at: 0)
        visitedCountryCodes.insert(visit.countryCode)
        publishSnapshot()

        return SaveOutcome(
            filledANewCountry: !before.contains(visit.countryCode),
            milestones: Milestone.crossed(from: before, to: visitedCountryCodes, countries: countries)
        )
    }

    func updateVisit(
        _ visit: Visit,
        title: String,
        visitedAt: Date?,
        datePrecision: VisitDatePrecision?,
        note: String?,
        retainedPhotoPaths: [String],
        newPhotos: [UIImage]
    ) async throws {
        let service = try VisitsService()
        let updated = try await service.updateVisit(
            visit,
            title: title,
            visitedAt: visitedAt,
            datePrecision: datePrecision,
            note: note,
            retainedPhotoPaths: retainedPhotoPaths,
            newPhotos: newPhotos
        )
        guard let index = visits.firstIndex(where: { $0.id == updated.id }) else { return }
        visits[index] = updated
        errorMessage = nil
        publishSnapshot()
    }

    func deleteVisit(_ visit: Visit) async {
        do {
            let service = try VisitsService()
            try await service.deleteVisit(visit)
            visits.removeAll { $0.id == visit.id }
            // A country stays filled in as long as any visit to it remains.
            if !visits.contains(where: { $0.countryCode == visit.countryCode })
                && !regionVisits.contains(where: { $0.countryCode == visit.countryCode }) {
                visitedCountryCodes.remove(visit.countryCode)
            }
            publishSnapshot()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func addRegionVisit(
        userID: UUID,
        countryCode: String,
        regionCode: String,
        visitedAt: Date?,
        note: String?,
        photos: [UIImage]
    ) async throws -> Bool {
        let wasVisited = visitedRegionCodes.contains(regionCode)
        let service = try RegionVisitsService()
        let visit = try await service.createRegionVisit(
            userID: userID,
            countryCode: countryCode,
            regionCode: regionCode,
            visitedAt: visitedAt,
            note: note,
            photos: photos
        )
        regionVisits.insert(visit, at: 0)
        visitedRegionCodes.insert(regionCode)
        // A local-region visit necessarily means the country itself has been visited,
        // even when the user never creates a separate country-level trip card.
        visitedCountryCodes.insert(countryCode)
        publishSnapshot()
        errorMessage = nil
        return !wasVisited
    }

    func updateRegionVisit(
        _ visit: RegionVisit,
        visitedAt: Date?,
        note: String?,
        retainedPhotoPaths: [String],
        newPhotos: [UIImage]
    ) async throws {
        let service = try RegionVisitsService()
        let updated = try await service.updateRegionVisit(
            visit,
            visitedAt: visitedAt,
            note: note,
            retainedPhotoPaths: retainedPhotoPaths,
            newPhotos: newPhotos
        )
        guard let index = regionVisits.firstIndex(where: { $0.id == updated.id }) else { return }
        regionVisits[index] = updated
        errorMessage = nil
    }

    func deleteRegionVisit(_ visit: RegionVisit) async {
        do {
            let service = try RegionVisitsService()
            try await service.deleteRegionVisit(visit)
            regionVisits.removeAll { $0.id == visit.id }
            if !regionVisits.contains(where: { $0.regionCode == visit.regionCode }) {
                visitedRegionCodes.remove(visit.regionCode)
            }
            if !visits.contains(where: { $0.countryCode == visit.countryCode })
                && !regionVisits.contains(where: { $0.countryCode == visit.countryCode }) {
                visitedCountryCodes.remove(visit.countryCode)
            }
            publishSnapshot()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Derived state

    var countries: [Country] { mapData?.countries ?? [] }

    func hasVisited(_ code: String) -> Bool { visitedCountryCodes.contains(code) }

    func country(for code: String) -> Country? { mapData?.shape(for: code)?.country }

    func region(for code: String) -> Region? { regionMapData?.region(code: code) }

    func regions(in countryCode: String) -> [Region] { regionMapData?.regions(in: countryCode) ?? [] }

    func supportsRegionMode(countryCode: String) -> Bool {
        regionMapData?.supportsRegionMode(countryCode: countryCode) == true
    }

    func regionProgress(in countryCode: String) -> VisitProgress {
        let validCodes = Set(regions(in: countryCode).map(\.code))
        return RegionProgress.make(
            regionCodes: visitedRegionCodes.intersection(validCodes),
            total: validCodes.count
        )
    }

    func regionVisits(to regionCode: String) -> [RegionVisit] {
        regionVisits
            .filter { $0.regionCode == regionCode }
            .sorted { RegionVisit.isLater($0, than: $1) }
    }

    /// Country-level region percentages only exist after the user logs at least one
    /// subdivision; before that, showing a wall of zeroes would compete with world stats.
    var regionalCountryProgress: [(country: Country, progress: VisitProgress)] {
        Set(regionVisits.map(\.countryCode))
            .compactMap { code -> (Country, VisitProgress)? in
                guard let country = country(for: code) else { return nil }
                return (country, regionProgress(in: code))
            }
            .sorted { $0.0.name.localizedStandardCompare($1.0.name) == .orderedAscending }
    }

    /// Every logged trip by when it happened, newest first. Undated visits are kept at
    /// the end and remain stable by creation time.
    var chronologicalVisits: [Visit] {
        visits.sorted { Visit.isLater($0, than: $1) }
    }

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

    /// Visits to one country, newest trip first rather than newest database row first.
    func visits(to countryCode: String) -> [Visit] {
        chronologicalVisits.filter { $0.countryCode == countryCode }
    }

    /// The country logged most recently, by when the visit was *created* rather than when
    /// it happened — "the last thing you added" is the useful one on a home screen.
    var mostRecentCountry: Country? {
        visits.first.flatMap { country(for: $0.countryCode) }
    }

    /// The most recent trips, each country appearing once, ordered by when they happened.
    func recentCountries(limit: Int) -> [Country] {
        var seen: Set<String> = []
        var result: [Country] = []
        for visit in chronologicalVisits where seen.insert(visit.countryCode).inserted {
            if let country = country(for: visit.countryCode) { result.append(country) }
            if result.count == limit { break }
        }
        return result
    }

    // MARK: - Widget

    /// Hands the widget everything it draws.
    ///
    /// Called from every path that changes the visited set. The widget process can't read
    /// the app's memory or reach Supabase, so this shared file is the only thing standing
    /// between a home-screen tile and a stale number.
    private func publishSnapshot() {
        guard mapData != nil else { return }
        var visited: [String: Int] = [:]
        var totals: [String: Int] = [:]
        for country in countries {
            totals[country.continent.rawValue, default: 0] += 1
            if visitedCountryCodes.contains(country.code) {
                visited[country.continent.rawValue, default: 0] += 1
            }
        }

        TravelSnapshotStore.write(
            TravelSnapshot(
                visitedCodes: visitedCountryCodes,
                totalCountries: countries.count,
                visitCount: visits.count + regionVisits.count,
                continentVisited: visited,
                continentTotals: totals,
                latestCountryCode: visits.first?.countryCode,
                latestCountryName: mostRecentCountry?.name,
                updatedAt: .now
            )
        )
    }
}

#if DEBUG
extension VisitStore {
    /// Attractive, fixed content for README captures. It never opens a network client or
    /// writes the widget snapshot, so documentation work cannot alter a real account.
    func loadScreenshotData(userID: UUID) async {
        await loadMapDataIfNeeded()
        let madrid = PostgresDate.date(from: "2026-05-01")
        let barcelona = PostgresDate.date(from: "2025-08-01")
        let japan = PostgresDate.date(from: "2024-04-01")
        visits = [
            Visit(
                userID: userID,
                countryCode: "ES",
                title: "A summer through Spain",
                visitedAt: barcelona,
                datePrecision: .month,
                note: "Markets, late dinners and a train along the coast.",
                createdAt: Date(timeIntervalSince1970: 3)
            ),
            Visit(
                userID: userID,
                countryCode: "JP",
                title: "Tokyo in bloom",
                visitedAt: japan,
                datePrecision: .month,
                note: "First stop on a long-awaited trip across Japan.",
                createdAt: Date(timeIntervalSince1970: 2)
            ),
            Visit(
                userID: userID,
                countryCode: "FR",
                title: "Weekend in Paris",
                visitedAt: PostgresDate.date(from: "2023-10-01"),
                datePrecision: .month,
                createdAt: Date(timeIntervalSince1970: 1)
            ),
        ]
        regionVisits = [
            RegionVisit(
                userID: userID,
                countryCode: "ES",
                regionCode: "ES-M",
                visitedAt: madrid,
                note: "Museums, Retiro and a perfect sunset from the Temple of Debod.",
                createdAt: Date(timeIntervalSince1970: 6)
            ),
            RegionVisit(
                userID: userID,
                countryCode: "ES",
                regionCode: "ES-B",
                visitedAt: barcelona,
                note: "Architecture walks and the Mediterranean.",
                createdAt: Date(timeIntervalSince1970: 5)
            ),
            RegionVisit(userID: userID, countryCode: "ES", regionCode: "ES-V", createdAt: Date(timeIntervalSince1970: 4)),
            RegionVisit(userID: userID, countryCode: "ES", regionCode: "ES-A", createdAt: Date(timeIntervalSince1970: 3)),
            RegionVisit(userID: userID, countryCode: "ES", regionCode: "ES-SE", createdAt: Date(timeIntervalSince1970: 2)),
        ]
        visitedRegionCodes = Set(regionVisits.map(\.regionCode))
        visitedCountryCodes = Set(visits.map(\.countryCode)).union(regionVisits.map(\.countryCode))
        errorMessage = nil
    }
}
#endif
