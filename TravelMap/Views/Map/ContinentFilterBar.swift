import SwiftUI

/// The row of continent chips across the top of the map.
struct ContinentFilterBar: View {
    @Binding var selection: Continent?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "All", isSelected: selection == nil) { selection = nil }

                ForEach(Continent.displayOrder) { continent in
                    chip(title: continent.shortName, isSelected: selection == continent) {
                        // Tapping the active chip returns you to the whole world.
                        selection = selection == continent ? nil : continent
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollClipDisabled()
    }

    private func chip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { action() }
        } label: {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background {
                    if isSelected {
                        Capsule().fill(AppTheme.accent)
                    } else {
                        Capsule().fill(.regularMaterial)
                    }
                }
                .overlay(Capsule().strokeBorder(.black.opacity(0.06)))
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
    }
}
