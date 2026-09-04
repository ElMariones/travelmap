import Foundation
import MapKit
import Testing

@testable import TravelMap

// The fiddly logic, and only the fiddly logic. These are the pieces where a wrong answer
// is quiet: a percentage that rounds a real visit away to nothing, a milestone that
// replays every time the app relaunches, a date that slides a day backwards, a tap that
// lands on the wrong country. None of them throws, and all of them are wrong on screen.

// MARK: - Percentages

@Suite("VisitProgress")
struct VisitProgressTests {
    @Test("A single visit never rounds away to 0%")
    func singleVisitShowsAsLessThanOnePercent() {
        // One country out of 236 is 0.42%, which `Int(rounded())` renders as "0%" — the
        // one number the user is most certain is wrong.
        #expect(VisitProgress(visited: 1, total: 236).percentText == "<1%")
    }

    @Test("Genuinely zero reads as zero")
    func noVisitsShowsZero() {
        #expect(VisitProgress(visited: 0, total: 236).percentText == "0%")
    }

    @Test("An empty reference set doesn't divide by zero")
    func emptyTotalIsSafe() {
        let progress = VisitProgress(visited: 0, total: 0)
        #expect(progress.fraction == 0)
        #expect(progress.percentText == "0%")
    }

    @Test("Percentages round to the nearest whole", arguments: [
        (24, 100, "24%"),
        (245, 1000, "25%"),   // 24.5 rounds up
        (236, 236, "100%"),
        (3, 236, "1%"),       // 1.27% — above the floor, so no "<1%"
    ])
    func rounding(visited: Int, total: Int, expected: String) {
        #expect(VisitProgress(visited: visited, total: total).percentText == expected)
    }
}

// MARK: - Milestones

@Suite("Milestone.crossed")
struct MilestoneTests {
    private let countries: [Country] = [
        Country(code: "ES", name: "Spain", continent: .europe),
        Country(code: "FR", name: "France", continent: .europe),
        Country(code: "PT", name: "Portugal", continent: .europe),
        Country(code: "JP", name: "Japan", continent: .asia),
        Country(code: "TH", name: "Thailand", continent: .asia),
    ]

    @Test("The first country is a milestone")
    func firstCountry() {
        let crossed = Milestone.crossed(from: [], to: ["ES"], countries: countries)
        #expect(crossed.contains { $0.id == "count-1" })
    }

    @Test("Nothing is crossed when the map doesn't grow")
    func noChange() {
        #expect(Milestone.crossed(from: ["ES"], to: ["ES"], countries: countries).isEmpty)
    }

    @Test("Removing a country crosses nothing")
    func removal() {
        #expect(Milestone.crossed(from: ["ES", "FR"], to: ["ES"], countries: countries).isEmpty)
    }

    @Test("A milestone already reached doesn't fire again")
    func noReplay() {
        // Adding a second country when the first-country milestone is long past.
        let crossed = Milestone.crossed(from: ["ES"], to: ["ES", "FR"], countries: countries)
        #expect(!crossed.contains { $0.id == "count-1" })
    }

    @Test("Completing a continent is a milestone")
    func continentCompletion() {
        let crossed = Milestone.crossed(
            from: ["ES", "FR"],
            to: ["ES", "FR", "PT"],
            countries: countries
        )
        #expect(crossed.contains { $0.id == "continent-Europe" })
    }

    @Test("A continent already complete doesn't fire again")
    func continentNoReplay() {
        let crossed = Milestone.crossed(
            from: ["ES", "FR", "PT"],
            to: ["ES", "FR", "PT", "JP"],
            countries: countries
        )
        #expect(!crossed.contains { $0.id == "continent-Europe" })
    }

    @Test("Finishing a continent is reported before the count it also crosses")
    func continentOutranksCount() {
        // Both fire on the same save. The continent is the rarer, better story, so it has
        // to be the one the user sees first.
        let crossed = Milestone.crossed(from: [], to: ["ES"], countries: [countries[0]])
        #expect(crossed.first?.id == "continent-Europe")
        #expect(crossed.contains { $0.id == "count-1" })
    }

    @Test("A jump past several thresholds reports each of them")
    func multipleThresholds() {
        // Restoring a backup, or a very productive afternoon: 0 → 12 crosses 1, 5 and 10.
        let many = (1...12).map { Country(code: "C\($0)", name: "C\($0)", continent: .africa) }
        let crossed = Milestone.crossed(from: [], to: Set(many.map(\.code)), countries: many)
        let ids = Set(crossed.map(\.id))
        #expect(ids.isSuperset(of: ["count-1", "count-5", "count-10"]))
        #expect(!ids.contains("count-25"))
    }

