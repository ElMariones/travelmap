import MapKit
import SwiftUI

/// The world map itself: one overlay per country, filled with the accent colour when
/// visited and neutral gray when not.
///
/// Wrapping `MKMapView` directly (rather than SwiftUI's `Map`) is what makes the
/// fill-in effect possible — `MKMultiPolygonRenderer` lets a single country recolour
/// in place without rebuilding the other 235.
struct CountryMapView: UIViewRepresentable {
    let mapData: CountryMapData
    let visitedCountryCodes: Set<String>
    let focusedContinent: Continent?
    let onSelectCountry: (Country) -> Void

    /// Keeps the camera clear of the badge and chips above and the tab bar below.
    static let cameraPadding = UIEdgeInsets(top: 96, left: 8, bottom: 56, right: 8)

    func makeCoordinator() -> Coordinator {
        Coordinator(mapData: mapData, onSelectCountry: onSelectCountry)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = LayoutReportingMapView()
        mapView.delegate = context.coordinator

        // A quiet base map: the country overlays carry all the meaning, so terrain,
        // points of interest, and 3D would only compete with them.
        let configuration = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        configuration.pointOfInterestFilter = .excludingAll
        configuration.showsTraffic = false
        mapView.preferredConfiguration = configuration

        mapView.isPitchEnabled = false
        mapView.isRotateEnabled = false
        mapView.showsCompass = false
        mapView.showsScale = false

        mapView.addOverlays(mapData.shapes.map(\.multiPolygon), level: .aboveRoads)

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap))
        mapView.addGestureRecognizer(tap)
        context.coordinator.mapView = mapView

        // Framing the world needs the view's real size, which it doesn't have yet here.
        mapView.onFirstLayout = { [weak coordinator = context.coordinator] in
            coordinator?.markReadyForCamera()
        }

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.onSelectCountry = onSelectCountry
        context.coordinator.applyVisitedCodes(visitedCountryCodes)
        context.coordinator.focus(on: focusedContinent)
    }

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate {
        weak var mapView: MKMapView?
        var onSelectCountry: (Country) -> Void

        private let mapData: CountryMapData
        private var renderers: [String: MKMultiPolygonRenderer] = [:]
        private var visitedCountryCodes: Set<String> = []
        private var requestedContinent: Continent?
        private var appliedContinent: Continent??
        private var isReadyForCamera = false
        /// Whether the camera has already settled onto the user's own countries. Only ever
        /// happens once, and only while the All chip is selected.
        private var hasFramedVisited = false

        init(mapData: CountryMapData, onSelectCountry: @escaping (Country) -> Void) {
            self.mapData = mapData
            self.onSelectCountry = onSelectCountry
        }

        // MARK: - Rendering

        func mapView(_ mapView: MKMapView, rendererFor overlay: any MKOverlay) -> MKOverlayRenderer {
            guard let multiPolygon = overlay as? MKMultiPolygon, let code = multiPolygon.title else {
                return MKOverlayRenderer(overlay: overlay)
            }

            let renderer = MKMultiPolygonRenderer(multiPolygon: multiPolygon)
            renderer.fillColor = fillColor(visited: visitedCountryCodes.contains(code))
            renderer.strokeColor = UIColor.label.withAlphaComponent(AppTheme.borderOpacity)
            renderer.lineWidth = AppTheme.borderWidth
            renderers[code] = renderer
            return renderer
        }

        private func fillColor(visited: Bool) -> UIColor {
            let base = visited ? UIColor(AppTheme.accent) : UIColor(AppTheme.unvisitedLand)
            return base.withAlphaComponent(AppTheme.landOpacity)
        }

        /// Recolours only the countries whose state actually changed, so saving a visit
        /// repaints one polygon instead of the whole map.
        func applyVisitedCodes(_ codes: Set<String>) {
            guard codes != visitedCountryCodes else { return }
            let changed = codes.symmetricDifference(visitedCountryCodes)
            visitedCountryCodes = codes

            for code in changed {
                guard let renderer = renderers[code] else { continue }
                renderer.fillColor = fillColor(visited: codes.contains(code))
                renderer.setNeedsDisplay()
            }

            frameVisitedIfNeeded()
        }

        // MARK: - Camera

        /// Called once the map view has a real size, which is when framing can be trusted.
        func markReadyForCamera() {
            isReadyForCamera = true
            applyCamera(animated: false)
            frameVisitedIfNeeded()
        }

        /// Settles the camera onto the countries the user has actually been to, once, as
        /// soon as they arrive.
        ///
        /// Visits load a moment after the map does, so the first frame is necessarily the
        /// default world view. Opening the app and being shown the middle of the Atlantic
        /// while your own map sits off-screen is a poor greeting; this pans to your
        /// countries the moment there are any to pan to, and then leaves the camera alone.
        private func frameVisitedIfNeeded() {
            guard isReadyForCamera, !hasFramedVisited, requestedContinent == nil,
                  let mapView, let rect = visitedBoundingRect()
            else { return }
            hasFramedVisited = true
            mapView.setVisibleMapRect(rect, edgePadding: CountryMapView.cameraPadding, animated: true)
        }

        /// The projected rect covering every visited country, with room to breathe.
        ///
        /// Returns `nil` rather than a world-sized rect when the spread is close to global:
        /// at that point the default framing is already the answer, and a computed rect
        /// would only nudge the camera for no visible gain. Countries either side of the
        /// antimeridian are what produce those degenerate rects — one visit to Fiji and one
        /// to Chile spans the planet the long way round.
        private func visitedBoundingRect() -> MKMapRect? {
            let visited = mapData.shapes.filter { visitedCountryCodes.contains($0.country.code) }
            guard !visited.isEmpty else { return nil }

            let rect = visited.dropFirst().reduce(visited[0].multiPolygon.boundingMapRect) {
                $0.union($1.multiPolygon.boundingMapRect)
            }
            guard rect.width < MKMapRect.world.width * 0.6 else { return nil }

            // A single country would otherwise fill the screen edge to edge, with no sense
            // of where in the world it is.
            let padding = max(rect.width, rect.height) * 0.9
            return rect.insetBy(dx: -padding, dy: -padding)
        }

        func focus(on continent: Continent?) {
            requestedContinent = continent
            applyCamera(animated: true)
        }

        private func applyCamera(animated: Bool) {
            guard isReadyForCamera, let mapView else { return }
            // `appliedContinent` is doubly optional on purpose: the outer nil means
            // "never applied", the inner nil means "the All chip".
            guard appliedContinent == nil || appliedContinent! != requestedContinent else { return }
            appliedContinent = .some(requestedContinent)

            // MapKit hard-clamps a flat map's camera at roughly 38,500 km out, which on a
            // portrait phone is about 95 degrees of longitude — the whole globe genuinely
            // doesn't fit. Asking for `.world` gets MapKit's widest possible framing.
            let rect = requestedContinent.map { MKMapRect(region: $0.mapRegion) } ?? .world
            mapView.setVisibleMapRect(rect, edgePadding: CountryMapView.cameraPadding, animated: animated)
        }

        // MARK: - Selection

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let mapView else { return }
            let point = gesture.location(in: mapView)
            let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
            guard let country = mapData.country(at: coordinate) else { return }

            UISelectionFeedbackGenerator().selectionChanged()
            onSelectCountry(country)
        }
    }
}

/// An `MKMapView` that says when it first has a usable size, so the initial camera can
/// be framed against real bounds instead of the zero rect it's created with.
private final class LayoutReportingMapView: MKMapView {
    var onFirstLayout: (() -> Void)?

    private var hasReportedLayout = false

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !hasReportedLayout, bounds.width > 0, bounds.height > 0 else { return }
        hasReportedLayout = true
        onFirstLayout?()
    }
}
