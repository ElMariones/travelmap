import SwiftUI

/// Searchable list of every country in the reference set.
struct CountryPickerList: View {
    @Environment(VisitStore.self) private var visitStore
    @Environment(Haptics.self) private var haptics

    let onSelect: (Country) -> Void
    /// Namespace owned by the flow above, so the pushed form can zoom out of its row.
    var zoomNamespace: Namespace.ID?

    @State private var query = ""

    private var results: [Country] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return visitStore.countries }
        return visitStore.countries.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed) || $0.code.caseInsensitiveCompare(trimmed) == .orderedSame
        }
    }

    var body: some View {
        List(results) { country in
            Button {
                haptics.fire(.selection)
                onSelect(country)
            } label: {
                HStack(spacing: 12) {
                    Text(country.flag)
                        .font(.title2)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(country.name).foregroundStyle(.primary)
                        Text(country.continent.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if visitStore.hasVisited(country.code) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(AppTheme.accent)
                            .transition(.symbolEffect(.drawOn))
                    }
                }
                .frame(minHeight: 44)
            }
            .matchedTransitionSourceIfAvailable(id: country.code, in: zoomNamespace)
            // The tick is the only thing marking a country as visited, and a glyph on its
            // own says nothing out loud.
            .accessibilityValue(visitStore.hasVisited(country.code) ? "Visited" : "Not visited")
        }
        .animation(AppTheme.Motion.snappy, value: visitStore.visitedCountryCodes)
        .listStyle(.plain)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search countries")
        .autocorrectionDisabled()
        .overlay {
            if results.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
    }
}


private extension View {
    /// `matchedTransitionSource` needs a namespace; the picker is also usable without one.
    @ViewBuilder
    func matchedTransitionSourceIfAvailable(id: some Hashable, in namespace: Namespace.ID?) -> some View {
        if let namespace {
            matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }
}
