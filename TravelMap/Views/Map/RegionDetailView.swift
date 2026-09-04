import SwiftUI

/// The V2 layer inside a country detail: progress, a tappable subdivision map, and an
/// accessible searchable route to every region.
struct RegionExplorerView: View {
    let country: Country

    @Environment(VisitStore.self) private var visitStore
    @State private var destination: RegionDestination?

    private var progress: VisitProgress { visitStore.regionProgress(in: country.code) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Explore locally")
                        .font(.headline)
                    Text("\(progress.visited) of \(progress.total) regions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if progress.visited > 0 {
                    Text(progress.percentText)
                        .font(.title3.bold().monospacedDigit())
                        .foregroundStyle(AppTheme.accent)
                        .contentTransition(.numericText())
                } else {
                    Text("Tap a region to begin")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let mapData = visitStore.regionMapData {
                RegionMapView(
                    mapData: mapData,
                    countryCode: country.code,
                    visitedRegionCodes: visitStore.visitedRegionCodes,
                    onSelectRegion: { destination = .detail($0) }
                )
                .frame(height: 250)
                .clipShape(.rect(cornerRadius: 18))
                .overlay {
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.primary.opacity(AppTheme.borderOpacity), lineWidth: AppTheme.borderWidth)
                }
                .accessibilityElement()
                .accessibilityLabel("Map of \(country.name)'s regions")
                .accessibilityValue("\(progress.visited) of \(progress.total) visited")
                .accessibilityHint("Use Browse all regions below to select one with VoiceOver")
            } else if let error = visitStore.regionDataError {
                ContentUnavailableView("Regions unavailable", systemImage: "map", description: Text(error))
                    .frame(height: 180)
            } else {
                ProgressView("Loading regions…")
                    .frame(maxWidth: .infinity, minHeight: 180)
            }

            if progress.visited > 0 {
                ProgressView(value: progress.fraction)
                    .tint(AppTheme.accent)
                    .accessibilityLabel("Regional progress")
                    .accessibilityValue(progress.percentText)
            }

            Button {
                destination = .browser
            } label: {
                Label("Browse all regions", systemImage: "list.bullet")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
        }
        .padding(16)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 18))
        .sheet(item: $destination) { destination in
            switch destination {
            case .detail(let region):
                NavigationStack {
                    RegionDetailContent(country: country, region: region)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { self.destination = nil }
                            }
                        }
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            case .browser:
                RegionBrowserSheet(country: country) { self.destination = nil }
            }
        }
    }
}

private enum RegionDestination: Identifiable {
    case detail(Region)
    case browser

    var id: String {
        switch self {
        case .detail(let region): "region-\(region.code)"
        case .browser: "browser"
        }
    }
}

struct RegionBrowserSheet: View {
    let country: Country
    let onDone: () -> Void

    @Environment(VisitStore.self) private var visitStore
    @State private var query = ""

    private var filteredRegions: [Region] {
        let regions = visitStore.regions(in: country.code)
        guard !query.isEmpty else { return regions }
        return regions.filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.code.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List(filteredRegions) { region in
                NavigationLink {
                    RegionDetailContent(country: country, region: region)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(region.name)
                            Text(region.code)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if visitStore.visitedRegionCodes.contains(region.code) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(AppTheme.accent)
                                .accessibilityLabel("Visited")
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "Search regions")
            .navigationTitle("\(country.name) regions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: onDone)
                }
            }
        }
    }
}

struct RegionDetailContent: View {
    let country: Country
    let region: Region

    @Environment(VisitStore.self) private var visitStore
    @Environment(Haptics.self) private var haptics
    @State private var formDestination: RegionFormDestination?
    @State private var pendingDeletion: RegionVisit?

