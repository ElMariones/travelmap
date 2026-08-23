import Foundation
import Supabase

/// Email + password authentication, and the profile row that hangs off each account.
struct AuthService: Sendable {
    private let client: SupabaseClient

    init() throws {
        guard let client = SupabaseClientProvider.shared else { throw SupabaseNotConfiguredError() }
        self.client = client
    }

    var currentUser: User? {
        get async { try? await client.auth.session.user }
    }

    /// Emits on sign-in, sign-out, and token refresh, so the UI can follow along.
    var authStateChanges: AsyncStream<(event: AuthChangeEvent, session: Session?)> {
        client.auth.authStateChanges
    }

    func signIn(email: String, password: String) async throws {
        try await client.auth.signIn(email: email, password: password)
    }

    /// Creates the account. The `profiles` row is created by a Postgres trigger that
    /// reads `display_name` back out of this metadata.
    ///
    /// Returns `false` when the project requires email confirmation, in which case there's
    /// no session yet and the caller should say so rather than pretending sign-in worked.
    @discardableResult
    func signUp(email: String, password: String, displayName: String) async throws -> Bool {
        let response = try await client.auth.signUp(
            email: email,
            password: password,
            data: ["display_name": .string(displayName)]
        )
        return response.session != nil
    }

    /// Exchanges Apple's identity token for a Supabase session.
    ///
    /// The raw nonce goes to Supabase, not the hash: the token carries the hash, and the
    /// backend recomputes it from this value to prove the two halves belong together.
    func signInWithApple(credential: AppleSignIn.Credential, nonce: AppleSignIn.Nonce) async throws {
        try await client.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(
                provider: .apple,
                idToken: credential.identityToken,
                nonce: nonce.raw
            )
        )
    }

    func signOut() async throws {
        try await client.auth.signOut()
    }

    /// Permanently deletes the account and everything attached to it.
    ///
    /// Apple requires any app that can create an account to be able to delete one
    /// (App Review Guideline 5.1.1(v)). Removing a row from `auth.users` is beyond what
    /// a client key can do, so this calls a `security definer` function that owns the
    /// deletion; the cascades and the storage cleanup happen inside it.
    func deleteAccount() async throws {
        try await client.rpc("delete_account").execute()
        try? await client.auth.signOut()
    }

    /// Stores a display name on the profile — used to save the name Apple hands over on
    /// the first authorization and never again.
    func updateDisplayName(_ displayName: String, userID: UUID) async throws {
        try await client
            .from("profiles")
            .update(["display_name": displayName])
            .eq("id", value: userID)
            .execute()
    }

    func fetchProfile(userID: UUID) async throws -> Profile {
        try await client
            .from("profiles")
            .select()
            .eq("id", value: userID)
            .single()
            .execute()
            .value
    }
}
