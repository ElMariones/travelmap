import AuthenticationServices
import Foundation
import Supabase

/// Tracks who's signed in, and keeps their profile alongside.
@MainActor
@Observable
final class SessionStore {
    enum State: Equatable {
        /// Before the stored session (if any) has been restored — shows the splash.
        case restoring
        case signedOut
        case signedIn(userID: UUID)
    }

    private(set) var state: State = .restoring
    private(set) var profile: Profile?
    var errorMessage: String?

    /// Set after a sign-up that needs email confirmation, so the UI can explain the wait.
    var pendingEmailConfirmation: String?

    /// Name to greet with once this account's first session appears.
    ///
    /// It survives a relaunch on purpose. Registering with email can require confirming
    /// the address first, which means the account is created in one launch and signed in
    /// during another — often days later. A welcome that only fires when the sign-up and
    /// the session happen in the same process would simply never fire for those users.
    private static let pendingWelcomeKey = "welcome.pendingName"

    private var pendingWelcomeName: String? {
        get { UserDefaults.standard.string(forKey: Self.pendingWelcomeKey) }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: Self.pendingWelcomeKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.pendingWelcomeKey)
            }
        }
    }

    /// Returns a welcome to show exactly once, or `nil` on every ordinary sign-in — the
    /// welcome belongs to registration, not to coming back.
    func consumeWelcome() -> PendingWelcome? {
        guard let stored = pendingWelcomeName else { return nil }
        pendingWelcomeName = nil
        return PendingWelcome(name: stored.isEmpty ? nil : stored)
    }

    /// Held between `SignInWithAppleButton`'s request and completion callbacks — the raw
    /// half of the nonce whose hash went to Apple.
    private var pendingAppleNonce: AppleSignIn.Nonce?
    /// A name Apple returned before the session existed, applied once it does.
    private var pendingAppleName: String?

    private var authService: AuthService?
    private var observationTask: Task<Void, Never>?

    var userID: UUID? {
        if case .signedIn(let userID) = state { return userID }
        return nil
    }

    init() {
        guard SupabaseEnvironment.isConfigured else {
            state = .signedOut
            return
        }
        authService = try? AuthService()
    }

    /// Restores any stored session and then follows auth changes.
    ///
    /// There's deliberately no matching teardown: this store is created by the `App` and
    /// lives as long as the process does, and `deinit` can't touch main-actor state anyway.
    func startObserving() {
        guard observationTask == nil, let authService else {
            if authService == nil { state = .signedOut }
            return
        }

        observationTask = Task { [weak self] in
            for await (event, session) in authService.authStateChanges {
                guard let self else { return }
                switch event {
                case .initialSession, .signedIn, .tokenRefreshed, .userUpdated:
                    if let session {
                        self.apply(userID: session.user.id)
                    } else {
                        self.state = .signedOut
                    }
                case .signedOut:
                    self.state = .signedOut
                    self.profile = nil
                default:
                    break
                }
            }
        }
    }

    private func apply(userID: UUID) {
        pendingEmailConfirmation = nil
        if state != .signedIn(userID: userID) {
            state = .signedIn(userID: userID)
        }
        Task {
            await applyPendingAppleName(userID: userID)
            await loadProfile(userID: userID)
        }
    }

    /// Apple hands over a name exactly once, on the first authorization, and the session
    /// doesn't exist yet at that moment. This writes it as soon as one does.
    private func applyPendingAppleName(userID: UUID) async {
        guard let name = pendingAppleName, let authService else { return }
        pendingAppleName = nil
        try? await authService.updateDisplayName(name, userID: userID)
    }

    func loadProfile(userID: UUID) async {
        guard let authService else { return }
        // A missing profile row isn't fatal — the rest of the app works without it, and
        // the Profile tab says so rather than blocking the map behind an error.
        profile = try? await authService.fetchProfile(userID: userID)
    }

    // MARK: - Actions

    func signIn(email: String, password: String) async throws {
        guard let authService else { throw SupabaseNotConfiguredError() }
        try await authService.signIn(email: email, password: password)
    }

    func signUp(email: String, password: String, displayName: String) async throws {
        guard let authService else { throw SupabaseNotConfiguredError() }
        let hasSession = try await authService.signUp(email: email, password: password, displayName: displayName)
        pendingWelcomeName = displayName
        if !hasSession {
            pendingEmailConfirmation = email
        }
    }

    func signOut() async {
        guard let authService else { return }
        do {
            try await authService.signOut()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Permanently deletes the account. See `AuthService.deleteAccount`.
    func deleteAccount() async throws {
        guard let authService else { throw SupabaseNotConfiguredError() }
        try await authService.deleteAccount()
        AppleSignIn.storedUserID = nil
        pendingWelcomeName = nil
        profile = nil
        state = .signedOut
    }

    // MARK: - Sign in with Apple

    /// Called from the button's `onRequest`. Mints the nonce and keeps the raw half.
    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = AppleSignIn.Nonce()
        pendingAppleNonce = nonce
        AppleSignIn.configure(request, nonce: nonce)
    }

    /// Called from the button's `onCompletion`.
    func completeAppleSignIn(_ result: Result<ASAuthorization, any Error>) async throws {
        guard let authService else { throw SupabaseNotConfiguredError() }
        guard let nonce = pendingAppleNonce else { return }
        pendingAppleNonce = nil

        switch result {
        case .failure(let error):
            // Backing out of the sheet is a choice, not a problem to report.
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            throw AppleSignInError(message: AppleSignIn.message(for: error))

        case .success(let authorization):
            let credential = try AppleSignIn.credential(from: authorization)
            AppleSignIn.rememberUserID(from: authorization)
            pendingAppleName = credential.fullName
            // Apple hands over a name only on the *first* authorization for this app, so
            // its presence is the one reliable signal that this is a new account.
            if let name = credential.fullName { pendingWelcomeName = name }
            try await authService.signInWithApple(credential: credential, nonce: nonce)
        }
    }

    /// Signs the user out if they revoked this app's Apple authorization elsewhere.
    ///
    /// Revoking in Settings is a decision; an app that stays signed in afterwards is
    /// quietly ignoring it. Checked on launch and whenever the app comes back to the
    /// foreground, since the notification only fires while the app is running.
    func verifyAppleAuthorization() async {
        guard AppleSignIn.storedUserID != nil, userID != nil else { return }
        if await AppleSignIn.isStillAuthorized() == false {
            AppleSignIn.storedUserID = nil
            await signOut()
        }
    }
}

#if DEBUG
extension SessionStore {
    func loadScreenshotProfile(userID: UUID) {
        observationTask?.cancel()
        observationTask = nil
        state = .signedIn(userID: userID)
        profile = Profile(
            id: userID,
            displayName: "Mario",
            friendCode: "TRVL2026",
            avatarURL: nil
        )
    }
}
#endif

/// A greeting owed to a newly registered account. The name is optional because Apple
/// doesn't always give one, and an anonymous welcome still beats no welcome.
struct PendingWelcome: Equatable {
    let name: String?
}

/// Carries an already-humanised Apple authorization failure to the UI.
struct AppleSignInError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
