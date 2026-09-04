import SwiftUI
import WidgetKit

/// Picks the layout for the family the system asked for.
///
/// Each family is designed rather than scaled: a small widget that is the medium one
/// squashed always reads as a mistake, and the small one has room for about four facts
/// before it stops being glanceable.
///
/// It lives in `Shared` and takes its family as a parameter rather than reading
/// `@Environment(\.widgetFamily)`, so the app can render the same views in a debug
/// harness. Iterating on a widget layout otherwise means a build, a long-press on the
/// home screen, and a trip through the widget gallery for every change.
struct WorldProgressView: View {
    let snapshot: TravelSnapshot
    /// `Continent.rawValue`, or nil for the whole world.
    let continent: String?
    /// What this widget calls its scope — "World visited", "Europe", …
    let title: String
    let family: WidgetFamily
    /// True for the gallery preview, whose numbers are invented.
    var isPlaceholder = false

    private var progress: (visited: Int, total: Int) { snapshot.progress(forContinent: continent) }
    private var percent: String { snapshot.percentText(forContinent: continent) }
    private var scopeName: String { continent == nil ? "the world" : title }

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .accessoryInline: inline
        case .systemMedium: medium
        case .systemLarge: large
        default: small
        }
    }

    // MARK: - Home screen

    /// Small: the number, then the map. Three facts and one tap target — the whole tile.
    ///
    /// The number leads because it's the thing worth a one-second glance; the map is what
    /// makes it worth glancing at twice. The world is a wide, shallow band, so it sits at
    /// the bottom rather than centred in a square with dead air above and below it.
    private var small: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(percent)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(WidgetTheme.accent)
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            Text("\(progress.visited) of \(progress.total)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)

            Spacer(minLength: 6)

            map
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetAccessibility(self)
    }

    /// Medium: the map keeps its shape and the numbers get a column of their own, rather
    /// than the small layout stretched sideways.
    private var medium: some View {
        HStack(spacing: 16) {
            map

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(percent)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(WidgetTheme.accent)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                Text("\(progress.visited) of \(progress.total) countries")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                if let latest = snapshot.latestCountryName {
                    Label(latest, systemImage: "mappin.and.ellipse")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .widgetAccessibility(self)
    }

    /// Large: room for the continent breakdown, which is the one thing the app's own map
    /// screen can only show one continent at a time.
    private var large: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(percent)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(WidgetTheme.accent)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                    Text("\(progress.visited) of \(progress.total) countries")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            map
                .frame(maxHeight: .infinity)

            if continent == nil {
                breakdown
            } else if let latest = snapshot.latestCountryName {
                Label("Last logged: \(latest)", systemImage: "mappin.and.ellipse")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .widgetAccessibility(self)
    }

    private var breakdown: some View {
        // Two columns of three: six continents fit a large widget exactly, and a grid
        // keeps them from reflowing into an odd shape as the numbers change width.
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 6) {
            ForEach(WidgetTheme.continentOrder, id: \.self) { name in
                let bar = snapshot.progress(forContinent: name)
                HStack(spacing: 6) {
                    Text(WidgetTheme.shortName(name))
                        .font(.caption2)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text("\(bar.visited)/\(bar.total)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Lock screen
    //
    // Accessory families render into a single tint, so anything that relies on the accent
    // colour to carry meaning disappears here. These lean on the gauge and the numbers.

    private var circular: some View {
        Gauge(value: snapshot.fraction(forContinent: continent)) {
            Image(systemName: "globe.europe.africa.fill")
        } currentValueLabel: {
            Text(percent.replacingOccurrences(of: "%", with: ""))
                .font(.caption.weight(.semibold))
                .minimumScaleFactor(0.7)
        }
        .gaugeStyle(.accessoryCircular)
        .widgetAccessibility(self)
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
            Text("\(percent) · \(progress.visited)/\(progress.total)")
                .font(.caption2.monospacedDigit())
            Gauge(value: snapshot.fraction(forContinent: continent)) { EmptyView() }
                .gaugeStyle(.accessoryLinearCapacity)
        }
        .widgetAccessibility(self)
    }

    private var inline: some View {
        // Inline gets one line with no wrapping, so it says the least that still means
        // something: the share, and what of.
        Label("\(percent) of \(scopeName)", systemImage: "globe.europe.africa.fill")
            .widgetAccessibility(self)
    }

    // MARK: - Pieces

    private var map: some View {
        WidgetWorldMapView(
            visitedCodes: Set(snapshot.visitedCodes),
            continent: continent,
            visitedColor: WidgetTheme.accent,
            landColor: WidgetTheme.land
        )
        .frame(maxWidth: .infinity)
        // A gallery preview drawn from invented data shouldn't look like a real map the
        // user forgot they made.
        .opacity(isPlaceholder ? 0.65 : 1)
    }
}

/// One spoken sentence per widget, whatever the family.
///
/// A widget that reads out as "42 percent, 99 of 236, Japan" is three fragments with no
/// subject. VoiceOver users get the same sentence everywhere instead.
private extension View {
    func widgetAccessibility(_ view: WorldProgressView) -> some View {
        let progress = view.snapshot.progress(forContinent: view.continent)
        let scope = view.continent == nil ? "the world" : view.title

        return accessibilityElement(children: .ignore)
            .accessibilityLabel("Travel progress")
            .accessibilityValue(
                "\(view.snapshot.percentText(forContinent: view.continent)) of \(scope) visited, "
                    + "\(progress.visited) of \(progress.total) countries"
            )
    }
}

enum WidgetTheme {
    static let accent = Color("AccentColor")

    /// Everywhere not yet logged. Deliberately low-contrast against the tile: the filled
    /// countries are the content, and the rest is context.
    static let land = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0.26, alpha: 1)
            : UIColor(white: 0.84, alpha: 1)
    })

    static let continentOrder = ["Europe", "Asia", "Africa", "North America", "South America", "Oceania"]

    static func shortName(_ continent: String) -> String {
        switch continent {
        case "North America": return "N. America"
        case "South America": return "S. America"
        default: return continent
        }
    }
}
