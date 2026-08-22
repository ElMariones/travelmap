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
        let anonKey: String
    }

    private static let placeholders: Set<String> = [
        "https://your-project-ref.supabase.co", "your-anon-key", "",
    ]

    static let configuration: Configuration? = {
        let info = Bundle.main.infoDictionary
        let rawURL = (info?["SupabaseURL"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        let anonKey = (info?["SupabaseAnonKey"] as? String ?? "").trimmingCharacters(in: .whitespaces)

        guard !placeholders.contains(rawURL), !placeholders.contains(anonKey),
              let url = URL(string: rawURL), url.host != nil
        else { return nil }

        return Configuration(url: url, anonKey: anonKey)
    }()

    static var isConfigured: Bool { configuration != nil }
}

/// The single Supabase client the app talks to. `nil` until credentials are filled in.
enum SupabaseClientProvider {
    static let shared: SupabaseClient? = {
        guard let configuration = SupabaseEnvironment.configuration else { return nil }
        return SupabaseClient(supabaseURL: configuration.url, supabaseKey: configuration.anonKey)
    }()

    /// Storage bucket holding visit photos. Created by `supabase/schema.sql`.
    static let photoBucket = "visit-photos"
}

/// Raised when a screen needs the client but the app was never configured.
struct SupabaseNotConfiguredError: LocalizedError {
    var errorDescription: String? {
        "TravelMap isn't connected to Supabase yet. Copy Config.xcconfig.example to Config.xcconfig and fill in your project URL and anon key."
    }
}
