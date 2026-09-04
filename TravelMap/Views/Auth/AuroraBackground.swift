import SwiftUI

/// The slowly drifting mesh behind the landing screen.
///
/// This is *content*, not glass — it's what the clear glass above it samples. Because the
/// app controls it, it can also guarantee the dimming that clear glass needs to stay
/// legible, which is exactly the condition under which clear glass is allowed at all.
struct AuroraBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Redraw rate. The motion is a slow drift, so a third of display refresh is
    /// indistinguishable from full rate and costs a lot less.
    private static let frameInterval = 1.0 / 30.0

    private static let palette: [Color] = [
        Color(.sRGB, red: 0.99, green: 0.62, blue: 0.42, opacity: 1),
        Color(.sRGB, red: 0.97, green: 0.42, blue: 0.28, opacity: 1),
        Color(.sRGB, red: 0.86, green: 0.26, blue: 0.30, opacity: 1),
        Color(.sRGB, red: 0.98, green: 0.74, blue: 0.50, opacity: 1),
        Color(.sRGB, red: 0.93, green: 0.36, blue: 0.31, opacity: 1),
        Color(.sRGB, red: 0.55, green: 0.19, blue: 0.38, opacity: 1),
        Color(.sRGB, red: 0.95, green: 0.51, blue: 0.35, opacity: 1),
        Color(.sRGB, red: 0.71, green: 0.23, blue: 0.36, opacity: 1),
        Color(.sRGB, red: 0.29, green: 0.13, blue: 0.31, opacity: 1),
    ]

    var body: some View {
        if reduceMotion {
            // The same mesh, frozen. Reduce Motion asks for less movement, not for a flat
            // colour — the gradient is the screen's identity and it survives standing still.
            MeshGradient(width: 3, height: 3, points: points(at: 0), colors: Self.palette)
        } else {
            TimelineView(.animation(minimumInterval: Self.frameInterval)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                MeshGradient(width: 3, height: 3, points: points(at: t), colors: Self.palette)
            }
        }
    }

    /// The four corners stay pinned so the mesh never tears away from the edges; the
    /// midpoints and centre wander on offset sine waves.
    private func points(at t: TimeInterval) -> [SIMD2<Float>] {
        func drift(_ base: SIMD2<Float>, _ amount: SIMD2<Float>, _ phase: Double) -> SIMD2<Float> {
            SIMD2(
                base.x + amount.x * Float(sin(t * 0.21 + phase)),
                base.y + amount.y * Float(cos(t * 0.17 + phase))
            )
        }

        return [
            SIMD2(0, 0), drift(SIMD2(0.5, 0), SIMD2(0.12, 0), 0.0), SIMD2(1, 0),
            drift(SIMD2(0, 0.5), SIMD2(0, 0.10), 1.3),
            drift(SIMD2(0.5, 0.5), SIMD2(0.16, 0.14), 2.1),
            drift(SIMD2(1, 0.5), SIMD2(0, 0.10), 3.4),
            SIMD2(0, 1), drift(SIMD2(0.5, 1), SIMD2(0.12, 0), 4.2), SIMD2(1, 1),
        ]
    }
}

#Preview {
    AuroraBackground().ignoresSafeArea()
}
