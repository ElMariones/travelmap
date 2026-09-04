import CoreHaptics
import Foundation
import UIKit

/// The things the app can *mean* through the Taptic Engine.
///
/// Call sites name the moment, never the waveform — which is what lets the patterns be
/// retuned on a device without touching a single view. The list is deliberately closed:
/// every case is an event a user cares about, and events they don't care about get
/// nothing.
///
/// The order below is the rarity gradient, quietest first. `newCountry` and `milestone`
/// are the climaxes and are the only patterns with a continuous tail.
enum HapticEvent {
    /// A chip, a row, a toggle. The lightest thing in the vocabulary.
    case selection
    /// A visit was saved to a country already on the map.
    case visitLogged
    /// A local subdivision filled in for the first time.
    case newRegion
    /// A visit was saved to a country that was gray until now — the map just changed
    /// colour. Signature moment.
    case newCountry
    /// A milestone crossed (a round number of countries, a continent completed). The
    /// biggest pattern in the app, and the rarest.
    case milestone
    /// Signed in, or account created.
    case welcome
    /// A visit was removed.
    case removed
    /// Something failed and the user has to deal with it.
    case failure
}

/// Owns the haptic engine and turns ``HapticEvent`` into waveforms.
///
/// Architecture notes, each of which is load-bearing:
///
/// - **The engine starts lazily**, on the first `fire`, not in `init`. Starting it is not
///   free and doing it during launch competes with the work that puts pixels on screen.
/// - **Capability is checked once.** Call sites fire blindly; on a device with no Taptic
///   Engine — an iPad, the Simulator — every call is a no-op and no `#if` leaks into a view.
/// - **`stoppedHandler` and `resetHandler` drop the engine** so the *next* fire builds a
///   new one. The system stops engines whenever it likes: audio interruptions, thermal
///   pressure, backgrounding. An engine held after that is a silent app.
/// - **There is a user toggle.** Core Haptics obeys no system setting, so an app that
///   plays custom patterns has to provide the off switch itself.
@MainActor
@Observable
final class Haptics {
    /// Off switch, surfaced in Profile. Core Haptics has no system-level setting, so this
    /// is the only way a user can turn the app's haptics off.
    var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            if !isEnabled { stopEngine() }
        }
    }

    private static let enabledKey = "haptics.enabled"

    private let supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    private var engine: CHHapticEngine?

    init() {
        // `object(forKey:)` rather than `bool(forKey:)` so an unset default reads as on
        // instead of as an explicit off.
        isEnabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    // MARK: - Firing

    func fire(_ event: HapticEvent) {
        guard isEnabled else { return }

        // The system presets are a better match than anything custom for the three events
        // that are ordinary iOS interactions rather than moments of this app's own.
        switch event {
        case .selection:
            UISelectionFeedbackGenerator().selectionChanged()
            return
        case .removed:
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.7)
            return
        case .failure:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        default:
            break
        }

        guard supportsHaptics, let pattern = try? pattern(for: event) else {
            // Devices without a Taptic Engine still deserve *something* for a success.
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            return
        }

        startEngineIfNeeded()
        guard let engine else { return }
        do {
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            // A failed play is never worth interrupting the user for; drop the engine so
            // the next event rebuilds one.
            self.engine = nil
        }
    }

    // MARK: - Patterns

    /// Sketches, tuned by ear on a device. The shapes matter more than the numbers: a
    /// routine save is one tap, a new country is a tap with a swell behind it, and a
    /// milestone is three rising taps — audibly and physically the biggest thing here.
    private func pattern(for event: HapticEvent) throws -> CHHapticPattern {
        switch event {
        case .visitLogged:
            return try CHHapticPattern(events: [transient(at: 0, intensity: 0.7, sharpness: 0.6)], parameters: [])

        case .newCountry, .newRegion:
            return try CHHapticPattern(
                events: [
                    transient(at: 0, intensity: 0.9, sharpness: 0.75),
                    continuous(from: 0.04, duration: 0.32, intensity: 0.55, sharpness: 0.25),
                ],
                parameterCurves: [rampDown(from: 0.04, to: 0.36)]
            )

        case .milestone:
            return try CHHapticPattern(
                events: [
                    transient(at: 0.00, intensity: 0.6, sharpness: 0.4),
                    transient(at: 0.12, intensity: 0.8, sharpness: 0.6),
                    transient(at: 0.24, intensity: 1.0, sharpness: 0.85),
                    continuous(from: 0.26, duration: 0.5, intensity: 0.6, sharpness: 0.3),
                ],
                parameterCurves: [rampDown(from: 0.26, to: 0.76)]
            )

        case .welcome:
            return try CHHapticPattern(
                events: [
                    transient(at: 0.00, intensity: 0.5, sharpness: 0.3),
                    transient(at: 0.10, intensity: 0.75, sharpness: 0.5),
                ],
                parameters: []
            )

        case .selection, .removed, .failure:
            // Handled by the presets above; never reached.
            return try CHHapticPattern(events: [transient(at: 0, intensity: 0.5, sharpness: 0.5)], parameters: [])
        }
    }

    private func transient(at time: TimeInterval, intensity: Float, sharpness: Float) -> CHHapticEvent {
        CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                .init(parameterID: .hapticIntensity, value: intensity),
                .init(parameterID: .hapticSharpness, value: sharpness),
            ],
            relativeTime: time
        )
    }

    private func continuous(
        from time: TimeInterval,
        duration: TimeInterval,
        intensity: Float,
        sharpness: Float
    ) -> CHHapticEvent {
        CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                .init(parameterID: .hapticIntensity, value: intensity),
                .init(parameterID: .hapticSharpness, value: sharpness),
            ],
            relativeTime: time,
            duration: duration
        )
    }

    /// Fades a continuous event out instead of cutting it, so the tail reads as a decay
    /// rather than as the engine stopping.
    private func rampDown(from start: TimeInterval, to end: TimeInterval) -> CHHapticParameterCurve {
        CHHapticParameterCurve(
            parameterID: .hapticIntensityControl,
            controlPoints: [
                .init(relativeTime: 0, value: 1.0),
                .init(relativeTime: end - start, value: 0.0),
            ],
            relativeTime: start
        )
    }

    // MARK: - Engine lifecycle

    private func startEngineIfNeeded() {
        guard engine == nil, supportsHaptics else { return }
        do {
            let engine = try CHHapticEngine()
            // The system stops engines freely. Dropping our reference is what makes the
            // next `fire` build a fresh one rather than play into a dead engine.
            engine.stoppedHandler = { [weak self] _ in
                Task { @MainActor in self?.engine = nil }
            }
            engine.resetHandler = { [weak self] in
                Task { @MainActor in self?.engine = nil }
            }
            try engine.start()
            self.engine = engine
        } catch {
            engine = nil
        }
    }

    /// Called when the app leaves the foreground. A running engine in the background
    /// wastes power and can be killed out from under us; lazy start recovers it.
    func stopEngine() {
        engine?.stop()
        engine = nil
    }
}
