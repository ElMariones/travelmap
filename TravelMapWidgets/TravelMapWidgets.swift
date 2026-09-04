import AppIntents
import SwiftUI
import WidgetKit

@main
struct TravelMapWidgets: WidgetBundle {
    var body: some Widget {
        WorldProgressWidget()
    }
}

// MARK: - Configuration

/// The continent a widget is scoped to. "The world" is the default and is its own case
/// rather than a `nil` — an intent parameter that can be empty shows an empty picker.
enum ContinentScope: String, AppEnum {
    case world, europe, asia, africa, northAmerica, southAmerica, oceania

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Scope")

    static let caseDisplayRepresentations: [ContinentScope: DisplayRepresentation] = [
        .world: "The whole world",
        .europe: "Europe",
        .asia: "Asia",
        .africa: "Africa",
        .northAmerica: "North America",
        .southAmerica: "South America",
        .oceania: "Oceania",
    ]

    /// Matches `Continent.rawValue` in the app, which is what the snapshot is keyed by.
    var continentName: String? {
        switch self {
        case .world: return nil
        case .europe: return "Europe"
        case .asia: return "Asia"
        case .africa: return "Africa"
        case .northAmerica: return "North America"
        case .southAmerica: return "South America"
        case .oceania: return "Oceania"
        }
    }

    var title: String {
        switch self {
        case .world: return "World visited"
        default: return continentName ?? "World visited"
        }
    }
}

/// Long-press the widget and pick a continent. Several instances configured differently is
/// the point — one for the world, one for the continent you're working through.
struct WorldProgressIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Travel progress"
    static let description = IntentDescription("Choose how much of the world to show.")

    @Parameter(title: "Show", default: .world)
    var scope: ContinentScope
}

// MARK: - Timeline

struct TravelEntry: TimelineEntry {
    let date: Date
    let snapshot: TravelSnapshot
    let scope: ContinentScope
    /// True for the gallery preview, where the numbers are invented and shouldn't be
    /// presented as the user's own.
    var isPlaceholder = false
}

struct TravelProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> TravelEntry {
        TravelEntry(date: .now, snapshot: .placeholder, scope: .world, isPlaceholder: true)
    }

    func snapshot(for configuration: WorldProgressIntent, in context: Context) async -> TravelEntry {
        // The widget gallery has no real data to show yet, so it gets the sample map
        // rather than a convincing-looking zero.
        let stored = TravelSnapshotStore.read()
        return TravelEntry(
            date: .now,
            snapshot: stored ?? .placeholder,
            scope: configuration.scope,
            isPlaceholder: stored == nil
        )
    }

    func timeline(for configuration: WorldProgressIntent, in context: Context) async -> Timeline<TravelEntry> {
        let entry = TravelEntry(
            date: .now,
            snapshot: TravelSnapshotStore.read() ?? .empty,
            scope: configuration.scope
        )

        // `.never`, not an interval. Nothing here changes on a clock — it changes when the
        // user logs a visit, and the app calls `reloadTimelines` the moment it does.
        // Polling would spend the day's refresh budget redrawing an identical tile.
        return Timeline(entries: [entry], policy: .never)
    }

    func recommendations() -> [AppIntentRecommendation<WorldProgressIntent>] {
        [AppIntentRecommendation(intent: WorldProgressIntent(), description: "Travel progress")]
    }
}

// MARK: - Widget

struct WorldProgressWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: TravelSnapshotStore.widgetKind,
            intent: WorldProgressIntent.self,
            provider: TravelProvider()
        ) { entry in
            WidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Travel progress")
        .description("How much of the world you've filled in.")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryCircular, .accessoryRectangular, .accessoryInline,
        ])
    }
}

extension UIColor {
    /// The tile's own background. Named here rather than reaching for a system colour so
    /// it stays paired with the map's land colour in both appearances.
    static let widgetBackground = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.09, green: 0.09, blue: 0.10, alpha: 1)
            : UIColor(red: 0.98, green: 0.97, blue: 0.96, alpha: 1)
    }
}

/// Binds a timeline entry to the shared layout, and paints the tile's own background.
private struct WidgetEntryView: View {
    let entry: TravelEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        WorldProgressView(
            snapshot: entry.snapshot,
            continent: entry.scope.continentName,
            title: entry.scope.title,
            family: family,
            isPlaceholder: entry.isPlaceholder
        )
        // Required on iOS 17+: without it the system can't offer the removable-background
        // option and the widget falls back to a placeholder backing.
        .containerBackground(for: .widget) { Color(.widgetBackground) }
    }
}

#Preview("Small", as: .systemSmall) {
    WorldProgressWidget()
} timeline: {
    TravelEntry(date: .now, snapshot: .placeholder, scope: .world)
}

#Preview("Medium", as: .systemMedium) {
    WorldProgressWidget()
} timeline: {
    TravelEntry(date: .now, snapshot: .placeholder, scope: .world)
}

#Preview("Large", as: .systemLarge) {
    WorldProgressWidget()
} timeline: {
    TravelEntry(date: .now, snapshot: .placeholder, scope: .world)
}

#Preview("Circular", as: .accessoryCircular) {
    WorldProgressWidget()
} timeline: {
    TravelEntry(date: .now, snapshot: .placeholder, scope: .europe)
}
