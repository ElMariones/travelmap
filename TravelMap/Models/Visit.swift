import Foundation

/// A country-level visit, mirroring a row in the `visits` table.
struct Visit: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let userID: UUID
    let countryCode: String
    var visitedAt: Date?
    var note: String?
    var photoURLs: [String]?
    let createdAt: Date

    /// Storage object paths for this visit's photos, at most four.
    var photos: [String] { photoURLs ?? [] }

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case countryCode = "country_code"
        case visitedAt = "visited_at"
        case note
        case photoURLs = "photo_urls"
        case createdAt = "created_at"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        userID = try container.decode(UUID.self, forKey: .userID)
        countryCode = try container.decode(String.self, forKey: .countryCode)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        photoURLs = try container.decodeIfPresent([String].self, forKey: .photoURLs)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        // `visited_at` is a Postgres `date`, which arrives as "2026-08-23" — not
        // something the client's timestamp decoding strategy can read.
        visitedAt = try container.decodeIfPresent(String.self, forKey: .visitedAt).flatMap(PostgresDate.date(from:))
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userID, forKey: .userID)
        try container.encode(countryCode, forKey: .countryCode)
        try container.encodeIfPresent(note, forKey: .note)
        try container.encodeIfPresent(photoURLs, forKey: .photoURLs)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(visitedAt.map(PostgresDate.string(from:)), forKey: .visitedAt)
    }
}

/// The insert payload for a new visit. Separate from `Visit` so the database keeps
/// ownership of `id` and `created_at`.
struct NewVisit: Encodable, Sendable {
    /// Generated on the client so the visit's photos can be uploaded to a Storage path
    /// keyed by this id before the row itself exists.
    let id: UUID
    let userID: UUID
    let countryCode: String
    let visitedAt: Date?
    let note: String?
    let photoURLs: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case countryCode = "country_code"
        case visitedAt = "visited_at"
        case note
        case photoURLs = "photo_urls"
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userID, forKey: .userID)
        try container.encode(countryCode, forKey: .countryCode)
        try container.encodeIfPresent(note, forKey: .note)
        try container.encode(photoURLs, forKey: .photoURLs)
        try container.encodeIfPresent(visitedAt.map(PostgresDate.string(from:)), forKey: .visitedAt)
    }
}

/// Converts between `Date` and the plain `YYYY-MM-DD` a Postgres `date` column uses.
///
/// Formatting happens in the user's own time zone: picking "23 August" should store
/// the 23rd, not slide to the 22nd because UTC hasn't caught up yet.
enum PostgresDate {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func string(from date: Date) -> String { formatter.string(from: date) }
    static func date(from string: String) -> Date? { formatter.date(from: string) }
}
