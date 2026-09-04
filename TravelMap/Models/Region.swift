import Foundation

/// A first-level local subdivision from the bundled Natural Earth reference set.
struct Region: Identifiable, Hashable, Sendable {
    var id: String { code }
    let code: String
    let countryCode: String
    let name: String
}

/// Region completion uses the same display and rounding rules as country completion.
enum RegionProgress {
    static func make<S: Sequence>(regionCodes: S, total: Int) -> VisitProgress where S.Element == String {
        VisitProgress(visited: Set(regionCodes).count, total: total)
    }
}
