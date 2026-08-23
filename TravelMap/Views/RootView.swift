import SwiftUI

/// Chooses between the setup screen, the landing screen, and the app itself.
struct RootView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
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
        .animation(AppTheme.Motion.bouncy, value: session.state)
        .task { session.startObserving() }
        .onChange(of: scenePhase) { _, phase in
            // Apple authorization can be revoked from Settings while the app is in the
            // background, where the revocation notification never reaches it.
            guard phase == .active else { return }
            Task { await session.verifyAppleAuthorization() }
        }
    }
}

/// Shown for the moment it takes to restore a stored session.
struct SplashView: View {
    @State private var isAnimating = false

    var body: some View {
        Image(systemName: "globe.europe.africa.fill")
            .font(.system(size: 56))
            .foregroundStyle(AppTheme.accent)
            .symbolEffect(.breathe, isActive: isAnimating)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground))
            .task { isAnimating = true }
    }
}

/// The three V1 tabs. Regions and friends are schema-ready but not built yet.
struct MainTabView: View {
    @Environment(SessionStore.self) private var session
    @Environment(VisitStore.self) private var visitStore

    var body: some View {
        TabView {
            Tab("Map", systemImage: "map.fill") {
                WorldMapScreen()
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
        .task(id: session.userID) {
            await visitStore.loadMapDataIfNeeded()
            if let userID = session.userID {
                await visitStore.refreshVisits(userID: userID)
            } else {
                visitStore.clearUserData()
            }
        }
    }
}
