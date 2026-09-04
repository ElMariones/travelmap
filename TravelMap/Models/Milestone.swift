import Foundation

/// A moment worth stopping the app for.
///
/// Milestones are **derived, never stored** — the same rule the percentages follow. A
/// milestone is "reached" if the user's current map satisfies it, and it is *celebrated*
/// only at the instant it flips from unreached to reached, which the store works out by
/// comparing the map before a save with the map after. Nothing is persisted, so nothing
/// can drift out of step with the visits themselves.
struct Milestone: Identifiable, Hashable, Sendable {
    let id: String
    /// The headline on the celebration card. Short — it sits under a burst of confetti.
    let title: String
    /// One line explaining what was just achieved.
    let blurb: String
    let symbol: String

    // MARK: - The set

    /// Country-count thresholds. The gaps widen deliberately: early milestones should
    /// arrive close together, and later ones should stay rare enough to still mean
    /// something.
    static let countThresholds = [1, 5, 10, 25, 50, 75, 100, 150]

    static func forCount(_ count: Int) -> Milestone? {
        guard countThresholds.contains(count) else { return nil }
        if count == 1 {
            return Milestone(
                id: "count-1",
                title: "Your first country",
                blurb: "One down. The map starts filling in from here.",
                symbol: "flag.checkered"
            )
        }
        return Milestone(
            id: "count-\(count)",
            title: "\(count) countries",
            blurb: "You've now logged \(count) countries.",
            symbol: "globe.europe.africa.fill"
        )
    }

    static func forContinent(_ continent: Continent) -> Milestone {
        Milestone(
            id: "continent-\(continent.rawValue)",
            title: "\(continent.displayName), complete",
            blurb: "Every country in \(continent.displayName) is on your map.",
            symbol: "checkmark.seal.fill"
        )
    }

    /// Whole-world share thresholds, as percentages.
    static let shareThresholds = [10, 25, 50, 75]

    static func forWorldShare(_ percent: Int) -> Milestone? {
        guard shareThresholds.contains(percent) else { return nil }
        return Milestone(
            id: "share-\(percent)",
            title: "\(percent)% of the world",
            blurb: "You've set foot in \(percent)% of the world's countries.",
            symbol: "globe.badge.chevron.backward"
        )
    }

    // MARK: - Detection

    /// Every milestone the move from `before` to `after` just crossed.
    ///
    /// Pure, and takes the whole reference set rather than reading a store, so the whole
    /// rule set is testable without a network or a signed-in user.
    ///
    /// Only *newly* satisfied milestones come back, so removing a visit and re-adding it
    /// doesn't replay the confetti. Continent completions are checked before the count
    /// and share thresholds because finishing a continent is the rarer, better story when
    /// one save happens to trigger both.
    static func crossed(
        from before: Set<String>,
        to after: Set<String>,
        countries: [Country]
    ) -> [Milestone] {
        guard after.count > before.count else { return [] }
        var crossed: [Milestone] = []

        for continent in Continent.displayOrder {
            let codes = Set(countries.filter { $0.continent == continent }.map(\.code))
            guard !codes.isEmpty else { continue }
            let wasComplete = codes.isSubset(of: before)
            let isComplete = codes.isSubset(of: after)
            if isComplete, !wasComplete { crossed.append(forContinent(continent)) }
        }

        for threshold in countThresholds where before.count < threshold && after.count >= threshold {
            if let milestone = forCount(threshold) { crossed.append(milestone) }
        }

        if !countries.isEmpty {
            let total = Double(countries.count)
            for threshold in shareThresholds {
                let beforeShare = Double(before.count) / total * 100
                let afterShare = Double(after.count) / total * 100
                if beforeShare < Double(threshold), afterShare >= Double(threshold),
                   let milestone = forWorldShare(threshold) {
                    crossed.append(milestone)
                }
            }
        }

        return crossed
    }
}
