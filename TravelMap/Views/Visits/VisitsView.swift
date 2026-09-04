import SwiftUI

/// Every trip ordered by when it happened. Creation time is only a tie-breaker and is
/// used within the final undated section.
struct VisitsView: View {
    @Environment(VisitStore.self) private var visitStore
    @Environment(SessionStore.self) private var session

    var body: some View {
        NavigationStack {
            Group {
                if visitStore.visits.isEmpty && visitStore.regionVisits.isEmpty {
                    ContentUnavailableView(
                        "No visits yet",
                        systemImage: "suitcase",
                        description: Text("Log a country or local region from the map and your trips will appear here.")
                    )
                } else {
                    List {
                        ForEach(sections) { section in
                            Section(section.title) {
                                ForEach(section.entries) { entry in
                                    NavigationLink { destination(for: entry) } label: {
                                        TravelTimelineRow(entry: entry)
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .refreshable {
                        guard let userID = session.userID else { return }
                        await visitStore.refreshVisits(userID: userID)
                    }
                }
            }
            .navigationTitle("Visits")
            .background(Color(.systemGroupedBackground))
        }
    }

    private var sections: [VisitTimelineSection] {
        var result: [VisitTimelineSection] = []
        for entry in timelineEntries {
            let title = entry.visitedAt?.formatted(.dateTime.year()) ?? "Date not set"
            if result.last?.title == title {
                result[result.count - 1].entries.append(entry)
            } else {
                result.append(VisitTimelineSection(title: title, entries: [entry]))
            }
        }
        return result
    }

    private var timelineEntries: [TravelTimelineEntry] {
        let countryEntries = visitStore.visits.map(TravelTimelineEntry.country)
        let regionEntries = visitStore.regionVisits.map(TravelTimelineEntry.region)
        return (countryEntries + regionEntries).sorted {
            switch ($0.visitedAt, $1.visitedAt) {
            case let (left?, right?) where left != right: left > right
            case (_?, nil): true
            case (nil, _?): false
            default: $0.createdAt > $1.createdAt
            }
        }
    }

    @ViewBuilder
    private func destination(for entry: TravelTimelineEntry) -> some View {
        switch entry {
        case .country(let visit):
            VisitDetailView(visitID: visit.id)
        case .region(let visit):
            if let country = visitStore.country(for: visit.countryCode),
               let region = visitStore.region(for: visit.regionCode) {
                RegionDetailContent(country: country, region: region)
            } else {
                ContentUnavailableView("Region unavailable", systemImage: "map")
            }
        }
    }
}

private struct VisitTimelineSection: Identifiable {
    let title: String
    var entries: [TravelTimelineEntry]

    var id: String { title }
}

private enum TravelTimelineEntry: Identifiable {
    case country(Visit)
    case region(RegionVisit)

    var id: UUID {
        switch self {
        case .country(let visit): visit.id
        case .region(let visit): visit.id
        }
    }
    var visitedAt: Date? {
        switch self {
        case .country(let visit): visit.visitedAt
        case .region(let visit): visit.visitedAt
        }
    }
    var createdAt: Date {
        switch self {
        case .country(let visit): visit.createdAt
        case .region(let visit): visit.createdAt
        }
    }
}

private struct TravelTimelineRow: View {
    let entry: TravelTimelineEntry

    @Environment(VisitStore.self) private var visitStore

    private var country: Country? { visitStore.country(for: countryCode) }
    private var countryCode: String {
        switch entry {
        case .country(let visit): visit.countryCode
        case .region(let visit): visit.countryCode
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            if let country {
                Text(country.flag)
                    .font(.title2)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: "globe")
                    .font(.title2)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(primaryTitle)
                    .font(.headline)
                Text(secondaryTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(dateText)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if photoCount > 0 {
                Label("\(photoCount)", systemImage: "photo")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var primaryTitle: String {
        switch entry {
        case .country(let visit): visit.displayTitle(countryName: country?.name ?? visit.countryCode)
        case .region(let visit): visitStore.region(for: visit.regionCode)?.name ?? visit.regionCode
        }
    }
    private var secondaryTitle: String {
        switch entry {
        case .country: country?.name ?? countryCode
        case .region: "Local region · \(country?.name ?? countryCode)"
        }
    }
    private var dateText: String {
        switch entry {
        case .country(let visit): visit.visitedDateText
        case .region(let visit): visit.visitedDateText
        }
    }
    private var photoCount: Int {
        switch entry {
        case .country(let visit): visit.photos.count
        case .region(let visit): visit.photos.count
        }
    }
}

private struct VisitDetailView: View {
    let visitID: UUID

    @Environment(VisitStore.self) private var visitStore
    @Environment(Haptics.self) private var haptics
    @Environment(\.dismiss) private var dismiss

    @State private var visitBeingEdited: Visit?
    @State private var showsDeleteConfirmation = false

    private var visit: Visit? { visitStore.visits.first { $0.id == visitID } }
    private var country: Country? { visit.flatMap { visitStore.country(for: $0.countryCode) } }

    var body: some View {
        Group {
            if let visit {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 6) {
                            if let country {
                                Text(country.flag)
                                    .font(.system(size: 46))
                                    .accessibilityHidden(true)
                            }
                            Text(visit.displayTitle(countryName: country?.name ?? visit.countryCode))
                                .font(.title2.weight(.bold))
                            Text(country?.name ?? visit.countryCode)
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            Label(visit.visitedDateText, systemImage: "calendar")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)

                        if let note = visit.note, !note.isEmpty {
                            Text(note)
                                .font(.body)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                                .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 14))
                        }

                        if !visit.photos.isEmpty {
                            LazyVGrid(
                                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2),
                                spacing: 8
                            ) {
                                ForEach(Array(visit.photos.enumerated()), id: \.element) { index, path in
                                    StoragePhotoView(path: path)
                                        .aspectRatio(1, contentMode: .fill)
                                        .clipShape(.rect(cornerRadius: 12))
                                        .accessibilityLabel("Photo \(index + 1)")
                                }
                            }
                        }
                    }
                    .padding(20)
                }
                .navigationTitle("Visit")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button { visitBeingEdited = visit } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            showsDeleteConfirmation = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                .sheet(item: $visitBeingEdited) { editableVisit in
                    if let country {
                        NavigationStack {
                            VisitFormView(country: country, visit: editableVisit) {
                                visitBeingEdited = nil
                            }
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("Cancel") { visitBeingEdited = nil }
                                }
                            }
                        }
                    } else {
                        ContentUnavailableView("Country unavailable", systemImage: "globe")
                    }
                }
                .confirmationDialog("Delete this visit?", isPresented: $showsDeleteConfirmation) {
                    Button("Delete visit", role: .destructive) {
                        haptics.fire(.removed)
                        Task {
                            await visitStore.deleteVisit(visit)
                            if visitStore.visits.contains(where: { $0.id == visitID }) == false {
                                dismiss()
                            }
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                }
            } else {
                ContentUnavailableView("Visit not found", systemImage: "suitcase")
            }
        }
    }
}
