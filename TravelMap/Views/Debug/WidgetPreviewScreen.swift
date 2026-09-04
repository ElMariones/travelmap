#if DEBUG
import SwiftUI
import WidgetKit

/// Debug-only launch switches, read once at startup.
enum DebugLaunch {
    /// `-widgetPreview` opens straight onto ``WidgetPreviewScreen``, skipping auth and the
    /// tab bar. It exists so the widget layouts can be built, launched and screenshotted
    /// in one command instead of navigated to by hand.
    static let wantsWidgetPreview = ProcessInfo.processInfo.arguments.contains("-widgetPreview")

    /// `-celebrate` fires a sample celebration on launch. Confetti timing and density are
    /// the sort of thing you have to *watch*, and getting there for real means creating an
    /// account or logging the twenty-fifth country.
    static let wantsCelebration = ProcessInfo.processInfo.arguments.contains("-celebrate")

    /// Opens a deterministic, network-free screen for documentation screenshots.
    static let screenshot: ScreenshotScene? = ScreenshotScene.allCases.first {
        ProcessInfo.processInfo.arguments.contains("-shot-\($0.rawValue)")
    }
}

enum ScreenshotScene: String, CaseIterable {
    case intro
    case map
    case country
    case add
    case region
    case regionAdd = "region-add"
    case visits
    case stats
    case profile
}

/// Every widget family, at its real point size, inside the app.
///
/// Debug builds only. Iterating on a widget layout otherwise means a build, a long-press
/// on the Home Screen, a trip through the widget gallery, and a wait for the system to
/// decide to re-render — for each change. This shows the same views the extension does,
/// from the same snapshot, in a second.
///
/// It is not a substitute for looking at the real thing: the system supplies the tile's
/// material, corner radius and tint, and the accessory families render into a single
/// colour that only the Lock Screen applies. Layout and content are what this checks.
struct WidgetPreviewScreen: View {
    @State private var useLiveData = true
    @State private var scope: String?

    private var snapshot: TravelSnapshot {
        useLiveData ? (TravelSnapshotStore.read() ?? .empty) : .placeholder
    }

    /// The point sizes iOS gives each family on a 6.1" phone. Close enough to judge
    /// whether text fits, which is the thing that actually breaks.
    private static let homeSizes: [(WidgetFamily, CGSize)] = [
        (.systemSmall, CGSize(width: 170, height: 170)),
        (.systemMedium, CGSize(width: 364, height: 170)),
        (.systemLarge, CGSize(width: 364, height: 382)),
    ]

    private static let accessorySizes: [(WidgetFamily, CGSize)] = [
        (.accessoryCircular, CGSize(width: 76, height: 76)),
        (.accessoryRectangular, CGSize(width: 172, height: 76)),
        (.accessoryInline, CGSize(width: 240, height: 26)),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                controls

                // Lock Screen first: three small tiles fit one row, and putting them
                // under the large widget would push them off the bottom of every
                // screenshot taken of this screen.
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        ForEach(Self.accessorySizes.prefix(2), id: \.0) { family, size in
                            tile(family, size: size, background: Color(white: 0.2))
                        }
                    }
                    ForEach(Self.accessorySizes.suffix(1), id: \.0) { family, size in
                        tile(family, size: size, background: Color(white: 0.2))
                    }
                }
                // Accessory widgets render into the Lock Screen's vibrancy, which is
                // roughly a white tint over the wallpaper. Dark grey stands in.
                .environment(\.colorScheme, .dark)

                ForEach(Self.homeSizes, id: \.0) { family, size in
                    tile(family, size: size, background: Color(.widgetPreviewBackground))
                }
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Widget preview")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Your data", isOn: $useLiveData)

            Picker("Scope", selection: $scope) {
                Text("World").tag(String?.none)
                ForEach(Continent.displayOrder) { continent in
                    Text(continent.shortName).tag(String?.some(continent.rawValue))
                }
            }
            .pickerStyle(.menu)

            if useLiveData, TravelSnapshotStore.read() == nil {
                Label(
                    "No snapshot written yet — log a visit, or switch to sample data.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
    }

    private func tile(_ family: WidgetFamily, size: CGSize, background: Color) -> some View {
        WorldProgressView(
            snapshot: snapshot,
            continent: scope,
            title: scope ?? "World visited",
            family: family,
            isPlaceholder: !useLiveData
        )
        .padding(family == .accessoryInline ? 4 : 14)
        .frame(width: size.width, height: size.height)
        .background(background, in: .rect(cornerRadius: family == .accessoryCircular ? size.width / 2 : 22))
        .frame(maxWidth: .infinity)
    }
}

private extension UIColor {
    /// Stands in for the tile material the system provides in a real widget.
    static let widgetPreviewBackground = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.09, green: 0.09, blue: 0.10, alpha: 1)
            : UIColor(red: 0.98, green: 0.97, blue: 0.96, alpha: 1)
    }
}
#endif
