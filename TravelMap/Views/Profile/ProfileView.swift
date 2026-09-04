import SwiftUI

/// Your account: display name, the friend code others will use to add you in V3, the way
/// out, and the way to take your data with you.
struct ProfileView: View {
    @Environment(SessionStore.self) private var session
    @Environment(VisitStore.self) private var visitStore
    @Environment(Haptics.self) private var haptics

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
                    LabeledContent("Regions explored", value: "\(visitStore.visitedRegionCodes.count)")
                        .contentTransition(.numericText())
                    LabeledContent("Visits logged", value: "\(visitStore.visits.count + visitStore.regionVisits.count)")
                        .contentTransition(.numericText())
                }

                Section {
                    Toggle("Haptics", isOn: Binding(
                        get: { haptics.isEnabled },
                        set: { haptics.isEnabled = $0 }
                    ))
                } header: {
                    Text("Feedback")
                } footer: {
                    Text("Taps and celebrations you can feel. iOS has no system setting for these, so this is the switch.")
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
                    LabeledContent("Version", value: Bundle.main.shortVersionString)
                        .foregroundStyle(.secondary)

                    #if DEBUG
                    NavigationLink("Widget preview") { WidgetPreviewScreen() }
                    #endif
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
                .accessibilityHidden(true)

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
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var friendCodeRow: some View {
        if let friendCode = session.profile?.friendCode {
            HStack(spacing: 4) {
                Text(friendCode)
                    .font(.title3.weight(.semibold).monospaced())
                    .textSelection(.enabled)

                Spacer()

                Button {
                    UIPasteboard.general.string = friendCode
                    haptics.fire(.selection)
                    withAnimation(AppTheme.Motion.snappy) { didCopyCode = true }
                    // Reverts, so the row doesn't read "copied" for the rest of the
                    // session and stop meaning anything.
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        withAnimation(AppTheme.Motion.snappy) { didCopyCode = false }
                    }
                } label: {
                    Image(systemName: didCopyCode ? "checkmark" : "doc.on.doc")
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.accent)
                .accessibilityLabel(didCopyCode ? "Friend code copied" : "Copy friend code")

                ShareLink(item: friendCode) {
                    Image(systemName: "square.and.arrow.up")
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .accessibilityLabel("Share friend code")
            }
            .accessibilityElement(children: .contain)
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
                haptics.fire(.failure)
            }
            isDeleting = false
        }
    }
}

extension Bundle {
    /// The marketing version, with the build number appended in Debug so a TestFlight
    /// screenshot says which build it came from.
    var shortVersionString: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        #if DEBUG
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(version) (\(build))"
        #else
        return version
        #endif
    }
}
