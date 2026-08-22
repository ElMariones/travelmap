import SwiftUI

@main
struct TravelMapApp: App {
    @State private var session = SessionStore()
    @State private var visitStore = VisitStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(visitStore)
                .tint(AppTheme.accent)
        }
    }
}
