import AuthenticationServices
import SwiftUI

/// The first thing anyone sees. Sign in with Apple is the primary path; email is the
/// alternative, and it lives behind a sheet so this screen stays a single decision.
struct LandingView: View {
    @Environment(SessionStore.self) private var session
    @Environment(Haptics.self) private var haptics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The wordmark scales with the user's text size like every other piece of type here.
    @ScaledMetric(relativeTo: .largeTitle) private var wordmarkSize: CGFloat = 44

    @State private var isShowingEmailAuth = false
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var hasAppeared = false

    @Namespace private var glass

    var body: some View {
        ZStack {
            AuroraBackground()
                .ignoresSafeArea()

            // The dimming layer that earns the right to use clear glass above it. Without
            // it, clear glass over a bright mesh would leave white text unreadable.
            LinearGradient(
                colors: [.black.opacity(0.10), .black.opacity(0.55)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                hero
                Spacer(minLength: 0)
                actions
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 28)
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $isShowingEmailAuth) {
            EmailAuthSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .task { hasAppeared = true }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: 22) {
            globeMark

            VStack(spacing: 10) {
                Text("TravelMap")
                    .font(.system(size: wordmarkSize, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.6)

                Text("Log a country in ten seconds\nand watch your world fill in.")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.82))
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }

            // Clear glass, over content this screen dims itself. Everywhere the app sits
            // over something it doesn't control — the map — it uses regular glass instead.
            GlassEffectContainer(spacing: 14) {
                Label("236 countries, one colour", systemImage: "sparkles")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .glassEffect(AppTheme.clearGlass, in: .capsule)
                    .glassEffectID("tagline", in: glass)
            }
        }
        .opacity(hasAppeared ? 1 : 0)
        .animation(reduceMotion ? .easeIn(duration: 0.2) : AppTheme.Motion.gentle.delay(0.15), value: hasAppeared)
    }

    /// The mark arrives on a multi-track keyframe sequence — scale, lift, and tilt each
    /// run on their own curve so it settles like an object rather than a fading image —
    /// then hands off to a continuous phase loop.
    private var globeMark: some View {
        Image(systemName: "globe.europe.africa.fill")
            .font(.system(size: 96))
            .foregroundStyle(.white)
            // Deliberately no indefinite symbol effect here. `breathe` dips a symbol's
            // opacity far enough that a brand mark visibly washes out at the bottom of
            // the cycle; the phase drift below gives it life without fading it.
            // Both the idle drift and the entrance are decoration on a mark that is
            // perfectly legible standing still, so Reduce Motion removes them outright
            // rather than substituting something smaller.
            .phaseAnimator(DriftPhase.allCases, trigger: hasAppeared && !reduceMotion) { view, phase in
                view
                    .offset(y: reduceMotion ? 0 : phase.lift)
                    .rotationEffect(.degrees(reduceMotion ? 0 : phase.tilt))
            } animation: { _ in
                AppTheme.Motion.gentle.delay(0.1)
            }
            .keyframeAnimator(initialValue: EntrancePose(), trigger: hasAppeared && !reduceMotion) { view, pose in
                view
                    .scaleEffect(pose.scale)
                    .rotationEffect(.degrees(pose.rotation))
                    .offset(y: pose.offset)
                    .opacity(pose.opacity)
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    SpringKeyframe(1.12, duration: 0.42, spring: .bouncy)
                    SpringKeyframe(1.0, duration: 0.34, spring: .snappy)
                }
                KeyframeTrack(\.offset) {
                    SpringKeyframe(-14, duration: 0.42, spring: .bouncy)
                    SpringKeyframe(0, duration: 0.38, spring: .snappy)
                }
                KeyframeTrack(\.rotation) {
                    CubicKeyframe(-10, duration: 0.34)
                    CubicKeyframe(4, duration: 0.24)
                    CubicKeyframe(0, duration: 0.26)
                }
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(1, duration: 0.28)
                }
            }
            .shadow(color: .black.opacity(0.28), radius: 22, y: 10)
            .accessibilityHidden(true)
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: 14) {
            // Absent on builds that can't complete it — see `AppleSignIn.isAvailable`.
            // Email then becomes the primary path rather than the alternative, so it takes
            // the prominent treatment the Apple button would have had. A screen whose only
            // action is styled as the secondary one reads as if something is missing.
            if AppleSignIn.isAvailable {
                SignInWithAppleButton(.signIn) { request in
                    session.prepareAppleRequest(request)
                } onCompletion: { result in
                    handleApple(result)
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: 52)
                .clipShape(.capsule)
                .disabled(isWorking)
            }

            emailButton
                .disabled(isWorking)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.red.opacity(0.35), in: .rect(cornerRadius: 12))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            Text("Your map is private. Nothing is shared until you add a friend.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.top, 2)
        }
        .animation(AppTheme.Motion.snappy, value: errorMessage)
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared || reduceMotion ? 0 : 24)
        .animation(reduceMotion ? .easeIn(duration: 0.2) : AppTheme.Motion.bouncy.delay(0.3), value: hasAppeared)
    }

    /// Email, styled by whether it's the alternative or the only way in.
    ///
    /// Written out twice because `buttonStyle` takes a concrete type — there's no
    /// `AnyButtonStyle` to pick between at runtime, and erasing it by hand for two
    /// variants of one button costs more than the duplication does.
    @ViewBuilder
    private var emailButton: some View {
        let label = Text("Continue with email")
            .font(.headline)
            // Glass samples what's behind it, and down here that's the dark end of the
            // gradient. The accent tint would sit at about 2:1 against it.
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 52)

        if AppleSignIn.isAvailable {
            Button { isShowingEmailAuth = true } label: { label }
                .buttonStyle(.glass)
        } else {
            Button { isShowingEmailAuth = true } label: { label }
                .buttonStyle(.glassProminent)
                .tint(AppTheme.accent)
        }
    }

    private func handleApple(_ result: Result<ASAuthorization, any Error>) {
        isWorking = true
        errorMessage = nil
        Task {
            do {
                try await session.completeAppleSignIn(result)
            } catch {
                errorMessage = error.localizedDescription
                haptics.fire(.failure)
            }
            isWorking = false
        }
    }
}

// MARK: - Animation values

/// The idle loop the mark settles into once it has arrived.
private enum DriftPhase: CaseIterable {
    case rest, lifted

    var lift: CGFloat { self == .lifted ? -8 : 0 }
    var tilt: Double { self == .lifted ? 2.5 : -2.5 }
}

/// One keyframe-animated pose. Each property is its own track, so they can run on
/// different curves and different durations.
private struct EntrancePose {
    var scale = 0.72
    var rotation = 0.0
    var offset: CGFloat = 26
    var opacity = 0.0
}

#Preview {
    LandingView()
        .environment(SessionStore())
        .environment(Haptics())
}
