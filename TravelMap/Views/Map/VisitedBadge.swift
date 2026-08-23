import SwiftUI

/// The live "how much of this have I seen" badge floating over the map.
///
/// Regular glass, not clear: what's behind it is the map, which can be pale ocean one
/// moment and dark terrain the next. Regular adapts and carries its own legibility;
/// clear would leave this unreadable half the time.
struct VisitedBadge: View {
    let title: String
    let progress: VisitProgress

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "globe.europe.africa.fill")
                .font(.footnote)
                .foregroundStyle(AppTheme.accent)
                // Fires when a new country is logged, so the map's fill-in has a
                // matching beat up here.
                .symbolEffect(.bounce, value: progress.visited)

            Text(progress.percentText)
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(AppTheme.accent)
                .contentTransition(.numericText())

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.weight(.semibold))
                Text("\(progress.visited) of \(progress.total)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassEffect(AppTheme.regularGlass, in: .capsule)
        .animation(AppTheme.Motion.snappy, value: progress)
    }
}
