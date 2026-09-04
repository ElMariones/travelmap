import MapKit
import SwiftUI

/// A country's local subdivisions. Only that country's overlays are installed, keeping
/// interaction quick even though the bundled reference set contains 4,477 regions.
struct RegionMapView: UIViewRepresentable {
    let mapData: RegionMapData
    let countryCode: String
    let visitedRegionCodes: Set<String>
    let onSelectRegion: (Region) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(mapData: mapData, countryCode: countryCode, onSelectRegion: onSelectRegion)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = RegionLayoutMapView()
        mapView.delegate = context.coordinator
        let configuration = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        configuration.pointOfInterestFilter = .excludingAll
        mapView.preferredConfiguration = configuration
        mapView.isPitchEnabled = false
        mapView.isRotateEnabled = false
        mapView.showsCompass = false
        mapView.showsScale = false
        mapView.addOverlays(mapData.shapes(in: countryCode).map(\.multiPolygon), level: .aboveRoads)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap))
        mapView.addGestureRecognizer(tap)
        context.coordinator.mapView = mapView
        mapView.onFirstLayout = { [weak coordinator = context.coordinator] in coordinator?.frameCountry() }
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.onSelectRegion = onSelectRegion
        context.coordinator.applyVisitedCodes(visitedRegionCodes)
    }

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate {
        weak var mapView: MKMapView?
        var onSelectRegion: (Region) -> Void
        private let mapData: RegionMapData
        private let countryCode: String
        private var visitedCodes: Set<String> = []
        private var renderers: [String: MKMultiPolygonRenderer] = [:]

        init(mapData: RegionMapData, countryCode: String, onSelectRegion: @escaping (Region) -> Void) {
            self.mapData = mapData
            self.countryCode = countryCode
            self.onSelectRegion = onSelectRegion
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: any MKOverlay) -> MKOverlayRenderer {
            guard let multi = overlay as? MKMultiPolygon, let code = multi.title else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let renderer = MKMultiPolygonRenderer(multiPolygon: multi)
            renderer.fillColor = fillColor(visited: visitedCodes.contains(code))
            renderer.strokeColor = UIColor.label.withAlphaComponent(0.38)
            renderer.lineWidth = 0.75
            renderers[code] = renderer
            return renderer
        }

        func applyVisitedCodes(_ codes: Set<String>) {
            guard codes != visitedCodes else { return }
            let changed = codes.symmetricDifference(visitedCodes)
            visitedCodes = codes
            for code in changed {
                guard let renderer = renderers[code] else { continue }
                renderer.fillColor = fillColor(visited: codes.contains(code))
                renderer.setNeedsDisplay()
            }
        }

        private func fillColor(visited: Bool) -> UIColor {
            let color = visited ? UIColor(AppTheme.accent) : UIColor(AppTheme.unvisitedLand)
            return color.withAlphaComponent(visited ? 0.72 : 0.48)
        }

        func frameCountry() {
            guard let mapView else { return }
            let rect = mapData.boundingRect(for: countryCode)
            guard !rect.isNull, !rect.isEmpty else { return }
            mapView.setVisibleMapRect(
                rect,
                edgePadding: UIEdgeInsets(top: 18, left: 18, bottom: 18, right: 18),
                animated: false
            )
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let mapView else { return }
            let point = gesture.location(in: mapView)
            let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
            guard let region = mapData.region(at: coordinate, countryCode: countryCode) else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            onSelectRegion(region)
        }
    }
}

private final class RegionLayoutMapView: MKMapView {
    var onFirstLayout: (() -> Void)?
    private var didReportLayout = false

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !didReportLayout, bounds.width > 0, bounds.height > 0 else { return }
        didReportLayout = true
        onFirstLayout?()
    }
}
