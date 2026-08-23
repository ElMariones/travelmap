import AuthenticationServices
import CryptoKit
import Foundation

/// The pieces of Sign in with Apple that aren't Supabase's concern: the nonce, and
/// pulling the useful parts out of a credential.
enum AppleSignIn {
    /// A one-time value that ties the credential Apple returns to the request this app
    /// made. Apple receives the SHA-256 hash and embeds it in the identity token; the
    /// backend receives the raw value and checks that it hashes to what the token claims.
    /// Without it, a token captured elsewhere could be replayed against this app.
    struct Nonce: Sendable {
        let raw: String
        let hashed: String

        init() {
            // Unreserved URL characters, so the value survives every transport intact.
            let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
            var generator = SystemRandomNumberGenerator()
            raw = String((0..<32).map { _ in alphabet[Int(generator.next(upperBound: UInt64(alphabet.count)))] })
            hashed = SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
        }
    }

    /// What a successful authorization gives the app.
    struct Credential {
        let identityToken: String
        /// Apple returns a name *only* on the very first authorization for this app, and
        /// never again. If it's here, it has to be persisted now or it's gone.
        let fullName: String?
    }

    enum Failure: LocalizedError {
        case missingIdentityToken

        var errorDescription: String? {
            switch self {
            case .missingIdentityToken:
                return "Apple didn't return an identity token. Try signing in again."
            }
        }
    }

    /// Turns an `ASAuthorizationError` into something worth showing someone.
    ///
    /// The raw errors surface as "error 1000" with no hint of the cause, and the most
    /// common cause by far — no Apple Account signed in on the device — is something the
    /// user can actually fix once they're told.
    static func message(for error: any Error) -> String {
        guard let authorizationError = error as? ASAuthorizationError else {
            return error.localizedDescription
        }

        switch authorizationError.code {
        case .canceled:
            return "Sign in was cancelled."
        case .unknown:
            return "Sign in with Apple isn't available right now. Check that you're signed in to an Apple Account in Settings."
        case .notHandled, .notInteractive:
            return "Apple couldn't complete the request. Try again in a moment."
        case .invalidResponse:
            return "Apple returned an unexpected response. Try signing in again."
        case .failed:
            return "Apple couldn't verify the request. Try again, or continue with email."
        default:
            return error.localizedDescription
        }
    }

    /// Configures the request. Scopes are deliberately minimal: a name to greet the user
    /// by, and the email Apple uses as the account key — nothing else is asked for.
    static func configure(_ request: ASAuthorizationAppleIDRequest, nonce: Nonce) {
        request.requestedScopes = [.fullName, .email]
        request.nonce = nonce.hashed
    }

    static func credential(from authorization: ASAuthorization) throws -> Credential {
        guard let appleCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = appleCredential.identityToken,
              let identityToken = String(data: tokenData, encoding: .utf8)
        else { throw Failure.missingIdentityToken }

        return Credential(
            identityToken: identityToken,
            fullName: appleCredential.fullName.flatMap(formattedName)
        )
    }

    private static func formattedName(_ components: PersonNameComponents) -> String? {
        let formatted = PersonNameComponentsFormatter.localizedString(from: components, style: .default)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return formatted.isEmpty ? nil : formatted
    }

    /// The user id Apple gave this account, kept so the app can ask Apple whether that
    /// authorization is still good. Not a secret — it's an opaque per-app identifier.
    private static let storedUserIDKey = "apple.user.id"

    static var storedUserID: String? {
        get { UserDefaults.standard.string(forKey: storedUserIDKey) }
        set { UserDefaults.standard.set(newValue, forKey: storedUserIDKey) }
    }

    static func rememberUserID(from authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }
        storedUserID = credential.user
    }

    /// True when Apple still considers this app authorized. A user can revoke it from
    /// Settings at any time, and an app that keeps them signed in afterwards is ignoring
    /// a decision they already made.
    static func isStillAuthorized() async -> Bool {
        guard let userID = storedUserID else { return true }
        let state = try? await ASAuthorizationAppleIDProvider().credentialState(forUserID: userID)
        return state == .authorized
    }
}
