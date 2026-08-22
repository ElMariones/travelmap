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
        Task { await loadProfile(userID: userID) }
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
}
