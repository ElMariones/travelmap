import SwiftUI

/// The add-visit flow. Opens straight onto the country list unless a country is already
/// known — the whole design goal is that logging a place takes seconds.
struct AddVisitView: View {
    let preselectedCountry: Country?

    @Environment(\.dismiss) private var dismiss
    @State private var pickedCountry: Country?

    var body: some View {
        NavigationStack {
            Group {
                if let preselectedCountry {
                    VisitFormView(country: preselectedCountry, onSaved: dismissSheet)
                } else {
                    CountryPickerList { pickedCountry = $0 }
                        .navigationTitle("Where have you been?")
                        .navigationBarTitleDisplayMode(.inline)
                        .navigationDestination(item: $pickedCountry) { country in
                            VisitFormView(country: country, onSaved: dismissSheet)
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

/// Date, note, and photos for one country, then save.
struct VisitFormView: View {
    let country: Country
    /// Called once the visit is saved, to close the flow the form is presented inside.
    let onSaved: () -> Void

    @Environment(SessionStore.self) private var session
    @Environment(VisitStore.self) private var visitStore

    @State private var includeDate = false
    @State private var visitedAt = Date()
    @State private var note = ""
    @State private var photos: [UIImage] = []
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Text(country.flag).font(.system(size: 40))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(country.name).font(.headline)
                        Text(country.continent.displayName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                Toggle("Add a date", isOn: $includeDate.animation())
                if includeDate {
                    DatePicker("Visited", selection: $visitedAt, in: ...Date(), displayedComponents: .date)
                }
                TextField("Note (optional)", text: $note, axis: .vertical)
                    .lineLimit(1...4)
            }

            Section {
                PhotoSlotsView(photos: $photos)
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
        .navigationTitle("Log a visit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView()
                } else {
                    Button("Save", action: save).fontWeight(.semibold)
                }
            }
        }
        .interactiveDismissDisabled(isSaving)
    }

    private func save() {
        guard let userID = session.userID, !isSaving else { return }
        isSaving = true
        errorMessage = nil

        Task {
            do {
                try await visitStore.addVisit(
                    userID: userID,
                    countryCode: country.code,
                    visitedAt: includeDate ? visitedAt : nil,
                    note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                    photos: photos
                )
                // No confirmation screen — the map is already filled in behind this sheet.
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                onSaved()
            } catch {
                errorMessage = error.localizedDescription
                isSaving = false
            }
        }
    }
}
