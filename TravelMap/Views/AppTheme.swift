import SwiftUI

/// The app's design tokens, and the Liquid Glass rules the views follow.
///
/// ## Where glass is allowed
///
/// Glass belongs to the *control* layer — things that float above content. It is never a
/// background for content itself. In this app that means: the map's percentage badge,
/// its continent chips, and its primary action float in glass over the map; cards inside
/// sheets and lists do not.
///
/// ## Never glass on glass
///
/// A glass surface samples what is behind it. Stacking two of them samples a sample, and
/// the result goes cloudy and loses its edge definition. So:
///
/// - Sheets, the tab bar, and navigation bars are *already* system glass. Nothing inside
///   them gets `.glassEffect`.
/// - Sibling glass shapes inside a `GlassEffectContainer` are fine and encouraged — that
///   is how they blend and morph into one another. What is forbidden is *nesting*.
///
/// ## Regular versus Clear
///
/// - ``regularGlass`` is the default. It adapts to whatever is behind it and brings its
///   own legibility handling, so it is the only safe choice over unpredictable content —
///   the map, where the user may be over pale ocean or dark terrain.
/// - ``clearGlass`` is more transparent and does *not* guarantee legibility on its own.
///   Apple's rule is that it is only for content you control and dim yourself. The one
///   place this app uses it is the landing screen, over its own mesh gradient, behind a
///   deliberate dimming layer — see ``LandingView``.
enum AppTheme {
    /// The single accent. Visited countries, the tab tint, primary actions.
    static let accent = Color("AccentColor")
    /// Every country not yet logged.
    static let unvisitedLand = Color("UnvisitedLand")

    // MARK: - Glass

    /// Default glass for controls floating over arbitrary content.
    static let regularGlass: Glass = .regular

    /// Interactive glass — reacts to touch with the system's own press response. Use for
    /// anything tappable so the material and the gesture stay in sync.
    static let interactiveGlass: Glass = .regular.interactive()

    /// The one tinted glass in the app, reserved for the single primary action so the
    /// tint keeps meaning something.
    static var accentGlass: Glass { .regular.tint(accent).interactive() }

    /// Transparent glass. Only over content this app dims itself. See the type docs.
    static let clearGlass: Glass = .clear

    // MARK: - Map fills

    /// Hairline between neighbouring countries.
    static let borderOpacity = 0.35
    static let borderWidth: CGFloat = 0.4

    /// Country polygons are nearly opaque so the map reads as two colours and nothing
    /// else — the base map's terrain would otherwise fight the accent.
    static let landOpacity = 0.92

    // MARK: - Motion

    /// Springs, not durations. A spring absorbs a new target mid-flight, which is what
    /// makes a re-tap during an animation feel answered instead of queued.
    enum Motion {
        /// Small state flips: chip selection, toggles, badge swaps.
        static let snappy = Animation.snappy(duration: 0.32, extraBounce: 0.08)
        /// Things that appear or grow — sheets, cards, the map filling in.
        static let bouncy = Animation.bouncy(duration: 0.5, extraBounce: 0.16)
        /// Continuous, low-energy motion that shouldn't draw the eye.
        static let gentle = Animation.smooth(duration: 0.7)
        /// Morphing between glass shapes inside a container.
        static let morph = Animation.spring(response: 0.45, dampingFraction: 0.78)
    }
}
