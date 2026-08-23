import Foundation
import Supabase

/// Supabase credentials, read from `Config.xcconfig` by way of `Info.plist`.
///
/// The template values in `Config.xcconfig.example` are treated as "not configured"
/// so a fresh clone still builds and launches — it just shows the setup screen
/// instead of the map.
enum SupabaseEnvironment {
    struct Configuration: Sendable {
        let url: URL
        let publishableKey: String
    }

    /// Why the app can't talk to Supabase, when it can't.
    enum Problem: Sendable {
        case notConfigured
        /// A server-side key was pasted into the client config. This one is worth catching
        /// loudly: a secret key bypasses Row Level Security, and anyone who unpacks the app
        /// binary would be able to read and delete every user's data.
        case serverSideKey
    }

    private static let placeholders: Set<String> = [
        "https://your-project-ref.supabase.co", "your-anon-key", "your-publishable-key", "",
    ]

    private static let resolved: (configuration: Configuration?, problem: Problem?) = {
        let info = Bundle.main.infoDictionary
        let rawURL = (info?["SupabaseURL"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        let key = (info?["SupabaseAnonKey"] as? String ?? "").trimmingCharacters(in: .whitespaces)

        // The wrong-key check comes first: it's the more dangerous mistake, and it should
        // be reported even when the URL is also wrong.
        guard !isServerSideKey(key) else { return (nil, .serverSideKey) }

        guard !placeholders.contains(rawURL), !placeholders.contains(key),
              let url = URL(string: rawURL), url.host != nil
        else { return (nil, .notConfigured) }

        return (Configuration(url: url, publishableKey: key), nil)
    }()

    static var configuration: Configuration? { resolved.configuration }
    static var problem: Problem? { resolved.problem }
    static var isConfigured: Bool { resolved.configuration != nil }

    /// Recognises both key formats Supabase issues: the current `sb_secret_` prefix and
    /// the legacy `service_role` JWT.
    private static func isServerSideKey(_ key: String) -> Bool {
        if key.hasPrefix("sb_secret_") { return true }

        let segments = key.split(separator: ".")
        guard segments.count == 3, let payload = base64URLDecoded(String(segments[1])),
              let claims = try? JSONSerialization.jsonObject(with: payload) as? [String: Any]
        else { return false }

        return claims["role"] as? String == "service_role"
    }

    private static func base64URLDecoded(_ value: String) -> Data? {
        var normalized = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        normalized += String(repeating: "=", count: (4 - normalized.count % 4) % 4)
        return Data(base64Encoded: normalized)
    }
}

/// The single Supabase client the app talks to. `nil` until credentials are filled in.
enum SupabaseClientProvider {
    static let shared: SupabaseClient? = {
        guard let configuration = SupabaseEnvironment.configuration else { return nil }
        return SupabaseClient(supabaseURL: configuration.url, supabaseKey: configuration.publishableKey)
    }()

    /// Storage bucket holding visit photos. Created by `supabase/schema.sql`.
    static let photoBucket = "visit-photos"
}

/// Raised when a screen needs the client but the app was never configured.
struct SupabaseNotConfiguredError: LocalizedError {
    var errorDescription: String? {
        "TravelMap isn't connected to Supabase yet. Copy Config.xcconfig.example to Config.xcconfig and fill in your project URL and publishable key."
    }
}
