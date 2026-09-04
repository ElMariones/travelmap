import SwiftUI

/// Chooses between the setup screen, the landing screen, and the app itself.
struct RootView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            #if DEBUG
            if DebugLaunch.wantsWidgetPreview {
                NavigationStack { WidgetPreviewScreen() }
            } else if let screenshot = DebugLaunch.screenshot {
                ScreenshotShowcaseScreen(scene: screenshot)
            } else {
                content
            }
            #else
            content
            #endif
        }
        .animation(AppTheme.Motion.bouncy, value: session.state)
        .task {
            #if DEBUG
            guard DebugLaunch.screenshot == nil else { return }
            #endif
            session.startObserving()
        }
        .onChange(of: scenePhase) { _, phase in
            // Apple authorization can be revoked from Settings while the app is in the
            // background, where the revocation notification never reaches it.
            guard phase == .active else { return }
            Task { await session.verifyAppleAuthorization() }
        }
    }

    @ViewBuilder
    private var content: some View {
        Group {
            if !SupabaseEnvironment.isConfigured {
                SetupRequiredView()
            } else {
                switch session.state {
                case .restoring:
                    SplashView()
                case .signedOut:
                    LandingView()
                        .transition(.opacity.combined(with: .scale(scale: 1.04)))
                case .signedIn:
                    MainTabView()
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                }
            }
        }
    }
}

/// Shown for the moment it takes to restore a stored session.
struct SplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAnimating = false

    var body: some View {
        Image(systemName: "globe.europe.africa.fill")
            .font(.system(size: 56))
            .foregroundStyle(AppTheme.accent)
            .symbolEffect(.pulse, isActive: isAnimating && !reduceMotion)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground))
            .task { isAnimating = true }
            .accessibilityLabel("Loading TravelMap")
    }
}

/// The primary app tabs. Country details own the regional layer; friends remain V3.
struct MainTabView: View {
    @Environment(SessionStore.self) private var session
    @Environment(VisitStore.self) private var visitStore
    @Environment(CelebrationCenter.self) private var celebrations

    var body: some View {
        TabView {
            Tab("Map", systemImage: "map.fill") {
                WorldMapScreen()
            }
            Tab("Visits", systemImage: "suitcase.fill") {
                VisitsView()
            }
            Tab("Stats", systemImage: "chart.bar.fill") {
                StatsView()
            }
            Tab("Profile", systemImage: "person.crop.circle.fill") {
                ProfileView()
            }
        }
        // The map is the hero, so the tab bar shrinks out of the way as the user explores
        // and comes back the moment they scroll up.
        .tabBarMinimizeBehavior(.onScrollDown)
        // The overlay hangs here rather than on the map so a milestone crossed as the
        // add-visit sheet closes still lands somewhere visible, whichever tab is showing.
        .celebrationHost()
        // Loads and delete failures used to set `errorMessage` and stop there, which meant
        // a dropped connection looked exactly like an empty map.
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { visitStore.errorMessage != nil },
                set: { if !$0 { visitStore.errorMessage = nil } }
            ),
            presenting: visitStore.errorMessage
        ) { _ in
            Button("Try again") {
                guard let userID = session.userID else { return }
                Task { await visitStore.refreshVisits(userID: userID) }
            }
            Button("Dismiss", role: .cancel) {}
        } message: { message in
            Text(message)
        }
        #if DEBUG
        .task {
            guard DebugLaunch.wantsCelebration else { return }
            try? await Task.sleep(for: .seconds(1))
            celebrations.welcome(name: "Mario")
        }
        #endif
        .task(id: session.userID) {
            await visitStore.loadMapDataIfNeeded()
            if let userID = session.userID {
                await visitStore.refreshVisits(userID: userID)
                if let welcome = session.consumeWelcome() {
                    celebrations.welcome(name: welcome.name ?? session.profile?.displayName)
                }
            } else {
                visitStore.clearUserData()
            }
        }
    }
}
