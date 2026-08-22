import SwiftUI

/// Email + password sign-in and sign-up.
struct AuthView: View {
    private enum Mode {
        case signIn, signUp

        var title: String { self == .signIn ? "Welcome back" : "Create your map" }
        var actionTitle: String { self == .signIn ? "Sign in" : "Sign up" }
        var switchPrompt: String {
            self == .signIn ? "New here? Create an account" : "Already have an account? Sign in"
        }
    }

    @Environment(SessionStore.self) private var session

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
        ScrollView {
            VStack(spacing: 28) {
                header

                VStack(spacing: 12) {
                    if mode == .signUp {
                        TextField("Display name", text: $displayName)
                            .textContentType(.name)
                            .focused($focusedField, equals: .name)
                            .fieldStyle()
                    }

                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .email)
                        .fieldStyle()

                    SecureField("Password", text: $password)
                        .textContentType(mode == .signIn ? .password : .newPassword)
                        .focused($focusedField, equals: .password)
                        .fieldStyle()
                        .onSubmit(submit)
                }

                if let confirmationEmail = session.pendingEmailConfirmation {
                    noticeBox(
                        icon: "envelope.badge",
                        text: "Confirm your address from the email we sent to \(confirmationEmail), then sign in."
                    )
                }

                if let errorMessage {
                    noticeBox(icon: "exclamationmark.triangle.fill", text: errorMessage, isError: true)
                }

                VStack(spacing: 14) {
                    Button(action: submit) {
                        Group {
                            if isWorking {
                                ProgressView().tint(.white)
                            } else {
                                Text(mode.actionTitle).font(.headline)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSubmit || isWorking)

                    Button(mode.switchPrompt) {
                        withAnimation { mode = mode == .signIn ? .signUp : .signIn }
                        errorMessage = nil
                    }
                    .font(.subheadline)
                }
            }
            .padding(28)
        }
        .background(Color(.systemBackground))
        .scrollDismissesKeyboard(.interactively)
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "globe.europe.africa.fill")
                .font(.system(size: 52))
                .foregroundStyle(AppTheme.accent)
            Text(mode.title)
                .font(.title.weight(.semibold))
            Text("Log where you've been and watch the world fill in.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 40)
    }

    private func noticeBox(icon: String, text: String, isError: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
            Text(text).frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.footnote)
        .foregroundStyle(isError ? Color.red : Color.secondary)
        .padding(14)
        .background(
            (isError ? Color.red.opacity(0.1) : Color(.secondarySystemBackground)),
            in: .rect(cornerRadius: 12)
        )
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

private extension View {
    func fieldStyle() -> some View {
        textFieldStyle(.plain)
            .padding(14)
            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 12))
    }
}
