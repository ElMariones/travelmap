import SwiftUI

/// The numbers behind the map: one big percentage, then a bar per continent.
struct StatsView: View {
    @Environment(VisitStore.self) private var visitStore

    private var overall: VisitProgress { visitStore.progress(for: nil) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    bigNumber
                    continentBreakdown
                }
                .padding(20)
            }
            .navigationTitle("Stats")
            .background(Color(.systemGroupedBackground))
            .overlay {
                if visitStore.mapData == nil {
                    ProgressView()
                }
            }
        }
    }

    private var bigNumber: some View {
        VStack(spacing: 6) {
            Text(overall.percentText)
                .font(.system(size: 76, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.accent)
                .contentTransition(.numericText())

            Text("of the world visited")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("\(overall.visited) of \(overall.total) countries")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
        .animation(.easeInOut(duration: 0.3), value: overall)
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
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
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
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.tertiarySystemFill))
                    Capsule()
                        .fill(AppTheme.accent)
                        .frame(width: max(progress.fraction > 0 ? 6 : 0, proxy.size.width * progress.fraction))
                }
            }
            .frame(height: 10)
            .animation(.easeInOut(duration: 0.4), value: progress)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(continent.displayName): \(progress.visited) of \(progress.total) countries visited")
    }
}
