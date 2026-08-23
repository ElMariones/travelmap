import AuthenticationServices
import SwiftUI

/// The first thing anyone sees. Sign in with Apple is the primary path; email is the
/// alternative, and it lives behind a sheet so this screen stays a single decision.
struct LandingView: View {
    @Environment(SessionStore.self) private var session

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
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

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
        .animation(AppTheme.Motion.gentle.delay(0.15), value: hasAppeared)
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
            .phaseAnimator(DriftPhase.allCases, trigger: hasAppeared) { view, phase in
                view
                    .offset(y: phase.lift)
                    .rotationEffect(.degrees(phase.tilt))
            } animation: { _ in
                AppTheme.Motion.gentle.delay(0.1)
            }
            .keyframeAnimator(initialValue: EntrancePose(), trigger: hasAppeared) { view, pose in
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
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: 14) {
            SignInWithAppleButton(.signIn) { request in
                session.prepareAppleRequest(request)
            } onCompletion: { result in
                handleApple(result)
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 52)
            .clipShape(.capsule)
            .disabled(isWorking)

            Button {
                isShowingEmailAuth = true
            } label: {
                Text("Continue with email")
                    .font(.headline)
                    // Glass samples what's behind it, and down here that's the dark end
                    // of the gradient. The accent tint would sit at about 2:1 against it.
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.glass)
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
        .offset(y: hasAppeared ? 0 : 24)
        .animation(AppTheme.Motion.bouncy.delay(0.3), value: hasAppeared)
    }

    private func handleApple(_ result: Result<ASAuthorization, any Error>) {
        isWorking = true
        errorMessage = nil
        Task {
            do {
                try await session.completeAppleSignIn(result)
            } catch {
                errorMessage = error.localizedDescription
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
}
