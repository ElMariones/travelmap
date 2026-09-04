import SwiftUI

/// The row of continent chips across the top of the map.
///
/// Each chip is its own glass capsule. They're siblings inside the screen's
/// `GlassEffectContainer`, which is what lets neighbouring chips sample together and
/// blend at the edges — the thing to avoid is *nesting* glass, not placing it side by side.
struct ContinentFilterBar: View {
    @Binding var selection: Continent?

    @Environment(Haptics.self) private var haptics

    /// Shared namespace so the selected chip's tint travels between chips instead of
    /// cross-fading in place.
    @Namespace private var chips

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "All", continent: nil)
                ForEach(Continent.displayOrder) { continent in
                    chip(title: continent.shortName, continent: continent)
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollClipDisabled()
        // A floating status control over the map, not the place to read numbers at
        // accessibility sizes — at those, chips wider than the screen stop being a filter
        // bar at all. The Stats tab carries the same breakdown at any size.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityLabel("Filter by continent")
    }

    private func chip(title: String, continent: Continent?) -> some View {
        let isSelected = selection == continent

        return Button {
            haptics.fire(.selection)
            withAnimation(AppTheme.Motion.snappy) {
                // Tapping the active chip returns you to the whole world.
                selection = isSelected ? nil : continent
            }
        } label: {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(isSelected ? .white : .primary)
                .padding(.horizontal, 15)
                // 44pt tall including the padding, so the chip is as big as it looks.
                .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .glassEffect(
            isSelected ? AppTheme.accentGlass : AppTheme.interactiveGlass,
            in: .capsule
        )
        .glassEffectID(continent?.id ?? "all", in: chips)
        // Selection is a tint on screen. Without the trait, VoiceOver reads every chip
        // identically and the current filter is invisible.
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel(continent?.displayName ?? "All continents")
    }
}
