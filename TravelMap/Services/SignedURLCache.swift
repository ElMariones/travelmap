import Foundation

/// Remembers the signed URL for a Storage object until shortly before it expires.
///
/// Photos are in a private bucket, so every thumbnail needs a signed URL before it can
/// load. Without a cache, scrolling a country's visits back and forth re-signs the same
/// four objects on every appearance — a network round trip each, for a URL that is still
/// perfectly valid.
///
/// It also **coalesces in-flight requests**: a grid that puts four photos on screen at
/// once used to fire four independent signings of the same path when they shared one.
/// The second caller now awaits the first caller's task instead of starting its own.
@MainActor
final class SignedURLCache {
    static let shared = SignedURLCache()

    /// Signed URLs are minted with an hour of life. Treating them as dead a minute early
    /// means a URL never expires *between* being handed out and being fetched.
    private static let safetyMargin: TimeInterval = 60

    private struct Entry {
        let url: URL
        let expiresAt: Date
    }

    private var entries: [String: Entry] = [:]
    private var inFlight: [String: Task<URL, any Error>] = [:]

    private init() {}

    func url(for path: String, expiresIn: TimeInterval = 3600) async throws -> URL {
        if let entry = entries[path], entry.expiresAt > .now {
            return entry.url
        }
        if let existing = inFlight[path] {
            return try await existing.value
        }

        let task = Task<URL, any Error> {
            try await VisitsService().signedURL(for: path)
        }
        inFlight[path] = task

        defer { inFlight[path] = nil }
        let url = try await task.value
        entries[path] = Entry(url: url, expiresAt: .now.addingTimeInterval(expiresIn - Self.safetyMargin))
        return url
    }

    /// Called on sign-out and account deletion. The URLs are signed against one user's
    /// session, and keeping them past that point is both useless and a small leak of the
    /// previous account's data into the next one's process.
    func clear() {
        entries.removeAll()
        for task in inFlight.values { task.cancel() }
        inFlight.removeAll()
    }
}
