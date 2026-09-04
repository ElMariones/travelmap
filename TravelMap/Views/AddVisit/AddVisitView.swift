import SwiftUI

/// The add-visit flow. Opens straight onto the country list unless a country is already
/// known — the whole design goal is that logging a place takes seconds.
struct AddVisitView: View {
    let preselectedCountry: Country?

    @Environment(\.dismiss) private var dismiss
    @State private var pickedCountry: Country?

    /// Source namespace for the zoom out of a country row into its form.
    @Namespace private var zoom

    var body: some View {
        NavigationStack {
            Group {
                if let preselectedCountry {
                    VisitFormView(country: preselectedCountry, onSaved: dismissSheet)
                } else {
                    CountryPickerList(onSelect: { pickedCountry = $0 }, zoomNamespace: zoom)
                        .navigationTitle("Where have you been?")
                        .navigationBarTitleDisplayMode(.inline)
                        .navigationDestination(item: $pickedCountry) { country in
                            VisitFormView(country: country, onSaved: dismissSheet)
                                .navigationTransition(.zoom(sourceID: country.code, in: zoom))
                        }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    /// Saving closes the whole flow, not just the form. `VisitFormView`'s own `dismiss`
    /// would only pop it back to the country list, which reads as if nothing was saved.
    private func dismissSheet() {
        dismiss()
    }
}

/// Title, partial date, note, and photos for one country. The same form edits an existing
/// visit so create and update cannot drift into different rules.
struct VisitFormView: View {
    let country: Country
    let visit: Visit?
    /// Called once the visit is saved, to close the flow the form is presented inside.
    let onSaved: () -> Void

    @Environment(SessionStore.self) private var session
    @Environment(VisitStore.self) private var visitStore
    @Environment(CelebrationCenter.self) private var celebrations
    @Environment(Haptics.self) private var haptics

    @State private var title: String
    @State private var dateChoice: VisitDateChoice
    @State private var selectedYear: Int
    @State private var selectedMonth: Int
    @State private var note: String
    @State private var existingPhotoPaths: [String]
    @State private var photos: [UIImage]
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var currentYear: Int { Calendar.current.component(.year, from: .now) }
    private var currentMonth: Int { Calendar.current.component(.month, from: .now) }
    private var availableYears: [Int] { Array(stride(from: currentYear, through: 1900, by: -1)) }
    private var availableMonths: [Int] {
        Array(1...(selectedYear == currentYear ? currentMonth : 12))
    }
    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    init(country: Country, visit: Visit? = nil, onSaved: @escaping () -> Void) {
        self.country = country
        self.visit = visit
        self.onSaved = onSaved

        let components = visit?.visitedAt.map { Calendar.current.dateComponents([.year, .month], from: $0) }
        let now = Calendar.current.dateComponents([.year, .month], from: .now)
        _title = State(initialValue: visit?.title ?? "")
        _dateChoice = State(initialValue: VisitDateChoice(visit: visit))
        _selectedYear = State(initialValue: components?.year ?? now.year ?? 2000)
        _selectedMonth = State(initialValue: components?.month ?? now.month ?? 1)
        _note = State(initialValue: visit?.note ?? "")
        _existingPhotoPaths = State(initialValue: visit?.photos ?? [])
        _photos = State(initialValue: [])
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Text(country.flag)
                        .font(.system(size: 40))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(country.name).font(.headline)
                        Text(country.continent.displayName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
            }

            Section("Visit") {
                TextField("Title", text: $title)
                    .onChange(of: title) { _, value in
                        if value.count > 100 { title = String(value.prefix(100)) }
                    }

                Picker("When", selection: $dateChoice.animation()) {
                    ForEach(VisitDateChoice.allCases) { choice in
                        Text(choice.label).tag(choice)
                    }
                }
                .pickerStyle(.segmented)

                if dateChoice != .none {
                    Picker("Year", selection: $selectedYear) {
                        ForEach(availableYears, id: \.self) { year in
                            Text(String(year)).tag(year)
                        }
                    }
                    .onChange(of: selectedYear) { _, _ in
                        if selectedMonth > availableMonths.count {
                            selectedMonth = availableMonths.count
                        }
                    }

                    if dateChoice == .month {
                        Picker("Month", selection: $selectedMonth) {
                            ForEach(availableMonths, id: \.self) { month in
                                Text(monthName(month)).tag(month)
                            }
                        }
                    }
                }
            }

            Section {
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
        .navigationTitle(visit == nil ? "Log a visit" : "Edit visit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView()
                        .accessibilityLabel("Saving your visit")
                } else {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(trimmedTitle.isEmpty)
                }
            }
        }
        .interactiveDismissDisabled(isSaving)
    }

    private func save() {
        guard !trimmedTitle.isEmpty, !isSaving else { return }
        isSaving = true
        errorMessage = nil

        Task {
            do {
                let date = selectedDate
                let precision = dateChoice.precision
                let cleanNote = note.trimmingCharacters(in: .whitespacesAndNewlines)

                if let visit {
                    try await visitStore.updateVisit(
                        visit,
                        title: trimmedTitle,
                        visitedAt: date,
                        datePrecision: precision,
                        note: cleanNote,
                        retainedPhotoPaths: existingPhotoPaths,
                        newPhotos: photos
                    )
                } else {
                    guard let userID = session.userID else {
                        isSaving = false
                        return
                    }
                    let outcome = try await visitStore.addVisit(
                        userID: userID,
                        countryCode: country.code,
                        title: trimmedTitle,
                        visitedAt: date,
                        datePrecision: precision,
                        note: cleanNote,
                        photos: photos
                    )
                    // No confirmation screen — the map is already filled in behind this sheet.
                    celebrations.record(outcome)
                }
                onSaved()
            } catch {
                errorMessage = error.localizedDescription
                haptics.fire(.failure)
                isSaving = false
            }
        }
    }

    private var selectedDate: Date? {
        guard dateChoice != .none else { return nil }
        return PostgresDate.partialDate(
            year: selectedYear,
            month: dateChoice == .year ? nil : selectedMonth
        )
    }

    private func monthName(_ month: Int) -> String {
        Calendar.current.monthSymbols[month - 1]
    }
}

private enum VisitDateChoice: String, CaseIterable, Identifiable {
    case none
    case year
    case month

    var id: Self { self }

    var label: String {
        switch self {
        case .none: "No date"
        case .year: "Year"
        case .month: "Month"
        }
    }

    var precision: VisitDatePrecision? {
        switch self {
        case .none: nil
        case .year: .year
        case .month: .month
        }
    }

    init(visit: Visit?) {
        guard let visit, visit.visitedAt != nil else {
            self = .none
            return
        }
        self = visit.datePrecision == .year ? .year : .month
    }
}
