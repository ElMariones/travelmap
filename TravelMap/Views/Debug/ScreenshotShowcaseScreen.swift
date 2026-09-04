#if DEBUG
import SwiftUI

/// Renders real production views with deterministic in-memory data for README captures.
/// Launch with `-shot-map`, `-shot-country`, `-shot-region-add`, and the other cases in
/// `ScreenshotScene`; no authentication or database mutation is involved.
struct ScreenshotShowcaseScreen: View {
    let scene: ScreenshotScene

    @Environment(SessionStore.self) private var session
    @Environment(VisitStore.self) private var visitStore
    @State private var isReady = false

    private let userID = UUID(uuidString: "00000000-0000-0000-0000-000000000042")!

    var body: some View {
        Group {
            if scene == .intro {
                LandingView()
            } else if isReady {
                content
            } else {
                SplashView()
            }
        }
        .task {
            guard scene != .intro else { return }
            session.loadScreenshotProfile(userID: userID)
            await visitStore.loadScreenshotData(userID: userID)
            isReady = true
        }
    }

    @ViewBuilder
    private var content: some View {
        switch scene {
        case .intro:
            LandingView()
        case .map:
            ScreenshotTabShell(selection: .map)
        case .visits:
            ScreenshotTabShell(selection: .visits)
        case .stats:
            ScreenshotTabShell(selection: .stats)
        case .profile:
            ScreenshotTabShell(selection: .profile)
        case .country:
            if let spain = visitStore.country(for: "ES") {
                NavigationStack { CountryDetailContent(country: spain) }
            }
        case .add:
            if let spain = visitStore.country(for: "ES") {
                NavigationStack { VisitFormView(country: spain, onSaved: {}) }
            }
        case .region:
            if let spain = visitStore.country(for: "ES"), let madrid = visitStore.region(for: "ES-M") {
                NavigationStack { RegionDetailContent(country: spain, region: madrid) }
            }
        case .regionAdd:
            if let spain = visitStore.country(for: "ES"), let madrid = visitStore.region(for: "ES-M") {
                NavigationStack { RegionVisitFormView(country: spain, region: madrid, onSaved: {}) }
            }
        }
    }
}

private enum ScreenshotTab: Hashable {
    case map
    case visits
    case stats
    case profile
}

/// Mirrors the production tab shell while allowing a launch argument to pick the screen.
private struct ScreenshotTabShell: View {
    @State private var selection: ScreenshotTab

    init(selection: ScreenshotTab) {
        _selection = State(initialValue: selection)
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab("Map", systemImage: "map.fill", value: .map) { WorldMapScreen() }
            Tab("Visits", systemImage: "suitcase.fill", value: .visits) { VisitsView() }
            Tab("Stats", systemImage: "chart.bar.fill", value: .stats) { StatsView() }
            Tab("Profile", systemImage: "person.crop.circle.fill", value: .profile) { ProfileView() }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}
#endif
