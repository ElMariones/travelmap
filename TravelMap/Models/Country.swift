import Foundation

/// One country in the reference set, loaded from the bundled Natural Earth data.
///
/// The reference set is the denominator for every percentage in the app: totals are
/// never stored, only derived from these against the user's visits.
struct Country: Identifiable, Hashable, Sendable {
    /// ISO 3166-1 alpha-2, e.g. `"ES"`. Matches `visits.country_code` in Postgres.
    let code: String
    let name: String
    let continent: Continent

    var id: String { code }

    /// Flag emoji derived from the ISO code's regional indicator symbols.
    var flag: String {
        code.unicodeScalars.reduce(into: "") { result, scalar in
            if let indicator = UnicodeScalar(scalar.value + 127_397) {
                result.unicodeScalars.append(indicator)
            }
        }
    }
}