    private var visits: [RegionVisit] { visitStore.regionVisits(to: region.code) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(region.name)
                        .font(.title2.bold())
                    Text("\(country.flag) \(country.name) · \(region.code)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if visits.isEmpty {
                    ContentUnavailableView(
                        "Not explored yet",
                        systemImage: "mappin.and.ellipse",
                        description: Text("Log a visit and this region will fill in on the map.")
                    )
                    Button {
                        formDestination = .add
                    } label: {
                        Label("I've been here", systemImage: "plus")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                } else {
                    ForEach(visits) { visit in regionVisitCard(visit) }
                    Button {
                        formDestination = .add
                    } label: {
                        Label("Log another visit", systemImage: "plus")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                }
            }
            .padding(20)
        }
        .navigationTitle(region.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $formDestination) { destination in
            NavigationStack {
                RegionVisitFormView(country: country, region: region, visit: destination.visit) {
                    formDestination = nil
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { formDestination = nil }
                    }
                }
            }
        }
        .confirmationDialog(
            "Remove this regional visit?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            )
        ) {
            Button("Remove visit", role: .destructive) {
                guard let visit = pendingDeletion else { return }
                pendingDeletion = nil
                haptics.fire(.removed)
                Task { await visitStore.deleteRegionVisit(visit) }
            }
            Button("Keep", role: .cancel) {}
        }
    }

    private func regionVisitCard(_ visit: RegionVisit) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(region.name).font(.headline)
                    Text(visit.visitedDateText).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Button { formDestination = .edit(visit) } label: {
                    Image(systemName: "pencil").frame(width: 44, height: 44).contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit regional visit")
                Button { pendingDeletion = visit } label: {
                    Image(systemName: "trash").frame(width: 44, height: 44).contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove regional visit")
            }
            if let note = visit.note, !note.isEmpty {
                Text(note).font(.subheadline).foregroundStyle(.secondary)
            }
            if !visit.photos.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(Array(visit.photos.enumerated()), id: \.element) { index, path in
                        StoragePhotoView(path: path)
                            .aspectRatio(1, contentMode: .fill)
                            .clipShape(.rect(cornerRadius: 10))
                            .accessibilityLabel("Photo \(index + 1) from \(region.name)")
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 14))
    }
}

private enum RegionFormDestination: Identifiable {
    case add
    case edit(RegionVisit)
    var id: String {
        switch self {
        case .add: "add"
        case .edit(let visit): visit.id.uuidString
        }
    }
    var visit: RegionVisit? {
        switch self {
        case .add: nil
        case .edit(let visit): visit
        }
    }
}

struct RegionVisitFormView: View {
    let country: Country
    let region: Region
    let visit: RegionVisit?
    let onSaved: () -> Void

    @Environment(SessionStore.self) private var session
    @Environment(VisitStore.self) private var visitStore
    @Environment(Haptics.self) private var haptics

    @State private var includesDate: Bool
    @State private var date: Date
    @State private var note: String
    @State private var existingPhotoPaths: [String]
    @State private var photos: [UIImage]
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(country: Country, region: Region, visit: RegionVisit? = nil, onSaved: @escaping () -> Void) {
        self.country = country
        self.region = region
        self.visit = visit
        self.onSaved = onSaved
        _includesDate = State(initialValue: visit?.visitedAt != nil)
        _date = State(initialValue: visit?.visitedAt ?? .now)
        _note = State(initialValue: visit?.note ?? "")
        _existingPhotoPaths = State(initialValue: visit?.photos ?? [])
        _photos = State(initialValue: [])
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Region", value: region.name)
                LabeledContent("Country", value: "\(country.flag) \(country.name)")
            }
            Section("Visit") {
                Toggle("Add a date", isOn: $includesDate.animation())
                if includesDate {
                    DatePicker("When", selection: $date, in: ...Date.now, displayedComponents: .date)
                }
                TextField("Note (optional)", text: $note, axis: .vertical)
                    .lineLimit(1...4)
            }
            Section {
                PhotoSlotsView(existingPhotoPaths: $existingPhotoPaths, photos: $photos)
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
            }
            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(visit == nil ? "Log a region" : "Edit region visit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView().accessibilityLabel("Saving regional visit")
                } else {
                    Button("Save", action: save).fontWeight(.semibold)
                }
            }
        }
        .interactiveDismissDisabled(isSaving)
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil
        Task {
            do {
                let cleanNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
                if let visit {
                    try await visitStore.updateRegionVisit(
                        visit,
                        visitedAt: includesDate ? date : nil,
                        note: cleanNote,
                        retainedPhotoPaths: existingPhotoPaths,
                        newPhotos: photos
                    )
                    haptics.fire(.visitLogged)
                } else {
                    guard let userID = session.userID else { isSaving = false; return }
                    let filledNewRegion = try await visitStore.addRegionVisit(
                        userID: userID,
                        countryCode: country.code,
                        regionCode: region.code,
                        visitedAt: includesDate ? date : nil,
                        note: cleanNote,
                        photos: photos
                    )
                    haptics.fire(filledNewRegion ? .newRegion : .visitLogged)
                }
                onSaved()
            } catch {
                errorMessage = error.localizedDescription
                haptics.fire(.failure)
                isSaving = false
            }
        }
    }
}
