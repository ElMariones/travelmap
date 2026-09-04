import Foundation
import WidgetKit

/// Everything the widget needs to draw, in one small value.
///
/// This type is compiled into **both** the app and the widget extension. The widget runs
/// in its own process: it cannot read the app's memory, and it has no Supabase session to
/// fetch with. So the app writes this after every change to the visited set, and the
/// widget only ever reads it.
///
/// It carries counts rather than the visit rows themselves. A widget has a 40 MB ceiling
/// and about a second of the user's attention, and neither is spent well on notes and
/// photo paths it will never show.
struct TravelSnapshot: Codable, Sendable, Equatable {
    /// ISO alpha-2 codes, sorted so identical states encode identically.
    var visitedCodes: [String]
    var totalCountries: Int
    var visitCount: Int
    /// Keyed by `Continent.rawValue`, so the widget doesn't need the `Continent` enum.
    var continentVisited: [String: Int]
    var continentTotals: [String: Int]
    var latestCountryCode: String?
    var latestCountryName: String?
    var updatedAt: Date

    init(
        visitedCodes: some Sequence<String>,
        totalCountries: Int,
        visitCount: Int,
        continentVisited: [String: Int],
        continentTotals: [String: Int],
        latestCountryCode: String?,
        latestCountryName: String?,
        updatedAt: Date
    ) {
        self.visitedCodes = visitedCodes.sorted()
        self.totalCountries = totalCountries
        self.visitCount = visitCount
        self.continentVisited = continentVisited
        self.continentTotals = continentTotals
        self.latestCountryCode = latestCountryCode
        self.latestCountryName = latestCountryName
        self.updatedAt = updatedAt
    }

    // MARK: - Derived

    /// Visited and total for one continent, or for the world when `continent` is nil.
    /// Same shape as the app's `VisitProgress`, deliberately: the widget's number and the
    /// app's number are the same number, and they should never be computed two ways.
    func progress(forContinent continent: String?) -> (visited: Int, total: Int) {
        guard let continent else { return (visitedCodes.count, totalCountries) }
        return (continentVisited[continent] ?? 0, continentTotals[continent] ?? 0)
    }

    func fraction(forContinent continent: String?) -> Double {
        let progress = self.progress(forContinent: continent)
        return progress.total > 0 ? Double(progress.visited) / Double(progress.total) : 0
    }

    /// Whole percent, except that one country shouldn't round away to "0%".
    func percentText(forContinent continent: String?) -> String {
        let percent = fraction(forContinent: continent) * 100
        if percent > 0, percent < 1 { return "<1%" }
        return "\(Int(percent.rounded()))%"
    }

    /// What the widget shows before the app has ever written a snapshot, and what the
    /// gallery preview shows. Deliberately non-empty: a widget previewing as all zeroes
    /// looks broken rather than new.
    static let placeholder = TravelSnapshot(
        visitedCodes: ["ES", "FR", "PT", "IT", "MA", "JP", "US", "MX", "IS", "GR", "TR", "TH"],
        totalCountries: 236,
        visitCount: 18,
        continentVisited: ["Europe": 7, "Asia": 2, "Africa": 1, "North America": 2],
        continentTotals: ["Europe": 51, "Asia": 47, "Africa": 55, "North America": 37,
                          "South America": 14, "Oceania": 25],
        latestCountryCode: "JP",
        latestCountryName: "Japan",
        updatedAt: .distantPast
    )

    /// The state a signed-out or brand-new account is in.
    static let empty = TravelSnapshot(
        visitedCodes: [],
        totalCountries: 236,
        visitCount: 0,
        continentVisited: [:],
        continentTotals: [:],
        latestCountryCode: nil,
        latestCountryName: nil,
        updatedAt: .distantPast
    )
}

/// Reads and writes the snapshot in the App Group both targets share.
///
/// The app group is the only channel between the two processes, and a mismatch between
/// the two ends of it fails *silently*: writes go nowhere and the widget shows its
/// placeholder for ever, with nothing logged anywhere.
///
/// So the identifier isn't written here at all. `APP_GROUP_ID` in `project.yml` is
/// stamped into both targets' entitlements and both targets' Info.plists, and this reads
/// it back out — which means the string the code uses is by construction the same string
/// the entitlement grants. Renaming the group is one line in `project.yml`.
enum TravelSnapshotStore {
    /// Nil when the app group is missing from Info.plist, or when the entitlement was
    /// stripped — which is what happens on a free personal team, where App Groups aren't
    /// available. The app still works; the widget just has nothing to show.
    static let appGroup = Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String

    static let widgetKind = "TravelMapProgress"

    private static let key = "travel.snapshot"

    private static var defaults: UserDefaults? {
        guard let appGroup, !appGroup.isEmpty else { return nil }
        return UserDefaults(suiteName: appGroup)
    }

    static func write(_ snapshot: TravelSnapshot) {
        guard let defaults, let data = try? JSONEncoder().encode(snapshot) else { return }
        // Skip the reload when nothing a widget draws has changed. `updatedAt` moves on
        // every refresh, so it's excluded from the comparison — otherwise every launch
        // would spend one of the day's limited reload budget on an identical redraw.
        let previous = read()
        defaults.set(data, forKey: key)
        guard previous?.isVisuallyEqual(to: snapshot) != true else { return }
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }

    static func read() -> TravelSnapshot? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(TravelSnapshot.self, from: data)
    }

    /// Sign-out clears it, so the next account never sees the previous one's map on the
    /// home screen — where it would sit in plain view of anyone holding the phone.
    static func clear() {
        defaults?.removeObject(forKey: key)
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }
}

extension TravelSnapshot {
    /// Equality over everything the widget actually renders.
    func isVisuallyEqual(to other: TravelSnapshot) -> Bool {
        visitedCodes == other.visitedCodes
            && totalCountries == other.totalCountries
            && visitCount == other.visitCount
            && continentVisited == other.continentVisited
            && continentTotals == other.continentTotals
            && latestCountryCode == other.latestCountryCode
            && latestCountryName == other.latestCountryName
    }
}
