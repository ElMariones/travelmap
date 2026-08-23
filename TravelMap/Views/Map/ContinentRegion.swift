import MapKit

extension Continent {
    /// Where the map flies to when this continent's chip is tapped.
    ///
    /// These are hand-framed rather than computed from the country polygons: Asia and
    /// Oceania both straddle the antimeridian, and the bounding box of their members
    /// comes out spanning the entire globe.
    var mapRegion: MKCoordinateRegion {
        switch self {
        case .europe:
            return region(latitude: 54, longitude: 15, latitudeSpan: 42, longitudeSpan: 62)
        case .asia:
            return region(latitude: 30, longitude: 92, latitudeSpan: 78, longitudeSpan: 122)
        case .africa:
            return region(latitude: 2, longitude: 19, latitudeSpan: 82, longitudeSpan: 86)
        case .northAmerica:
            return region(latitude: 42, longitude: -98, latitudeSpan: 84, longitudeSpan: 128)
        case .southAmerica:
            return region(latitude: -22, longitude: -61, latitudeSpan: 78, longitudeSpan: 68)
        case .oceania:
            return region(latitude: -22, longitude: 148, latitudeSpan: 74, longitudeSpan: 96)
        }
    }


    private func region(
        latitude: CLLocationDegrees,
        longitude: CLLocationDegrees,
        latitudeSpan: CLLocationDegrees,
        longitudeSpan: CLLocationDegrees
    ) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            span: MKCoordinateSpan(latitudeDelta: latitudeSpan, longitudeDelta: longitudeSpan)
        )
    }
}

extension MKMapRect {
    /// The projected rect covering a coordinate region, corners included.
    init(region: MKCoordinateRegion) {
        let topLeft = MKMapPoint(CLLocationCoordinate2D(
            latitude: min(region.center.latitude + region.span.latitudeDelta / 2, 85),
            longitude: max(region.center.longitude - region.span.longitudeDelta / 2, -179.9)
        ))
        let bottomRight = MKMapPoint(CLLocationCoordinate2D(
            latitude: max(region.center.latitude - region.span.latitudeDelta / 2, -85),
            longitude: min(region.center.longitude + region.span.longitudeDelta / 2, 179.9)
        ))
        self.init(
            x: min(topLeft.x, bottomRight.x),
            y: min(topLeft.y, bottomRight.y),
            width: abs(bottomRight.x - topLeft.x),
            height: abs(bottomRight.y - topLeft.y)
        )
    }
}
