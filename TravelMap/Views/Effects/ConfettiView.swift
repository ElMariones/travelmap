import SwiftUI
import UIKit

/// A one-shot confetti burst.
///
/// It emits for a fraction of a second and then stops — a burst, not a fountain. A
/// `CAEmitterLayer` left running keeps allocating particles for as long as it's on
/// screen, which is how celebration effects quietly become a battery bug.
///
/// The layer is driven by a `trigger` value rather than a binding, so it fits the same
/// declarative shape as `.symbolEffect(_:value:)` and `.sensoryFeedback(_:trigger:)`:
/// change the value, get a burst, and no state has to be reset afterwards.
///
/// **Reduce Motion is honoured by refusing to emit at all.** Confetti is decoration, so
/// there is nothing to substitute — the celebration overlay above it carries the meaning
/// on its own.
struct ConfettiView<Trigger: Equatable>: UIViewRepresentable {
    /// Bursts whenever this changes.
    let trigger: Trigger
    var intensity: ConfettiIntensity = .standard

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeUIView(context: Context) -> ConfettiUIView {
        let view = ConfettiUIView()
        view.intensity = intensity
        // `lastTrigger` is deliberately left nil, so the very first `updateUIView` counts
        // as a change and bursts. The overlay that hosts this is created *by* the event
        // being celebrated — it appears with the new trigger value already in place, and
        // no further change ever arrives. Seeding `lastTrigger` here means the confetti
        // never fires at all.
        return view
    }

    func updateUIView(_ view: ConfettiUIView, context: Context) {
        view.intensity = intensity
        guard !reduceMotion else { return }
        guard context.coordinator.lastTrigger != trigger else { return }
        context.coordinator.lastTrigger = trigger
        view.burst()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var lastTrigger: Trigger?
    }
}

/// How much confetti, and for how long. The rarity gradient in one enum: a country
/// filling in gets `standard`, and only a milestone gets `celebration`.
enum ConfettiIntensity {
    case standard
    case celebration

    /// Particles per second across the whole emitter line, not per cell.
    var birthRate: Float { self == .celebration ? 220 : 120 }
    var emitDuration: TimeInterval { self == .celebration ? 0.9 : 0.55 }
    var velocity: CGFloat { self == .celebration ? 560 : 440 }
}

/// The `CAEmitterLayer` host.
final class ConfettiUIView: UIView {
    var intensity: ConfettiIntensity = .standard

    private let emitter = CAEmitterLayer()
    private var stopWorkItem: DispatchWorkItem?
    private var hasPendingBurst = false

    /// Warm, map-adjacent colours: the accent, the two ends of the landing gradient, and
    /// enough spread that a single hue never dominates a burst.
    private static let palette: [UIColor] = [
        UIColor(red: 0.949, green: 0.361, blue: 0.231, alpha: 1),
        UIColor(red: 0.99, green: 0.62, blue: 0.42, alpha: 1),
        UIColor(red: 0.98, green: 0.80, blue: 0.42, alpha: 1),
        UIColor(red: 0.55, green: 0.19, blue: 0.38, alpha: 1),
        UIColor(red: 0.36, green: 0.65, blue: 0.62, alpha: 1),
        UIColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 1),
    ]

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        emitter.emitterShape = .line
        // Not `.additive`: over a light sheet, additive blending washes every particle
        // out to white. Normal blending keeps the colours the palette actually specifies.
        emitter.birthRate = 0
        layer.addSublayer(emitter)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        emitter.frame = bounds
        // Just off the top edge, so particles fall *into* the frame rather than appearing
        // inside it.
        emitter.emitterPosition = CGPoint(x: bounds.midX, y: -12)
        emitter.emitterSize = CGSize(width: bounds.width * 1.1, height: 1)

        if hasPendingBurst { burst() }
    }

    /// Emits for `intensity.emitDuration`, then shuts the emitter off. The particles
    /// already in flight finish their own lifetimes.
    ///
    /// A burst requested before the view has been laid out is held until it has: the
    /// emitter's position and width come from `bounds`, and firing into a zero rect emits
    /// everything from a single point off the top-left corner.
    func burst() {
        guard bounds.width > 0, bounds.height > 0 else {
            hasPendingBurst = true
            return
        }
        hasPendingBurst = false
        stopWorkItem?.cancel()

        // The cells are rebuilt and reassigned rather than mutated in place. Assigning to
        // `emitterCells` hands the layer its own copies, so anything set on the originals
        // afterwards is written to objects the emitter no longer uses — the symptom is a
        // burst that fires, reports no error, and produces nothing at all.
        let shapes: [Shape] = [.rectangle, .rectangle, .circle, .triangle]
        let perCell = intensity.birthRate / Float(Self.palette.count * shapes.count)
        emitter.emitterCells = Self.palette.flatMap { colour in
            shapes.map { cell(colour: colour, shape: $0, birthRate: perCell) }
        }

        emitter.beginTime = CACurrentMediaTime()
        emitter.birthRate = 1

        let stop = DispatchWorkItem { [weak self] in self?.emitter.birthRate = 0 }
        stopWorkItem = stop
        DispatchQueue.main.asyncAfter(deadline: .now() + intensity.emitDuration, execute: stop)
    }

    private enum Shape { case rectangle, circle, triangle }

    private func cell(colour: UIColor, shape: Shape, birthRate: Float) -> CAEmitterCell {
        let cell = CAEmitterCell()
        cell.contents = Self.particleImage(colour: colour, shape: shape).cgImage
        cell.birthRate = birthRate
        cell.velocity = intensity.velocity
        cell.lifetime = 4.5
        cell.lifetimeRange = 1.2
        cell.velocityRange = 160
        cell.emissionLongitude = .pi          // downward
        cell.emissionRange = .pi / 5
        cell.spin = 3.4
        cell.spinRange = 7
        cell.scale = 0.5
        cell.scaleRange = 0.28
        cell.scaleSpeed = -0.04
        cell.yAcceleration = 320               // gravity
        cell.xAcceleration = shape == .circle ? 30 : -30
        cell.alphaSpeed = -0.28                // fade out before they reach the bottom
        return cell
    }

    /// Rendered once per colour-and-shape and cached. Redrawing eighteen bitmaps on every
    /// burst is wasted work at exactly the moment the app can least afford a hitch.
    private static var imageCache: [String: UIImage] = [:]

    private static func particleImage(colour: UIColor, shape: Shape) -> UIImage {
        let key = "\(colour.description)-\(shape)"
        if let cached = imageCache[key] { return cached }

        let size = shape == .rectangle ? CGSize(width: 9, height: 15) : CGSize(width: 11, height: 11)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            colour.setFill()
            let rect = CGRect(origin: .zero, size: size)
            switch shape {
            case .rectangle:
                UIBezierPath(roundedRect: rect, cornerRadius: 2).fill()
            case .circle:
                context.cgContext.fillEllipse(in: rect)
            case .triangle:
                let path = UIBezierPath()
                path.move(to: CGPoint(x: rect.midX, y: 0))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
                path.close()
                path.fill()
            }
        }

        imageCache[key] = image
        return image
    }
}
