import SwiftUI

/// What you get when you tap a country on the map: whether you've been, when, and the
/// photos you attached. The region map that will eventually live here is V2.
struct CountryDetailSheet: View {
    let country: Country

    @Environment(VisitStore.self) private var visitStore
    @Environment(\.dismiss) private var dismiss

    @State private var isAddingVisit = false
    @State private var visitPendingDeletion: Visit?

    private var visits: [Visit] { visitStore.visits(to: country.code) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    if visits.isEmpty {
                        emptyState
                    } else {
                        ForEach(visits) { visit in
                            visitCard(visit)
                        }
                    }
                }
                .padding(20)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $isAddingVisit) {
                AddVisitView(preselectedCountry: country)
            }
            .confirmationDialog(
                "Remove this visit?",
                isPresented: .init(
                    get: { visitPendingDeletion != nil },
                    set: { if !$0 { visitPendingDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Remove visit", role: .destructive) {
                    guard let visit = visitPendingDeletion else { return }
                    visitPendingDeletion = nil
                    Task { await visitStore.deleteVisit(visit) }
                }
                Button("Keep", role: .cancel) { visitPendingDeletion = nil }
            } message: {
                Text("\(country.name) goes back to gray if this is your only visit.")
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Text(country.flag).font(.system(size: 48))

            VStack(alignment: .leading, spacing: 3) {
                Text(country.name).font(.title2.weight(.semibold))
                Text(country.continent.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !visits.isEmpty {
                Label("Visited", systemImage: "checkmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .font(.title2)
                    .foregroundStyle(AppTheme.accent)
                    .accessibilityLabel("Visited")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Text("You haven't logged \(country.name) yet.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                isAddingVisit = true
            } label: {
                Label("I've been here", systemImage: "plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }

    private func visitCard(_ visit: Visit) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(dateText(for: visit))
                    .font(.subheadline.weight(.medium))
                Spacer()
                Button {
                    visitPendingDeletion = visit
                } label: {
                    Image(systemName: "trash")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Remove this visit")
            }

            if let note = visit.note, !note.isEmpty {
                Text(note).font(.subheadline).foregroundStyle(.secondary)
            }

            if !visit.photos.isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                    ForEach(visit.photos, id: \.self) { path in
                        StoragePhotoView(path: path)
                            .aspectRatio(1, contentMode: .fill)
                            .clipShape(.rect(cornerRadius: 10))
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 14))
    }

    private func dateText(for visit: Visit) -> String {
        if let visitedAt = visit.visitedAt {
            return visitedAt.formatted(.dateTime.day().month(.wide).year())
        }
        return "Logged \(visit.createdAt.formatted(.dateTime.day().month(.abbreviated).year()))"
    }
}
