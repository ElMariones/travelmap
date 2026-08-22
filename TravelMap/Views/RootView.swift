import SwiftUI

/// Chooses between the setup screen, the auth screen, and the app itself.
struct RootView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        Group {
            if !SupabaseEnvironment.isConfigured {
                SetupRequiredView()
            } else {
                switch session.state {
                case .restoring:
                    SplashView()
                case .signedOut:
                    AuthView()
                case .signedIn:
                    MainTabView()
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: session.state)
        .task { session.startObserving() }
    }
}

/// Shown for the moment it takes to restore a stored session.
struct SplashView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "globe.europe.africa.fill")
                .font(.system(size: 56))
                .foregroundStyle(AppTheme.accent)
            ProgressView()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

/// The three V1 tabs. Regions and friends are schema-ready but not built yet.
struct MainTabView: View {
    @Environment(SessionStore.self) private var session
    @Environment(VisitStore.self) private var visitStore

    var body: some View {
        TabView {
            WorldMapScreen()
                .tabItem { Label("Map", systemImage: "map.fill") }

            StatsView()
                .tabItem { Label("Stats", systemImage: "chart.bar.fill") }

            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle.fill") }
        }
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
