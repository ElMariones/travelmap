import Foundation

enum VisitDatePrecision: String, Codable, CaseIterable, Sendable {
    case year
    case month
}

/// A country-level visit, mirroring a row in the `visits` table.
struct Visit: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let userID: UUID
    let countryCode: String
    var title: String?
    var visitedAt: Date?
    var datePrecision: VisitDatePrecision?
    var note: String?
    var photoURLs: [String]?
    let createdAt: Date

    /// Storage object paths for this visit's photos, at most four.
    var photos: [String] { photoURLs ?? [] }

    func displayTitle(countryName: String) -> String {
        guard let title, !title.isEmpty else { return "Visit to \(countryName)" }
        return title
    }

    var visitedDateText: String {
        guard let visitedAt else { return "Date not set" }
        switch datePrecision {
        case .year:
            return visitedAt.formatted(.dateTime.year())
        case .month:
            return visitedAt.formatted(.dateTime.month(.wide).year())
        case nil:
            // V1 stored exact days. Keep those records truthful until the user edits one,
            // at which point the form intentionally converts it to month precision.
            return visitedAt.formatted(.dateTime.day().month(.wide).year())
        }
    }

    static func isLater(_ lhs: Visit, than rhs: Visit) -> Bool {
        switch (lhs.visitedAt, rhs.visitedAt) {
        case let (left?, right?) where left != right:
            return left > right
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            return lhs.createdAt > rhs.createdAt
        }
    }

    init(
        id: UUID = UUID(),
        userID: UUID,
        countryCode: String,
        title: String? = nil,
        visitedAt: Date? = nil,
        datePrecision: VisitDatePrecision? = nil,
        note: String? = nil,
        photoURLs: [String]? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.userID = userID
        self.countryCode = countryCode
        self.title = title
        self.visitedAt = visitedAt
        self.datePrecision = datePrecision
        self.note = note
        self.photoURLs = photoURLs
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case countryCode = "country_code"
        case title
        case visitedAt = "visited_at"
        case datePrecision = "date_precision"
        case note
        case photoURLs = "photo_urls"
        case createdAt = "created_at"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        userID = try container.decode(UUID.self, forKey: .userID)
        countryCode = try container.decode(String.self, forKey: .countryCode)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        datePrecision = try container.decodeIfPresent(VisitDatePrecision.self, forKey: .datePrecision)
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
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(datePrecision, forKey: .datePrecision)
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
    let title: String
    let visitedAt: Date?
    let datePrecision: VisitDatePrecision?
    let note: String?
    let photoURLs: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case countryCode = "country_code"
        case title
        case visitedAt = "visited_at"
        case datePrecision = "date_precision"
        case note
        case photoURLs = "photo_urls"
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userID, forKey: .userID)
        try container.encode(countryCode, forKey: .countryCode)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(datePrecision, forKey: .datePrecision)
        try container.encodeIfPresent(note, forKey: .note)
        try container.encode(photoURLs, forKey: .photoURLs)
        try container.encodeIfPresent(visitedAt.map(PostgresDate.string(from:)), forKey: .visitedAt)
    }
}

/// The editable columns of an existing visit. Ownership, country, and creation time do
/// not change when a visit is edited.
struct VisitUpdate: Encodable, Sendable {
    let title: String
    let visitedAt: Date?
    let datePrecision: VisitDatePrecision?
    let note: String?
    let photoURLs: [String]

    enum CodingKeys: String, CodingKey {
        case title
        case visitedAt = "visited_at"
        case datePrecision = "date_precision"
        case note
        case photoURLs = "photo_urls"
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        // Updates must encode nil as JSON null rather than omit the key, otherwise
        // clearing a previously entered date or note leaves the old database value.
        try container.encode(visitedAt.map(PostgresDate.string(from:)), forKey: .visitedAt)
        try container.encode(datePrecision, forKey: .datePrecision)
        try container.encode(note, forKey: .note)
        try container.encode(photoURLs, forKey: .photoURLs)
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

    static func partialDate(year: Int, month: Int? = nil) -> Date? {
        let resolvedMonth = month ?? 1
        guard (1...12).contains(resolvedMonth) else { return nil }
        return Calendar.current.date(from: DateComponents(year: year, month: resolvedMonth, day: 1))
    }
}
