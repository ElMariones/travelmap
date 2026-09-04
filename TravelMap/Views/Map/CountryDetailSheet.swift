import SwiftUI

/// What you get when you tap a country on the map: whether you've been, when, and the
/// photos you attached, plus the country's V2 local-region map where the bundled data
/// contains more than one subdivision.
///
/// Presented as its own sheet from the map, and pushed inside the country browser — hence
/// the split: ``CountryDetailContent`` is the screen, this is only the sheet chrome
/// around it.
struct CountryDetailSheet: View {
    let country: Country

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            CountryDetailContent(country: country)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

struct CountryDetailContent: View {
    let country: Country

    @Environment(VisitStore.self) private var visitStore
    @Environment(Haptics.self) private var haptics

    @State private var presentedVisitForm: VisitFormDestination?
    @State private var visitPendingDeletion: Visit?

    private var visits: [Visit] { visitStore.visits(to: country.code) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if visitStore.supportsRegionMode(countryCode: country.code) {
                    RegionExplorerView(country: country)
                }

                if visits.isEmpty {
                    emptyState
                } else {
                    ForEach(visits) { visit in
                        visitCard(visit)
                    }

                    Button {
                        presentedVisitForm = .add
                    } label: {
                        Label("Log another visit", systemImage: "plus")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                }
            }
            .padding(20)
        }
        .navigationTitle(country.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $presentedVisitForm) { destination in
            NavigationStack {
                VisitFormView(country: country, visit: destination.visit) {
                    presentedVisitForm = nil
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { presentedVisitForm = nil }
                    }
                }
            }
        }
        .confirmationDialog(
            "Remove this visit?",
            isPresented: Binding(
                get: { visitPendingDeletion != nil },
                set: { if !$0 { visitPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove visit", role: .destructive) {
                guard let visit = visitPendingDeletion else { return }
                visitPendingDeletion = nil
                haptics.fire(.removed)
                Task { await visitStore.deleteVisit(visit) }
            }
            Button("Keep", role: .cancel) { visitPendingDeletion = nil }
        } message: {
            Text("\(country.name) goes back to gray only if no country or regional visits remain.")
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Text(country.flag)
                .font(.system(size: 48))
                // Decoration: the country's name is right beside it, and VoiceOver reads
                // a flag emoji as its own country name, so this would say it twice.
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(country.name).font(.title2.weight(.semibold))
                Text(country.continent.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !visits.isEmpty {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(AppTheme.accent)
            }
        }
        .accessibilityElement(children: .combine)
        // Visited-ness is a colour and a glyph on screen; VoiceOver needs it said.
        .accessibilityValue(visits.isEmpty ? "Not visited" : "Visited")
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Text("No country-wide trip logged for \(country.name) yet.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                presentedVisitForm = .add
            } label: {
                Label("I've been here", systemImage: "plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }

    private func visitCard(_ visit: Visit) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(visit.displayTitle(countryName: country.name))
                        .font(.headline)
                    Text(visit.visitedDateText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    presentedVisitForm = .edit(visit)
                } label: {
                    Image(systemName: "pencil")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit this visit")

                Button {
                    visitPendingDeletion = visit
                } label: {
                    Image(systemName: "trash")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        // A glyph's own bounds are about 15pt across. The frame is what
                        // makes this the 44pt target the HIG asks for; without it the
                        // button is technically present and practically unhittable.
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove this visit")
            }

            if let note = visit.note, !note.isEmpty {
                Text(note).font(.subheadline).foregroundStyle(.secondary)
            }

            if !visit.photos.isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                    ForEach(Array(visit.photos.enumerated()), id: \.element) { index, path in
                        StoragePhotoView(path: path)
                            .aspectRatio(1, contentMode: .fill)
                            .clipShape(.rect(cornerRadius: 10))
                            .accessibilityLabel("Photo \(index + 1) from your visit to \(country.name)")
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 14))
    }
}

private enum VisitFormDestination: Identifiable {
    case add
    case edit(Visit)

    var id: String {
        switch self {
        case .add: "add"
        case let .edit(visit): visit.id.uuidString
        }
    }

    var visit: Visit? {
        switch self {
        case .add: nil
        case let .edit(visit): visit
        }
    }
}