    @Test("World-share milestones fire on the share, not the count")
    func worldShare() {
        // 5 countries out of 5 is 100%, which passes 10, 25, 50 and 75 all at once.
        let crossed = Milestone.crossed(from: [], to: ["ES", "FR", "PT", "JP", "TH"], countries: countries)
        let ids = Set(crossed.map(\.id))
        #expect(ids.isSuperset(of: ["share-10", "share-25", "share-50", "share-75"]))
    }
}

// MARK: - Dates

@Suite("PostgresDate")
struct PostgresDateTests {
    @Test("A date survives a round trip")
    func roundTrip() throws {
        let date = try #require(PostgresDate.date(from: "2026-08-23"))
        #expect(PostgresDate.string(from: date) == "2026-08-23")
    }

    @Test("Formatting uses the local day, not UTC's")
    func localDay() throws {
        // The bug this guards: a date picked as "23 August" late in the evening in a
        // positive-offset zone, formatted in UTC, stores the 22nd.
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 23
        components.hour = 23
        components.minute = 30
        let date = try #require(Calendar.current.date(from: components))
        #expect(PostgresDate.string(from: date) == "2026-08-23")
    }

    @Test("Nonsense doesn't parse")
    func rejectsGarbage() {
        #expect(PostgresDate.date(from: "not a date") == nil)
        #expect(PostgresDate.date(from: "2026-08-23T10:00:00Z") == nil)
    }

    @Test("Partial dates use the first day of their period")
    func partialDatesAreCanonical() throws {
        let year = try #require(PostgresDate.partialDate(year: 2024))
        let month = try #require(PostgresDate.partialDate(year: 2024, month: 7))
        #expect(PostgresDate.string(from: year) == "2024-01-01")
        #expect(PostgresDate.string(from: month) == "2024-07-01")
        #expect(PostgresDate.partialDate(year: 2024, month: 13) == nil)
    }
}

@Suite("Visit editing and chronology")
struct VisitEditingTests {
    private let userID = UUID()

    @Test("Travel date outranks creation date")
    func chronologyUsesTravelDate() throws {
        let olderDate = try #require(PostgresDate.date(from: "2020-01-01"))
        let newerDate = try #require(PostgresDate.date(from: "2025-01-01"))
        let olderTrip = Visit(
            userID: userID,
            countryCode: "ES",
            visitedAt: olderDate,
            datePrecision: .year,
            createdAt: Date(timeIntervalSince1970: 200)
        )
        let newerTrip = Visit(
            userID: userID,
            countryCode: "JP",
            visitedAt: newerDate,
            datePrecision: .year,
            createdAt: Date(timeIntervalSince1970: 100)
        )

        let sorted = [olderTrip, newerTrip].sorted { Visit.isLater($0, than: $1) }
        #expect(sorted.map(\.countryCode) == ["JP", "ES"])
    }

    @Test("Undated visits follow dated visits")
    func undatedVisitsAreLast() throws {
        let travelDate = try #require(PostgresDate.date(from: "2000-01-01"))
        let undated = Visit(
            userID: userID,
            countryCode: "ES",
            createdAt: Date(timeIntervalSince1970: 300)
        )
        let dated = Visit(
            userID: userID,
            countryCode: "JP",
            visitedAt: travelDate,
            datePrecision: .year,
            createdAt: Date(timeIntervalSince1970: 100)
        )

        let sorted = [undated, dated].sorted { Visit.isLater($0, than: $1) }
        #expect(sorted.map(\.countryCode) == ["JP", "ES"])
    }

    @Test("Clearing optional fields sends database nulls")
    func updatePayloadCanClearValues() throws {
        let payload = VisitUpdate(
            title: "Summer trip",
            visitedAt: nil,
            datePrecision: nil,
            note: nil,
            photoURLs: []
        )
        let data = try JSONEncoder().encode(payload)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["visited_at"] is NSNull)
        #expect(object["date_precision"] is NSNull)
        #expect(object["note"] is NSNull)
    }
}

// MARK: - Map hit testing

@Suite("MKPolygon.contains")
struct PolygonContainsTests {
    /// A square around the origin, in coordinate space.
    private func square() -> MKPolygon {
        var coordinates = [
            CLLocationCoordinate2D(latitude: 1, longitude: -1),
            CLLocationCoordinate2D(latitude: 1, longitude: 1),
            CLLocationCoordinate2D(latitude: -1, longitude: 1),
            CLLocationCoordinate2D(latitude: -1, longitude: -1),
        ]
        return MKPolygon(coordinates: &coordinates, count: coordinates.count)
    }

    @Test("A point inside is inside")
    func inside() {
        let point = MKMapPoint(CLLocationCoordinate2D(latitude: 0.5, longitude: 0.5))
        #expect(square().contains(point))
    }

