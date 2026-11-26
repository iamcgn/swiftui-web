// Directions, the user's location annotation, tile overlays and distance formatting for UIKit map
// code (OldOS's Maps app). Directions come from Apple's servers, which a page can't reach, so a
// request fails as Apple's does when no route is found (`MKError.directionsNotFound`), after the
// call returns, and an app's no-route path runs. A tile overlay keeps its URL template and
// answers the URL of each tile, as Apple's does; the web map doesn't paint overlays yet. The
// distance formatter writes distances in the locale's units, as Maps' search results do.
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif
import SwiftUI
import CoreLocation
#if canImport(FoundationNetworking) && !os(WASI)
import FoundationNetworking   // Linux keeps URLSession here
#endif

// MARK: - The user's location

/// The annotation for the device's own location; a map view's `userLocation`.
open class MKUserLocation: NSObject, MKAnnotation, @unchecked Sendable {
    /// Where the device is; nil until a location arrives.
    open internal(set) var location: CLLocation?
    open internal(set) var heading: CLHeading?
    open internal(set) var isUpdating = false
    open var title: String? = "My Location"
    open var subtitle: String?
    open var coordinate: CLLocationCoordinate2D { location?.coordinate ?? kCLLocationCoordinate2DInvalid }
    public override init() { super.init() }
}

// MARK: - Tile overlays

/// The address of one map tile: its column, row and zoom level, and the screen scale.
public struct MKTileOverlayPath: Hashable, Sendable {
    public var x: Int
    public var y: Int
    public var z: Int
    public var contentScaleFactor: CGFloat
    public init(x: Int = 0, y: Int = 0, z: Int = 0, contentScaleFactor: CGFloat = 1) {
        self.x = x
        self.y = y
        self.z = z
        self.contentScaleFactor = contentScaleFactor
    }
}

/// An overlay of map tiles from a server, named by a URL template with `{x}`, `{y}`, `{z}` and
/// `{scale}` in it.
open class MKTileOverlay: NSObject, MKOverlay, @unchecked Sendable {
    public let urlTemplate: String?
    open var tileSize = CGSize(width: 256, height: 256)
    open var isGeometryFlipped = false
    open var minimumZ = 0
    open var maximumZ = 21
    open var canReplaceMapContent = false
    open var coordinate: CLLocationCoordinate2D { MKMapPoint(x: MKMapRect.world.midX, y: MKMapRect.world.midY).coordinate }
    open var boundingMapRect: MKMapRect { .world }

    public init(urlTemplate URLTemplate: String?) {
        urlTemplate = URLTemplate
        super.init()
    }

    /// The tile's URL: the template with the path's values put in.
    open func url(forTilePath path: MKTileOverlayPath) -> URL {
        var text = ""
        var name: String?
        for character in urlTemplate ?? "" {
            if character == "{" {
                name = ""
            } else if character == "}", let key = name {
                switch key {
                case "x": text += String(path.x)
                case "y": text += String(isGeometryFlipped ? (1 << path.z) - 1 - path.y : path.y)
                case "z": text += String(path.z)
                case "scale": text += String(Int(path.contentScaleFactor))
                default: text += "{" + key + "}"
                }
                name = nil
            } else if name != nil {
                name?.append(character)
            } else {
                text.append(character)
            }
        }
        if let open = name { text += "{" + open }
        return URL(string: text) ?? URL(fileURLWithPath: "/")
    }

    /// Loads the tile's data from its URL.
    open func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        let url = url(forTilePath: path)
        let handler = _Carried(result)
        URLSession.shared.dataTask(with: url) { data, _, error in handler.value(data, error) }.resume()
    }
}

/// Draws a tile overlay. The web map doesn't paint overlays yet; the renderer keeps the overlay.
open class MKTileOverlayRenderer: MKOverlayRenderer {
    public convenience init(tileOverlay overlay: MKTileOverlay) { self.init(overlay: overlay) }
    open func reloadData() {}
}

// MARK: - Directions

/// The ways a route can be travelled.
public struct MKDirectionsTransportType: OptionSet, Hashable, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let automobile = MKDirectionsTransportType(rawValue: 1 << 0)
    public static let walking = MKDirectionsTransportType(rawValue: 1 << 1)
    public static let transit = MKDirectionsTransportType(rawValue: 1 << 2)
    public static let cycling = MKDirectionsTransportType(rawValue: 1 << 3)
    public static let any = MKDirectionsTransportType(rawValue: 0x0FFF_FFFF)
}

/// A route between two places: its line, length, time and steps.
open class MKRoute: NSObject, @unchecked Sendable {
    /// One instruction along a route.
    open class Step: NSObject, @unchecked Sendable {
        open internal(set) var instructions = ""
        open internal(set) var notice: String?
        open internal(set) var polyline = MKPolyline(points: [])
        open internal(set) var distance: CLLocationDistance = 0
        open internal(set) var transportType: MKDirectionsTransportType = .automobile
    }

    open internal(set) var name = ""
    open internal(set) var advisoryNotices: [String] = []
    open internal(set) var distance: CLLocationDistance = 0
    open internal(set) var expectedTravelTime: TimeInterval = 0
    open internal(set) var transportType: MKDirectionsTransportType = .automobile
    open internal(set) var polyline = MKPolyline(points: [])
    open internal(set) var steps: [Step] = []
    open internal(set) var hasTolls = false
    open internal(set) var hasHighways = false
}

