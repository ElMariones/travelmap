import SwiftUI

/// The numbers behind the map: one big percentage, then a bar per continent.
///
/// Nothing here is glass. This is the content layer — glass belongs to controls floating
/// above content, and the navigation bar above is already providing it.
struct StatsView: View {
    @Environment(VisitStore.self) private var visitStore

    private var overall: VisitProgress { visitStore.progress(for: nil) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    bigNumber
                    continentBreakdown
                }
                .padding(20)
            }
            .navigationTitle("Stats")
            .background(Color(.systemGroupedBackground))
            // Softens content passing under the navigation bar's glass instead of
            // letting it collide with a hard edge.
            .scrollEdgeEffectStyle(.soft, for: .top)
            .overlay {
                if visitStore.mapData == nil {
                    ProgressView()
                }
            }
        }
    }

    /// The headline number lands with a keyframed pop whenever it changes — separate
    /// tracks for scale and lift, so it overshoots and settles like a physical object.
    private var bigNumber: some View {
        VStack(spacing: 6) {
            Text(overall.percentText)
                .font(.system(size: 76, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.accent)
                .contentTransition(.numericText())
                .keyframeAnimator(
                    initialValue: CountPop(),
                    trigger: overall.visited
                ) { view, pop in
                    view
                        .scaleEffect(pop.scale)
                        .offset(y: pop.lift)
                } keyframes: { _ in
                    KeyframeTrack(\.scale) {
                        SpringKeyframe(1.18, duration: 0.26, spring: .bouncy)
                        SpringKeyframe(1.0, duration: 0.42, spring: .snappy)
                    }
                    KeyframeTrack(\.lift) {
                        CubicKeyframe(-10, duration: 0.24)
                        CubicKeyframe(0, duration: 0.44)
                    }
                }

            Text("of the world visited")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("\(overall.visited) of \(overall.total) countries")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.tertiary)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
        .animation(AppTheme.Motion.snappy, value: overall)
    }

    private var continentBreakdown: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("By continent")
                .font(.headline)

            ForEach(visitStore.continentProgress, id: \.continent) { entry in
                continentBar(entry.continent, entry.progress)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
    }

    private func continentBar(_ continent: Continent, _ progress: VisitProgress) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(continent.displayName)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(progress.percentText) · \(progress.visited)/\(progress.total)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.tertiarySystemFill))
                    Capsule()
                        .fill(AppTheme.accent)
                        // A single visit should still be visible, so the fill has a floor.
                        .frame(width: max(progress.fraction > 0 ? 8 : 0, proxy.size.width * progress.fraction))
                }
            }
            .frame(height: 10)
            .animation(AppTheme.Motion.bouncy, value: progress)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(continent.displayName): \(progress.visited) of \(progress.total) countries visited")
    }
}

/// One keyframe-animated pose for the headline number.
private struct CountPop {
    var scale = 1.0
    var lift: CGFloat = 0
}
