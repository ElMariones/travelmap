import Foundation

/// The six continent buckets the app groups countries into.
///
/// Raw values match the `continent` property written into `countries.geojson`
/// by `scripts/build-mapdata.mjs`, so decoding is a straight lookup.
enum Continent: String, CaseIterable, Codable, Identifiable, Sendable {
    case africa = "Africa"
    case asia = "Asia"
    case europe = "Europe"
    case northAmerica = "North America"
    case southAmerica = "South America"
    case oceania = "Oceania"

    var id: String { rawValue }

    /// Full name, for stats rows and other places with room to breathe.
    var displayName: String { rawValue }

    /// Abbreviated name for the map's filter chips, where horizontal space is tight.
    var shortName: String {
        switch self {
        case .africa: return "Africa"
        case .asia: return "Asia"
        case .europe: return "Europe"
        case .northAmerica: return "N. America"
        case .southAmerica: return "S. America"
        case .oceania: return "Oceania"
        }
    }

    /// Display order for the filter chips and the stats breakdown.
    static let displayOrder: [Continent] = [
        .europe, .asia, .africa, .northAmerica, .southAmerica, .oceania,
    ]
}