    @Test("A point outside is outside")
    func outside() {
        let point = MKMapPoint(CLLocationCoordinate2D(latitude: 5, longitude: 5))
        #expect(!square().contains(point))
    }

    @Test("A point inside the bounding box but outside the shape is outside")
    func insideBoundingBoxOnly() {
        // The prefilter is a bounding-box test, so an L-shape is the case that separates
        // "the ray casting works" from "the bounding box happened to be enough".
        var coordinates = [
            CLLocationCoordinate2D(latitude: 2, longitude: 0),
            CLLocationCoordinate2D(latitude: 2, longitude: 1),
            CLLocationCoordinate2D(latitude: 1, longitude: 1),
            CLLocationCoordinate2D(latitude: 1, longitude: 2),
            CLLocationCoordinate2D(latitude: 0, longitude: 2),
            CLLocationCoordinate2D(latitude: 0, longitude: 0),
        ]
        let lShape = MKPolygon(coordinates: &coordinates, count: coordinates.count)
        // The missing corner of the L, well inside the bounding box.
        let point = MKMapPoint(CLLocationCoordinate2D(latitude: 1.7, longitude: 1.7))
        #expect(!lShape.contains(point))
    }

    @Test("A point in a hole is outside")
    func inHole() {
        var outer = [
            CLLocationCoordinate2D(latitude: 3, longitude: -3),
            CLLocationCoordinate2D(latitude: 3, longitude: 3),
            CLLocationCoordinate2D(latitude: -3, longitude: 3),
            CLLocationCoordinate2D(latitude: -3, longitude: -3),
        ]
        var hole = [
            CLLocationCoordinate2D(latitude: 1, longitude: -1),
            CLLocationCoordinate2D(latitude: 1, longitude: 1),
            CLLocationCoordinate2D(latitude: -1, longitude: 1),
            CLLocationCoordinate2D(latitude: -1, longitude: -1),
        ]
        let polygon = MKPolygon(
            coordinates: &outer,
            count: outer.count,
            interiorPolygons: [MKPolygon(coordinates: &hole, count: hole.count)]
        )

        #expect(polygon.contains(MKMapPoint(CLLocationCoordinate2D(latitude: 2, longitude: 2))))
        #expect(!polygon.contains(MKMapPoint(CLLocationCoordinate2D(latitude: 0, longitude: 0))))
    }
}

// MARK: - The widget's shared state

@Suite("TravelSnapshot")
struct TravelSnapshotTests {
    private let snapshot = TravelSnapshot(
        visitedCodes: ["FR", "ES", "JP"],
        totalCountries: 236,
        visitCount: 4,
        continentVisited: ["Europe": 2, "Asia": 1],
        continentTotals: ["Europe": 51, "Asia": 47],
        latestCountryCode: "JP",
        latestCountryName: "Japan",
        updatedAt: .now
    )

    @Test("Codes are stored sorted, so identical states encode identically")
    func sortedCodes() {
        #expect(snapshot.visitedCodes == ["ES", "FR", "JP"])
    }

    @Test("World progress counts every visited code")
    func worldProgress() {
        let progress = snapshot.progress(forContinent: nil)
        #expect(progress.visited == 3)
        #expect(progress.total == 236)
    }

    @Test("Continent progress reads the per-continent counts")
    func continentProgress() {
        let progress = snapshot.progress(forContinent: "Europe")
        #expect(progress.visited == 2)
        #expect(progress.total == 51)
    }

    @Test("An unknown continent is zero, not a crash")
    func unknownContinent() {
        let progress = snapshot.progress(forContinent: "Antarctica")
        #expect(progress == (0, 0))
        #expect(snapshot.percentText(forContinent: "Antarctica") == "0%")
    }

    @Test("The widget's percentage matches the app's")
    func percentMatchesApp() {
        // Two code paths render the same figure in two processes. They agree here or the
        // home screen quietly contradicts the app.
        let progress = snapshot.progress(forContinent: nil)
        let appText = VisitProgress(visited: progress.visited, total: progress.total).percentText
        #expect(snapshot.percentText(forContinent: nil) == appText)
    }

    @Test("A refresh that changes nothing visible doesn't count as a change")
    func visualEqualityIgnoresTimestamp() {
        var later = snapshot
        later.updatedAt = .now.addingTimeInterval(3600)
        #expect(snapshot.isVisuallyEqual(to: later))
        #expect(snapshot != later)

        later.visitCount += 1
        #expect(!snapshot.isVisuallyEqual(to: later))
    }
}

// MARK: - The widget's map

