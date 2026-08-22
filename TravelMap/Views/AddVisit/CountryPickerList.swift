import SwiftUI

/// Searchable list of every country in the reference set.
struct CountryPickerList: View {
    @Environment(VisitStore.self) private var visitStore

    let onSelect: (Country) -> Void

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
                onSelect(country)
            } label: {
                HStack(spacing: 12) {
                    Text(country.flag).font(.title2)

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
                    }
                }
            }
        }
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