/// Finds routes between places. Routes come from Apple's servers, which a page can't reach, so
/// every request fails with `MKError.directionsNotFound`.
open class MKDirections: NSObject, @unchecked Sendable {
    /// Where a route starts and ends, and how it is travelled.
    open class Request: NSObject, @unchecked Sendable {
        open var source: MKMapItem?
        open var destination: MKMapItem?
        open var transportType: MKDirectionsTransportType = .any
        open var requestsAlternateRoutes = false
        open var departureDate: Date?
        open var arrivalDate: Date?
        open var tollPreference: RoutePreference = .any
        open var highwayPreference: RoutePreference = .any
        public override init() { super.init() }
        public init(contentsOf url: URL) { super.init() }
        open class func isDirectionsRequest(_ url: URL) -> Bool { false }
    }

    /// Whether a route should use or avoid tolls or highways.
    public enum RoutePreference: Int, Sendable { case any = 0, avoid }

    /// The routes found for a request.
    open class Response: NSObject, @unchecked Sendable {
        public let source: MKMapItem
        public let destination: MKMapItem
        public let routes: [MKRoute]
        init(source: MKMapItem, destination: MKMapItem, routes: [MKRoute]) {
            self.source = source
            self.destination = destination
            self.routes = routes
        }
    }

    /// The expected travel time for a request.
    open class ETAResponse: NSObject, @unchecked Sendable {
        public let source: MKMapItem
        public let destination: MKMapItem
        public let expectedTravelTime: TimeInterval
        public let distance: CLLocationDistance
        public let expectedArrivalDate: Date
        public let expectedDepartureDate: Date
        public let transportType: MKDirectionsTransportType
        init(source: MKMapItem, destination: MKMapItem) {
            self.source = source
            self.destination = destination
            expectedTravelTime = 0
            distance = 0
            expectedArrivalDate = Date()
            expectedDepartureDate = Date()
            transportType = .automobile
        }
    }

    public typealias DirectionsHandler = (Response?, Error?) -> Void
    public typealias ETAHandler = (ETAResponse?, Error?) -> Void

    public let request: Request
    open private(set) var isCalculating = false

    public init(request: Request) {
        self.request = request
        super.init()
    }

    private static var noRoute: MKError {
        MKError(.directionsNotFound, userInfo: [NSLocalizedDescriptionKey: "Directions Not Available"])
    }

    /// Calls the handler with the routes, after the call returns: no route, as no server answers.
    open func calculate(completionHandler: @escaping DirectionsHandler) {
        isCalculating = true
        let carried = _Carried((self, completionHandler))
        Task { @MainActor in
            carried.value.0.isCalculating = false
            carried.value.1(nil, MKDirections.noRoute)
        }
    }

    open func calculate() async throws -> Response { throw MKDirections.noRoute }

    open func calculateETA(completionHandler: @escaping ETAHandler) {
        isCalculating = true
        let carried = _Carried((self, completionHandler))
        Task { @MainActor in
            carried.value.0.isCalculating = false
            carried.value.1(nil, MKDirections.noRoute)
        }
    }

    open func calculateETA() async throws -> ETAResponse { throw MKDirections.noRoute }

    open func cancel() { isCalculating = false }
}

// MARK: - Distance formatting

/// Writes a distance in the locale's units ("500 ft" and "1.2 mi" in the US, "500 m" and "1.2 km"
/// elsewhere), as Maps' results do.
open class MKDistanceFormatter: Formatter, @unchecked Sendable {
    public enum Units: UInt, Sendable { case `default` = 0, metric, imperial, imperialWithYards }
    public enum DistanceUnitStyle: UInt, Sendable { case `default` = 0, abbreviated, full }

    open var locale = Locale.current
    open var units: Units = .default
    open var unitStyle: DistanceUnitStyle = .default

    /// The locale's region code, read from its identifier ("en_US" → "US").
    private var region: String {
        let parts = locale.identifier.split { $0 == "_" || $0 == "-" }.dropFirst()
        return parts.first { $0.count == 2 && $0.allSatisfy(\.isUppercase) }.map(String.init) ?? ""
    }

    private var usesImperial: Bool {
        switch units {
        case .metric: return false
        case .imperial, .imperialWithYards: return true
        case .default: return ["US", "LR", "MM", "GB"].contains(region)
        }
    }

    /// The distance, in meters, written in the formatter's units.
    open func string(fromDistance distance: CLLocationDistance) -> String {
        let full = unitStyle == .full
        func write(_ value: Double, _ short: String, _ one: String, _ many: String) -> String {
            let rounded = value < 10 ? (value * 10).rounded() / 10 : value.rounded()
            let number = rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
            return number + " " + (full ? (rounded == 1 ? one : many) : short)
        }
        let meters = max(distance, 0)
        if usesImperial {
            let miles = meters / 1609.344
            if miles >= 0.1 { return write(miles, "mi", "mile", "miles") }
            if units == .imperialWithYards || (units == .default && region == "GB") {
                return write((meters / 0.9144 / 10).rounded() * 10, "yd", "yard", "yards")
            }
            return write((meters / 0.3048 / 10).rounded() * 10, "ft", "foot", "feet")
        }
        if meters >= 1000 { return write(meters / 1000, "km", "kilometer", "kilometers") }
        return write((meters / 10).rounded() * 10, "m", "meter", "meters")
    }

    /// The distance, in meters, that a string the formatter writes stands for.
    open func distance(from distance: String) -> CLLocationDistance {
        let parts = distance.split(separator: " ")
        guard parts.count == 2, let value = Double(parts[0]) else { return 0 }
        switch parts[1] {
        case "mi", "mile", "miles": return value * 1609.344
        case "yd", "yard", "yards": return value * 0.9144
        case "ft", "foot", "feet": return value * 0.3048
        case "km", "kilometer", "kilometers": return value * 1000
        default: return value
        }
    }

    open override func string(for obj: Any?) -> String? {
        guard let value = obj as? Double ?? (obj as? Int).map(Double.init) else { return nil }
        return string(fromDistance: value)
    }
}
