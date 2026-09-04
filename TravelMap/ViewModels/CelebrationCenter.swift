import Foundation

/// One thing worth celebrating, in the shape the overlay needs to draw it.
struct Celebration: Identifiable, Equatable {
    let id: String
    let symbol: String
    let title: String
    let blurb: String
    let intensity: ConfettiIntensity

    static func welcome(name: String?) -> Celebration {
        Celebration(
            id: "welcome",
            symbol: "globe.europe.africa.fill",
            title: name.map { "Welcome, \($0)" } ?? "Welcome aboard",
            blurb: "Your map starts empty and gray. Log the first country and watch it fill in.",
            intensity: .celebration
        )
    }

    static func milestone(_ milestone: Milestone) -> Celebration {
        Celebration(
            id: milestone.id,
            symbol: milestone.symbol,
            title: milestone.title,
            blurb: milestone.blurb,
            intensity: .celebration
        )
    }
}

/// What one save actually changed, so the app can react proportionally.
struct SaveOutcome: Equatable {
    /// True when the country was gray before this save — the map visibly changed colour.
    let filledANewCountry: Bool
    let milestones: [Milestone]
}

/// The single owner of "something good just happened".
///
/// Everything celebratory funnels through here: the haptic, the confetti trigger, and the
/// overlay queue. That is the point — when a store *and* a view both react to the same
/// save, the user gets a double buzz and two overlapping animations. One owner, one beat.
///
/// Celebrations queue rather than overwrite. A single save can finish a continent *and*
/// cross a round number, and swallowing one of them to show the other would mean the
/// rarest events are the ones most likely to go unseen.
@MainActor
@Observable
final class CelebrationCenter {
    /// The celebration on screen right now, if any.
    private(set) var current: Celebration?
    /// Bumped on every burst; `ConfettiView` watches it.
    private(set) var confettiTrigger = 0

    private var queue: [Celebration] = []
    private let haptics: Haptics

    init(haptics: Haptics) {
        self.haptics = haptics
    }

    // MARK: - Input

    /// Reacts to a saved visit: one haptic sized to what changed, then any milestones.
    func record(_ outcome: SaveOutcome) {
        haptics.fire(outcome.milestones.isEmpty
            ? (outcome.filledANewCountry ? .newCountry : .visitLogged)
            : .milestone)

        for milestone in outcome.milestones {
            enqueue(.milestone(milestone))
        }
    }

    /// Shown once, after the account is created — not on every sign-in.
    func welcome(name: String?) {
        haptics.fire(.welcome)
        enqueue(.welcome(name: name))
    }

    // MARK: - Queue

    private func enqueue(_ celebration: Celebration) {
        // Re-entering the same celebration while it's on screen would restart its
        // animation from the top for no reason.
        guard current?.id != celebration.id, !queue.contains(celebration) else { return }
        if current == nil {
            show(celebration)
        } else {
            queue.append(celebration)
        }
    }

    private func show(_ celebration: Celebration) {
        current = celebration
        confettiTrigger += 1
    }

    /// Dismisses the current celebration and shows the next one, if there is one.
    func advance() {
        guard !queue.isEmpty else {
            current = nil
            return
        }
        let next = queue.removeFirst()
        haptics.fire(.milestone)
        show(next)
    }
}
