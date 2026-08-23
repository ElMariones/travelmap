import SwiftUI

/// Email and password, for anyone who'd rather not use Apple.
///
/// Nothing in here carries `.glassEffect`: a sheet is already a system glass surface, and
/// glass on glass samples a sample — the material goes cloudy and loses its edges.
struct EmailAuthSheet: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case signIn, signUp

        var id: String { rawValue }
        var title: String { self == .signIn ? "Sign in" : "Create account" }
    }

    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var mode: Mode = .signIn
    @State private var displayName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    @FocusState private var focusedField: Field?
    private enum Field { case name, email, password }

    private var canSubmit: Bool {
        guard email.contains("@"), password.count >= 6 else { return false }
        return mode == .signIn || !displayName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Picker("Mode", selection: $mode.animation(AppTheme.Motion.snappy)) {
                        ForEach(Mode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    VStack(spacing: 12) {
                        if mode == .signUp {
                            field(.name) {
                                TextField("Display name", text: $displayName)
                                    .textContentType(.name)
                            }
                            .transition(.blurReplace)
                        }

                        field(.email) {
                            TextField("Email", text: $email)
                                .textContentType(.emailAddress)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }

                        field(.password) {
                            SecureField("Password", text: $password)
                                .textContentType(mode == .signIn ? .password : .newPassword)
                                .onSubmit(submit)
                        }
                    }

                    if let confirmationEmail = session.pendingEmailConfirmation {
                        notice(
                            icon: "envelope.badge",
                            text: "Confirm your address from the email we sent to \(confirmationEmail), then sign in."
                        )
                    }

                    if let errorMessage {
                        notice(icon: "exclamationmark.triangle.fill", text: errorMessage, isError: true)
                    }

                    Button(action: submit) {
                        Group {
                            if isWorking {
                                ProgressView().tint(.white)
                            } else {
                                Text(mode.title).font(.headline)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .disabled(!canSubmit || isWorking)
                }
                .padding(24)
                .animation(AppTheme.Motion.snappy, value: mode)
                .animation(AppTheme.Motion.snappy, value: errorMessage)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Continue with email")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    /// A field in its pill.
    ///
    /// The tap target is the whole pill, not just the text. A bare `TextField` only takes
    /// focus where its own glyphs are, so the padding around it looks tappable and isn't.
    ///
    /// The gesture that closes that gap lives on the *background*, not in front. In front
    /// it wins over the field's own recognisers and swallows the long press that brings up
    /// select and paste; behind, it only sees the taps the field didn't want.
    @ViewBuilder
    private func field(_ id: Field, @ViewBuilder content: () -> some View) -> some View {
        content()
            .textFieldStyle(.plain)
            .focused($focusedField, equals: id)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemBackground))
                    .contentShape(.rect(cornerRadius: 12))
                    .onTapGesture { focusedField = id }
            }
    }

    private func notice(icon: String, text: String, isError: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .symbolEffect(.bounce, value: text)
            Text(text).frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.footnote)
        .foregroundStyle(isError ? Color.red : Color.secondary)
        .padding(14)
        .background(
            (isError ? Color.red.opacity(0.1) : Color(.secondarySystemBackground)),
            in: .rect(cornerRadius: 12)
        )
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func submit() {
        guard canSubmit, !isWorking else { return }
        focusedField = nil
        errorMessage = nil
        isWorking = true

        Task {
            do {
                switch mode {
                case .signIn:
                    try await session.signIn(email: email, password: password)
                case .signUp:
                    try await session.signUp(
                        email: email,
                        password: password,
                        displayName: displayName.trimmingCharacters(in: .whitespaces)
                    )
                    if session.pendingEmailConfirmation != nil {
                        mode = .signIn
                    }
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }
}
