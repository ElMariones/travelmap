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
        }

        // MARK: - Camera

        /// Called once the map view has a real size, which is when framing can be trusted.
        func markReadyForCamera() {
            isReadyForCamera = true
            applyCamera(animated: false)
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
