import SwiftUI

/// The world, small enough for a widget to draw.
///
/// The app's map is MapKit; a widget extension cannot use MapKit at all. So this is a
/// second, far coarser copy of the same borders — 236 countries, about 5,000 points,
/// 57 KB — projected once at build time by `scripts/build-widgetmap.mjs` and drawn here
/// as plain SwiftUI `Path`s.
///
/// Coordinates arrive as integers on a 0…10000 grid rather than as latitude and longitude:
/// the projection is already done, so drawing is a multiply and an add per point with no
/// trigonometry anywhere.
struct WidgetWorldMap: Decodable, Sendable {
    struct Country: Decodable, Sendable {
        /// ISO 3166-1 alpha-2.
        let c: String
        /// Two-letter continent key — `EU`, `AS`, `NA`… Empty if unknown.
        let k: String
        /// Rings, each flattened to `[x, y, x, y, …]`.
        let r: [[Double]]
    }

    /// Width of the coordinate space. Height is stored alongside it rather than derived,
    /// because y is already scaled proportionally to x — see the build script.
    let grid: Double
    let height: Double
    let countries: [Country]

    /// Loaded once per process. A widget refresh is short and may run several times in a
    /// row; re-parsing 57 KB of JSON for each of them is avoidable work in a process with
    /// a 40 MB ceiling.
    static let shared: WidgetWorldMap? = {
        guard let url = Bundle.main.url(forResource: "worldmap", withExtension: "json", subdirectory: "WidgetMapData")
            ?? Bundle.main.url(forResource: "worldmap", withExtension: "json"),
            let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(WidgetWorldMap.self, from: data)
    }()

    /// Continent keys, in the same order the app lists them.
    static let continentKeys: [String: String] = [
        "Europe": "EU", "Asia": "AS", "Africa": "AF",
        "North America": "NA", "South America": "SA", "Oceania": "OC",
    ]
}

/// Draws the world with the visited countries filled in.
///
/// Two paths, not 236: every unvisited country is appended into one `Path` and every
/// visited one into another. SwiftUI then has two shapes to rasterize instead of a few
/// hundred, which is the difference between a widget that renders instantly and one the
/// system gives up waiting for.
struct WidgetWorldMapView: View {
    let visitedCodes: Set<String>
    /// Draw only this continent, by `Continent.rawValue`. `nil` draws the world.
    var continent: String?
    var visitedColor: Color
    var landColor: Color

    var body: some View {
        GeometryReader { proxy in
            let paths = WidgetWorldMap.shared.map { build($0, in: proxy.size) }

            ZStack {
                if let paths {
                    paths.unvisited.fill(landColor)
                    paths.visited.fill(visitedColor)
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// Builds the two paths, fitted to `size`.
    ///
    /// The fit is computed from the bounding box of whatever is actually being drawn, so
    /// scoping the widget to Europe frames Europe instead of drawing a small Europe in a
    /// world-shaped hole. Uniform scale on both axes, always — an independent x and y fit
    /// would stretch every country to whatever shape the widget happens to be.
    private func build(_ map: WidgetWorldMap, in size: CGSize) -> (visited: Path, unvisited: Path) {
        let key = continent.flatMap { WidgetWorldMap.continentKeys[$0] }
        let included = key.map { key in map.countries.filter { $0.k == key } } ?? map.countries
        guard !included.isEmpty, size.width > 0, size.height > 0 else { return (Path(), Path()) }

        let box = boundingBox(of: included, map: map, isScoped: key != nil)
        let scale = min(size.width / box.width, size.height / box.height)
        let offsetX = (size.width - box.width * scale) / 2 - box.minX * scale
        let offsetY = (size.height - box.height * scale) / 2 - box.minY * scale

        var visited = Path()
        var unvisited = Path()

        for country in included {
            let isVisited = visitedCodes.contains(country.c)

            for ring in country.r where ring.count >= 6 {
                var path = Path()
                path.move(to: CGPoint(x: ring[0] * scale + offsetX, y: ring[1] * scale + offsetY))
                for index in stride(from: 2, to: ring.count - 1, by: 2) {
                    path.addLine(to: CGPoint(x: ring[index] * scale + offsetX, y: ring[index + 1] * scale + offsetY))
                }
                path.closeSubpath()

                if isVisited {
                    visited.addPath(path)
                } else {
                    unvisited.addPath(path)
                }
            }
        }

        return (visited, unvisited)
    }

    private func boundingBox(of countries: [WidgetWorldMap.Country], map: WidgetWorldMap, isScoped: Bool) -> CGRect {
        let world = CGRect(x: 0, y: 0, width: map.grid, height: map.height)

        // The whole world uses the full coordinate space, so the framing never shifts as
        // countries are logged and every widget on the home screen lines up with every other.
        guard isScoped else { return world }

        var minX = Double.greatestFiniteMagnitude, minY = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude, maxY = -Double.greatestFiniteMagnitude
        for country in countries {
            for ring in country.r {
                for index in stride(from: 0, to: ring.count - 1, by: 2) {
                    minX = min(minX, ring[index]); maxX = max(maxX, ring[index])
                    minY = min(minY, ring[index + 1]); maxY = max(maxY, ring[index + 1])
                }
            }
        }
        guard maxX > minX, maxY > minY else { return world }

        // A little air, so the outermost coastline isn't flush against the widget's edge.
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            .insetBy(dx: -(maxX - minX) * 0.04, dy: -(maxY - minY) * 0.04)
    }
}
