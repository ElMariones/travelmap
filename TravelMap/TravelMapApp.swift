import SwiftUI

@main
struct TravelMapApp: App {
    @State private var haptics: Haptics
    @State private var session = SessionStore()
    @State private var visitStore = VisitStore()
    @State private var celebrations: CelebrationCenter

    @Environment(\.scenePhase) private var scenePhase

    init() {
        let haptics = Haptics()
        _haptics = State(initialValue: haptics)
        _celebrations = State(initialValue: CelebrationCenter(haptics: haptics))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(visitStore)
                .environment(haptics)
                .environment(celebrations)
                .tint(AppTheme.accent)
                .onChange(of: scenePhase) { _, phase in
                    // A haptic engine left running in the background burns power and gets
                    // killed out from under us anyway; the next event lazily starts a new one.
                    if phase != .active { haptics.stopEngine() }
                }
        }
    }
}
