import Foundation
import MapKit

/// One country's renderable geometry, paired with its reference-set entry.
struct CountryShape {
    let country: Country
    let multiPolygon: MKMultiPolygon
}

/// The decoded contents of `countries.geojson`: the reference country list plus the
/// polygons the world map draws.
///
/// MapKit's overlay types aren't `Sendable`, but every shape here is built once during
/// decoding and never mutated afterwards, so handing the finished set from the decoding
/// task to the main actor is safe.
final class CountryMapData: @unchecked Sendable {
    let shapes: [CountryShape]
    let countries: [Country]
    private let shapesByCode: [String: CountryShape]

    init(shapes: [CountryShape]) {
        self.shapes = shapes
        self.countries = shapes.map(\.country).sorted { $0.name < $1.name }
        self.shapesByCode = Dictionary(uniqueKeysWithValues: shapes.map { ($0.country.code, $0) })
    }

    func shape(for code: String) -> CountryShape? { shapesByCode[code] }

    /// Total countries per continent — the denominator for every percentage.
    func countryCount(in continent: Continent) -> Int {
        countries.filter { $0.continent == continent }.count
    }

    /// The country whose borders contain `coordinate`, if any.
    ///
    /// Bounding boxes narrow 236 countries down to a handful before any ray casting runs,
    /// which keeps a map tap comfortably inside one frame.
    func country(at coordinate: CLLocationCoordinate2D) -> Country? {
        let point = MKMapPoint(coordinate)
        var best: (country: Country, area: Double)?

        for shape in shapes where shape.multiPolygon.boundingMapRect.contains(point) {
            guard shape.multiPolygon.polygons.contains(where: { $0.contains(point) }) else { continue }
            // Overlapping bounding boxes are common (France's overseas departments sit
            // inside larger neighbours' boxes); prefer the tightest actual match.
            let area = shape.multiPolygon.boundingMapRect.size.width * shape.multiPolygon.boundingMapRect.size.height
            if best == nil || area < best!.area {
                best = (shape.country, area)
            }
        }

        return best?.country
    }

    /// The smallest map rect containing every country in `continent`.
    func boundingRect(for continent: Continent) -> MKMapRect {
        shapes
            .filter { $0.country.continent == continent }
            .reduce(MKMapRect.null) { $0.union($1.multiPolygon.boundingMapRect) }
    }
}

/// Loads and decodes the bundled Natural Earth GeoJSON.
enum GeoDataService {
    /// Folder reference inside the app bundle holding the Natural Earth assets.
    static let mapDataDirectory = "MapData"

    enum LoadError: LocalizedError {
        case missingResource(String)

        var errorDescription: String? {
            switch self {
            case .missingResource(let name):
                return "Couldn't find \(name) in the app bundle."
            }
        }
    }

    /// Properties written by `scripts/build-mapdata.mjs`.
    private struct CountryProperties: Decodable {
        let code: String
        let name: String
        let continent: Continent
    }

    /// Decodes `countries.geojson`. Runs off the main actor — it's a few hundred
    /// kilobytes of JSON and several thousand polygon vertices.
    static func loadCountries() async throws -> CountryMapData {
        try await Task.detached(priority: .userInitiated) {
            // MapData is bundled as a folder reference, so the subdirectory is required —
            // the flat lookup doesn't recurse and would silently come back nil.
            guard let url = Bundle.main.url(
                forResource: "countries",
                withExtension: "geojson",
                subdirectory: Self.mapDataDirectory
            ) else {
                throw LoadError.missingResource("countries.geojson")
            }

            let objects = try MKGeoJSONDecoder().decode(Data(contentsOf: url))
            let decoder = JSONDecoder()
            var shapes: [CountryShape] = []

            for case let feature as MKGeoJSONFeature in objects {
                guard let propertyData = feature.properties,
                      let properties = try? decoder.decode(CountryProperties.self, from: propertyData)
                else { continue }

                let polygons = feature.geometry.flatMap { geometry -> [MKPolygon] in
                    switch geometry {
                    case let multi as MKMultiPolygon: return multi.polygons
                    case let polygon as MKPolygon: return [polygon]
                    default: return []
                    }
                }
                guard !polygons.isEmpty else { continue }

                let country = Country(code: properties.code, name: properties.name, continent: properties.continent)
                let multiPolygon = MKMultiPolygon(polygons)
                // The renderer only sees the overlay, so the ISO code rides along on it.
                multiPolygon.title = country.code
                shapes.append(CountryShape(country: country, multiPolygon: multiPolygon))
            }

            return CountryMapData(shapes: shapes)
        }.value
    }
}

extension MKPolygon {
    /// Ray-casting point-in-polygon test in projected map space, honouring interior holes.
    func contains(_ point: MKMapPoint) -> Bool {
        guard boundingMapRect.contains(point) else { return false }
        guard crossesBoundaryOddNumberOfTimes(point) else { return false }

        for hole in interiorPolygons ?? [] where hole.contains(point) {
            return false
        }
        return true
    }

    private func crossesBoundaryOddNumberOfTimes(_ point: MKMapPoint) -> Bool {
        let vertices = UnsafeBufferPointer(start: points(), count: pointCount)
        guard vertices.count > 2 else { return false }

        var isInside = false
        var j = vertices.count - 1

        for i in vertices.indices {
            let a = vertices[i]
            let b = vertices[j]
            if (a.y > point.y) != (b.y > point.y) {
                let crossingX = (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x
                if point.x < crossingX { isInside.toggle() }
            }
            j = i
        }

        return isInside
    }
}
