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

    func signOut() async throws {
        try await client.auth.signOut()
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
