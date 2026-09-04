import Foundation

/// One logged local subdivision, mirroring a row in `region_visits`.
struct RegionVisit: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let userID: UUID
    let countryCode: String
    let regionCode: String
    var visitedAt: Date?
    var note: String?
    var photoURLs: [String]?
    let createdAt: Date

    var photos: [String] { photoURLs ?? [] }

    var visitedDateText: String {
        visitedAt?.formatted(.dateTime.day().month(.wide).year()) ?? "Date not set"
    }

    static func isLater(_ lhs: RegionVisit, than rhs: RegionVisit) -> Bool {
        switch (lhs.visitedAt, rhs.visitedAt) {
        case let (left?, right?) where left != right: left > right
        case (_?, nil): true
        case (nil, _?): false
        default: lhs.createdAt > rhs.createdAt
        }
    }

    init(
        id: UUID = UUID(),
        userID: UUID,
        countryCode: String,
        regionCode: String,
        visitedAt: Date? = nil,
        note: String? = nil,
        photoURLs: [String]? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.userID = userID
        self.countryCode = countryCode
        self.regionCode = regionCode
        self.visitedAt = visitedAt
        self.note = note
        self.photoURLs = photoURLs
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case countryCode = "country_code"
        case regionCode = "region_code"
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
        regionCode = try container.decode(String.self, forKey: .regionCode)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        photoURLs = try container.decodeIfPresent([String].self, forKey: .photoURLs)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        visitedAt = try container.decodeIfPresent(String.self, forKey: .visitedAt).flatMap(PostgresDate.date(from:))
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userID, forKey: .userID)
        try container.encode(countryCode, forKey: .countryCode)
        try container.encode(regionCode, forKey: .regionCode)
        try container.encodeIfPresent(note, forKey: .note)
        try container.encodeIfPresent(photoURLs, forKey: .photoURLs)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(visitedAt.map(PostgresDate.string(from:)), forKey: .visitedAt)
    }
}

struct NewRegionVisit: Encodable, Sendable {
    let id: UUID
    let userID: UUID
    let countryCode: String
    let regionCode: String
    let visitedAt: Date?
    let note: String?
    let photoURLs: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case countryCode = "country_code"
        case regionCode = "region_code"
        case visitedAt = "visited_at"
        case note
        case photoURLs = "photo_urls"
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userID, forKey: .userID)
        try container.encode(countryCode, forKey: .countryCode)
        try container.encode(regionCode, forKey: .regionCode)
        try container.encodeIfPresent(visitedAt.map(PostgresDate.string(from:)), forKey: .visitedAt)
        try container.encodeIfPresent(note, forKey: .note)
        try container.encode(photoURLs, forKey: .photoURLs)
    }
}

struct RegionVisitUpdate: Encodable, Sendable {
    let visitedAt: Date?
    let note: String?
    let photoURLs: [String]

    enum CodingKeys: String, CodingKey {
        case visitedAt = "visited_at"
        case note
        case photoURLs = "photo_urls"
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(visitedAt.map(PostgresDate.string(from:)), forKey: .visitedAt)
        try container.encode(note, forKey: .note)
        try container.encode(photoURLs, forKey: .photoURLs)
    }
}