@Suite("WidgetWorldMap")
struct WidgetWorldMapTests {
    @Test("The bundled world decodes")
    func decodes() throws {
        let map = try #require(WidgetWorldMap.shared, "worldmap.json is missing from the bundle")
        #expect(map.countries.count == 236)
        #expect(map.grid > 0)
        #expect(map.height > 0)
    }

    @Test("Every country the app knows about can be drawn")
    func coversTheReferenceSet() async throws {
        let map = try #require(WidgetWorldMap.shared)
        let drawable = Set(map.countries.map(\.c))
        let reference = Set(try await GeoDataService.loadCountries().countries.map(\.code))

        // Micro-states simplify away to nothing at widget scale, so the build script gives
        // them a marker instead of dropping them. If that ever regresses, a user whose only
        // visit is Singapore sees an entirely empty map.
        #expect(reference.subtracting(drawable).isEmpty)
    }

    @Test("Every ring is a usable polygon")
    func ringsAreWellFormed() throws {
        let map = try #require(WidgetWorldMap.shared)
        for country in map.countries {
            #expect(!country.r.isEmpty, "\(country.c) has no rings")
            for ring in country.r {
                #expect(ring.count.isMultiple(of: 2), "\(country.c) has an odd coordinate count")
                #expect(ring.count >= 6, "\(country.c) has a ring with fewer than three points")
            }
        }
    }
}

// MARK: - Local regions

@Suite("Region map data")
struct RegionMapDataTests {
    @Test("The bundled region map decodes and covers Spain")
    func decodesBundledRegions() async throws {
        let data = try await GeoDataService.loadRegions()
        let spain = data.regions(in: "ES")

        #expect(data.regions.count == 4_477)
        #expect(spain.count == 52)
        #expect(spain.contains { $0.code == "ES-M" && $0.name == "Community of Madrid" })
        #expect(data.supportsRegionMode(countryCode: "ES"))
    }

    @Test("Countries with one subdivision skip region mode")
    func skipsSingleSubdivisionCountries() async throws {
        let data = try await GeoDataService.loadRegions()
        #expect(data.regions(in: "MC").count == 1)
        #expect(!data.supportsRegionMode(countryCode: "MC"))
    }

    @Test("A coordinate resolves to the tightest matching region")
    func regionHitTesting() async throws {
        let data = try await GeoDataService.loadRegions()
        let madrid = try #require(data.region(code: "ES-M"))
        let polygon = try #require(madridShape(in: data)?.multiPolygon.polygons.first)
        let coordinate = polygon.coordinate

        #expect(data.region(at: coordinate, countryCode: "ES")?.code == "ES-M")
    }

    private func madridShape(in data: RegionMapData) -> RegionShape? {
        data.shapes(in: "ES").first { $0.region.code == "ES-M" }
    }
}

@Suite("Region visits")
struct RegionVisitTests {
    private let userID = UUID()

    @Test("Progress counts distinct visited regions")
    func distinctProgress() {
        let progress = RegionProgress.make(
            regionCodes: ["ES-M", "ES-B", "ES-M"],
            total: 52
        )
        #expect(progress == VisitProgress(visited: 2, total: 52))
    }

    @Test("A region visit decodes Postgres dates")
    func decodesDate() throws {
        let json = """
        {
          "id":"00000000-0000-0000-0000-000000000001",
          "user_id":"00000000-0000-0000-0000-000000000002",
          "country_code":"ES",
          "region_code":"ES-M",
          "visited_at":"2025-06-01",
          "note":"A long weekend",
          "photo_urls":[],
          "created_at":"2026-01-01T10:00:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let visit = try decoder.decode(RegionVisit.self, from: Data(json.utf8))

        #expect(visit.regionCode == "ES-M")
        #expect(visit.visitedAt.map(PostgresDate.string(from:)) == "2025-06-01")
    }

    @Test("Region insert payload uses database keys and date format")
    func insertPayload() throws {
        let date = try #require(PostgresDate.date(from: "2025-06-01"))
        let payload = NewRegionVisit(
            id: UUID(),
            userID: userID,
            countryCode: "ES",
            regionCode: "ES-M",
            visitedAt: date,
            note: nil,
            photoURLs: []
        )
        let data = try JSONEncoder().encode(payload)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object["country_code"] as? String == "ES")
        #expect(object["region_code"] as? String == "ES-M")
        #expect(object["visited_at"] as? String == "2025-06-01")
    }

    @Test("Clearing a region date and note sends database nulls")
    func updatePayloadCanClearValues() throws {
        let payload = RegionVisitUpdate(visitedAt: nil, note: nil, photoURLs: [])
        let data = try JSONEncoder().encode(payload)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object["visited_at"] is NSNull)
        #expect(object["note"] is NSNull)
    }
}
