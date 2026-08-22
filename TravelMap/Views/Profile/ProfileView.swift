import SwiftUI

/// Your account: display name, the friend code others will use to add you in V3,
/// and the way out.
struct ProfileView: View {
    @Environment(SessionStore.self) private var session
    @Environment(VisitStore.self) private var visitStore

    @State private var isConfirmingSignOut = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    identityRow
                }

                Section {
                    if let friendCode = session.profile?.friendCode {
                        HStack {
                            Text(friendCode)
                                .font(.title3.weight(.semibold).monospaced())
                                .textSelection(.enabled)
                            Spacer()
                            ShareLink(item: friendCode) {
                                Image(systemName: "square.and.arrow.up")
                            }
                        }
                    } else {
                        Text("Not available yet")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Friend code")
                } footer: {
                    Text("Friends will add you with this code once the social layer ships.")
                }

                Section("Your travels") {
                    LabeledContent("Countries visited", value: "\(visitStore.visitedCountryCodes.count)")
                    LabeledContent("Visits logged", value: "\(visitStore.visits.count)")
                }

                Section {
                    Button("Sign out", role: .destructive) { isConfirmingSignOut = true }
                }

                Section {
                    Text("V1: countries, photos, and stats. Regions and friends are in the database schema but not built yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Profile")
            .confirmationDialog("Sign out of TravelMap?", isPresented: $isConfirmingSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) {
                    Task { await session.signOut() }
                }
                Button("Cancel", role: .cancel) {}
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
            }
        }
        .padding(.vertical, 4)
    }
}
