import SwiftUI

/// The app's whole palette. One accent for "visited", neutral gray for everything else.
enum AppTheme {
    /// Visited countries, the tab bar tint, and primary actions.
    static let accent = Color("AccentColor")
    /// Every country you haven't logged yet.
    static let unvisitedLand = Color("UnvisitedLand")

    /// Hairline between neighbouring countries on the map.
    static let borderOpacity = 0.35
    static let borderWidth: CGFloat = 0.4

    /// Fill opacity for country polygons — solid enough to hide the base map's terrain,
    /// so the map reads as two colours and nothing else.
    static let landOpacity = 0.92
}
