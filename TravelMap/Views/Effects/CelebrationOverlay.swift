import SwiftUI

/// The full-screen moment: scrim, confetti, and a card that says what just happened.
///
/// It does not auto-dismiss. A timed dismissal races the user — and races VoiceOver,
/// which may still be reading the announcement when the view disappears out from under
/// it. The card is dismissed by its button or by a tap anywhere on the scrim.
struct CelebrationOverlay: View {
    let celebration: Celebration
    let confettiTrigger: Int
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    var body: some View {
        ZStack {
            // Our own dimming, drawn before anything else. It is what makes the card
            // legible over a map that could be pale ocean or dark terrain, and it doubles
            // as the tap target for dismissal.
            Rectangle()
                .fill(.black.opacity(0.42))
                .ignoresSafeArea()
                .onTapGesture(perform: dismiss)
                .accessibilityHidden(true)

            ConfettiView(trigger: confettiTrigger, intensity: celebration.intensity)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            card
        }
        .transition(.opacity)
        // The overlay owns the screen while it's up, so VoiceOver shouldn't be able to
        // swipe past it into the map behind.
        .accessibilityAddTraits(.isModal)
        .task {
            hasAppeared = true
            // Reduce Motion users get no confetti, so the announcement is the whole
            // event for them — and it's what makes this reach VoiceOver at all.
            AccessibilityNotification.Announcement("\(celebration.title). \(celebration.blurb)")
                .post()
        }
    }

    private var card: some View {
        VStack(spacing: 18) {
            Image(systemName: celebration.symbol)
                .font(.system(size: 64))
                .foregroundStyle(AppTheme.accent)
                .symbolEffect(.bounce, options: .nonRepeating, value: hasAppeared)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text(celebration.title)
                    .font(.title.weight(.bold))
                    .multilineTextAlignment(.center)

                Text(celebration.blurb)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button(action: dismiss) {
                Text("Nice")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(AppTheme.accent)
        }
        .padding(28)
        .frame(maxWidth: 340)
        // Regular glass, not clear. The scrim behind it is ours, but the map behind
        // *that* is not, and regular is the material that carries its own legibility.
        .glassEffect(AppTheme.regularGlass, in: .rect(cornerRadius: 28))
        .padding(.horizontal, 32)
        .scaleEffect(scale)
        .animation(AppTheme.Motion.bouncy, value: hasAppeared)
        .accessibilityElement(children: .contain)
    }

    /// The card springs in — unless the user asked for less motion, in which case it
    /// simply fades with the rest of the overlay and loses nothing but the flourish.
    private var scale: CGFloat {
        guard !reduceMotion else { return 1 }
        return hasAppeared ? 1 : 0.86
    }

    private func dismiss() {
        withAnimation(AppTheme.Motion.snappy) { onDismiss() }
    }
}

/// Hangs the celebration overlay off any view, driven by the shared ``CelebrationCenter``.
///
/// It lives on the tab container rather than on a single screen so a milestone crossed
/// while the add-visit sheet is closing still lands somewhere visible.
struct CelebrationHost: ViewModifier {
    @Environment(CelebrationCenter.self) private var celebrations

    func body(content: Content) -> some View {
        content
            .overlay {
                if let celebration = celebrations.current {
                    CelebrationOverlay(
                        celebration: celebration,
                        confettiTrigger: celebrations.confettiTrigger,
                        onDismiss: celebrations.advance
                    )
                    .id(celebration.id)
                }
            }
            .animation(AppTheme.Motion.bouncy, value: celebrations.current)
    }
}

extension View {
    func celebrationHost() -> some View { modifier(CelebrationHost()) }
}
