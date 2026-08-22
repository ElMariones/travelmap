import SwiftUI

/// The live "how much of this have I seen" badge that floats over the map.
struct VisitedBadge: View {
    let title: String
    let progress: VisitProgress

    var body: some View {
        HStack(spacing: 10) {
            Text(progress.percentText)
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(AppTheme.accent)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.weight(.semibold))
                Text("\(progress.visited) of \(progress.total)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: .capsule)
        .overlay(Capsule().strokeBorder(.black.opacity(0.06)))
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        .contentTransition(.numericText())
        .animation(.easeInOut(duration: 0.3), value: progress)
    }
}
