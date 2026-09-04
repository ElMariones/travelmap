import SwiftUI

/// The numbers behind the map: one big percentage, then a bar per continent.
///
/// Nothing here is glass. This is the content layer — glass belongs to controls floating
/// above content, and the navigation bar above is already providing it.
struct StatsView: View {
    @Environment(VisitStore.self) private var visitStore
    @Environment(SessionStore.self) private var session
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The headline number scales with the user's text size instead of ignoring it. It's
    /// the single most important figure in the app, so it's the last thing that should
    /// stay 76pt while everything around it grows.
    @ScaledMetric(relativeTo: .largeTitle) private var headlineSize: CGFloat = 76

    private var overall: VisitProgress { visitStore.progress(for: nil) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    bigNumber
                    continentBreakdown
                    if !visitStore.regionalCountryProgress.isEmpty { regionalBreakdown }
                    if !visitStore.visits.isEmpty { recentlyLogged }
                }
                .padding(20)
            }
            .navigationTitle("Stats")
            .background(Color(.systemGroupedBackground))
            // Softens content passing under the navigation bar's glass instead of
            // letting it collide with a hard edge.
            .scrollEdgeEffectStyle(.soft, for: .top)
            .refreshable {
                guard let userID = session.userID else { return }
                await visitStore.refreshVisits(userID: userID)
            }
            .overlay { loadingOrError }
        }
    }

    /// Loading, failure and "nothing yet" are three different things and used to look
    /// like one: an endless spinner.
    @ViewBuilder
    private var loadingOrError: some View {
        if let mapDataError = visitStore.mapDataError {
            ContentUnavailableView(
                "Stats unavailable",
                systemImage: "chart.bar.xaxis",
                description: Text(mapDataError)
            )
            .background(Color(.systemGroupedBackground))
        } else if visitStore.mapData == nil {
            ProgressView("Counting the world…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGroupedBackground))
        }
    }

    /// The headline number lands with a keyframed pop whenever it changes — separate
    /// tracks for scale and lift, so it overshoots and settles like a physical object.
    private var bigNumber: some View {
        VStack(spacing: 6) {
            Text(overall.percentText)
                .font(.system(size: headlineSize, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.accent)
                .contentTransition(.numericText())
                .keyframeAnimator(
                    initialValue: CountPop(),
                    // Reduce Motion keeps the number and drops the pop: `trigger` never
                    // changes, so the keyframes never run.
                    trigger: reduceMotion ? 0 : overall.visited
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
                .minimumScaleFactor(0.5)

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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("World visited")
        .accessibilityValue("\(overall.percentText), \(overall.visited) of \(overall.total) countries")
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(continent.displayName)
        .accessibilityValue("\(progress.percentText), \(progress.visited) of \(progress.total) countries visited")
    }

    private var regionalBreakdown: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Local exploration")
                .font(.headline)
            ForEach(visitStore.regionalCountryProgress, id: \.country.code) { entry in
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text("\(entry.country.flag) \(entry.country.name)")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text("\(entry.progress.percentText) · \(entry.progress.visited)/\(entry.progress.total)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: entry.progress.fraction)
                        .tint(AppTheme.accent)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
    }

    /// The last few countries visited. Small, but it's the part of the Stats tab that
    /// changes between visits — the percentages barely move, and a screen that never
    /// looks different stops being worth opening.
    private var recentlyLogged: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Recent trips")
                .font(.headline)

            ForEach(visitStore.recentCountries(limit: 5), id: \.code) { country in
                HStack(spacing: 12) {
                    Text(country.flag)
                        .font(.title3)
                        .accessibilityHidden(true)
                    Text(country.name)
                        .font(.subheadline)
                    Spacer()
                    Text(country.continent.shortName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(minHeight: 32)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
    }
}

/// One keyframe-animated pose for the headline number.
private struct CountPop {
    var scale = 1.0
    var lift: CGFloat = 0
}
