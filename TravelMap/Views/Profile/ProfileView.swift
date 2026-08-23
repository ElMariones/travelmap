import SwiftUI

/// Your account: display name, the friend code others will use to add you in V3, the way
/// out, and the way to take your data with you.
struct ProfileView: View {
    @Environment(SessionStore.self) private var session
    @Environment(VisitStore.self) private var visitStore

    @State private var isConfirmingSignOut = false
    @State private var isConfirmingDelete = false
    @State private var isDeleting = false
    @State private var deleteError: String?
    @State private var didCopyCode = false

    var body: some View {
        NavigationStack {
            List {
                Section { identityRow }

                Section {
                    friendCodeRow
                } header: {
                    Text("Friend code")
                } footer: {
                    Text("Friends will add you with this code once the social layer ships.")
                }

                Section("Your travels") {
                    LabeledContent("Countries visited", value: "\(visitStore.visitedCountryCodes.count)")
                        .contentTransition(.numericText())
                    LabeledContent("Visits logged", value: "\(visitStore.visits.count)")
                        .contentTransition(.numericText())
                }

                Section {
                    Button("Sign out", role: .destructive) { isConfirmingSignOut = true }
                }

                Section {
                    Button(role: .destructive) {
                        isConfirmingDelete = true
                    } label: {
                        HStack {
                            Text("Delete account")
                            Spacer()
                            if isDeleting { ProgressView() }
                        }
                    }
                    .disabled(isDeleting)
                } footer: {
                    // Deleting has to be reachable from inside the app, not only by
                    // writing to support — App Review Guideline 5.1.1(v).
                    Text("Permanently removes your account, every visit, and every photo. This can't be undone.")
                }

                if let deleteError {
                    Section {
                        Label(deleteError, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Text("V1: countries, photos, and stats. Regions and friends are in the database schema but not built yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Profile")
            .scrollEdgeEffectStyle(.soft, for: .top)
            .animation(AppTheme.Motion.snappy, value: deleteError)
            .confirmationDialog("Sign out of TravelMap?", isPresented: $isConfirmingSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) {
                    Task { await session.signOut() }
                }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog(
                "Delete your account?",
                isPresented: $isConfirmingDelete,
                titleVisibility: .visible
            ) {
                Button("Delete everything", role: .destructive, action: deleteAccount)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your \(visitStore.visits.count) visit\(visitStore.visits.count == 1 ? "" : "s") and all their photos are deleted immediately and can't be recovered.")
            }
        }
    }

    private var identityRow: some View {
        HStack(spacing: 14) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(AppTheme.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.profile?.displayName ?? "Traveller")
                    .font(.headline)
                Text(visitStore.progress(for: nil).percentText + " of the world")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var friendCodeRow: some View {
        if let friendCode = session.profile?.friendCode {
            HStack {
                Text(friendCode)
                    .font(.title3.weight(.semibold).monospaced())
                    .textSelection(.enabled)

                Spacer()

                Button {
                    UIPasteboard.general.string = friendCode
                    withAnimation(AppTheme.Motion.snappy) { didCopyCode = true }
                } label: {
                    Image(systemName: didCopyCode ? "checkmark" : "doc.on.doc")
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.accent)
                .accessibilityLabel("Copy friend code")

                ShareLink(item: friendCode) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        } else {
            Text("Not available yet")
                .foregroundStyle(.secondary)
        }
    }

    private func deleteAccount() {
        isDeleting = true
        deleteError = nil
        Task {
            do {
                try await session.deleteAccount()
                visitStore.clearUserData()
            } catch {
                deleteError = error.localizedDescription
            }
            isDeleting = false
        }
    }
}
