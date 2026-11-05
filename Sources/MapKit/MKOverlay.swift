// Map overlays for UIKit map code: the flat map projection (`MKMapPoint`, `MKMapRect`), the
// overlay shapes apps add (circles, polylines, polygons), their renderers and the user tracking
// mode. The map view keeps the overlays it is given and asks its delegate for their renderers;
// it does not paint them yet, like its annotations.
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif
import SwiftUI

// MARK: - Projection

/// A point on the flat, two-dimensional map projection (Web Mercator, 2^28 points wide).
public struct MKMapPoint: Hashable, Sendable {
    public var x: Double
    public var y: Double
    public init() { x = 0; y = 0 }
    public init(x: Double, y: Double) { self.x = x; self.y = y }

    public init(_ coordinate: CLLocationCoordinate2D) {
        let width = MKMapSize.world.width
        let latitude = max(-85.05112878, min(85.05112878, coordinate.latitude)) * .pi / 180
        x = (coordinate.longitude + 180) / 360 * width
        y = (1 - log(tan(latitude) + 1 / cos(latitude)) / .pi) / 2 * width
    }

    public var coordinate: CLLocationCoordinate2D {
        let width = MKMapSize.world.width
        let n = Double.pi * (1 - 2 * y / width)
        let latitude = atan(0.5 * (exp(n) - exp(-n))) * 180 / .pi
        return CLLocationCoordinate2D(latitude: latitude, longitude: x / width * 360 - 180)
    }

    /// The distance in meters to another point, along the earth's surface.
    public func distance(to other: MKMapPoint) -> Double {
        let a = coordinate, b = other.coordinate
        let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
        let dLat = lat2 - lat1, dLon = (b.longitude - a.longitude) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * 6_371_000 * asin(min(1, h.squareRoot()))
    }
}

/// A width and height on the map projection.
public struct MKMapSize: Hashable, Sendable {
    public var width: Double
    public var height: Double
    public init() { width = 0; height = 0 }
    public init(width: Double, height: Double) { self.width = width; self.height = height }
    /// The size of the whole world.
    public static let world = MKMapSize(width: 268_435_456, height: 268_435_456)
}

/// A rectangle on the map projection.
public struct MKMapRect: Hashable, Sendable {
    public var origin: MKMapPoint
    public var size: MKMapSize
    public init() { origin = MKMapPoint(); size = MKMapSize() }
    public init(origin: MKMapPoint, size: MKMapSize) { self.origin = origin; self.size = size }
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.init(origin: MKMapPoint(x: x, y: y), size: MKMapSize(width: width, height: height))
    }

    public static let world = MKMapRect(origin: MKMapPoint(), size: .world)
    public static let null = MKMapRect(x: .infinity, y: .infinity, width: 0, height: 0)

    public var minX: Double { origin.x }
    public var minY: Double { origin.y }
    public var maxX: Double { origin.x + size.width }
    public var maxY: Double { origin.y + size.height }
    public var midX: Double { origin.x + size.width / 2 }
    public var midY: Double { origin.y + size.height / 2 }
    public var width: Double { size.width }
    public var height: Double { size.height }
    public var isNull: Bool { origin.x.isInfinite || origin.y.isInfinite }
    public var isEmpty: Bool { isNull || size.width == 0 || size.height == 0 }

    public func contains(_ point: MKMapPoint) -> Bool {
        point.x >= minX && point.x < maxX && point.y >= minY && point.y < maxY
    }
    public func intersects(_ rect: MKMapRect) -> Bool {
        !isNull && !rect.isNull && minX < rect.maxX && rect.minX < maxX && minY < rect.maxY && rect.minY < maxY
    }
    public func union(_ rect: MKMapRect) -> MKMapRect {
        if isNull { return rect }
        if rect.isNull { return self }
        let x = min(minX, rect.minX), y = min(minY, rect.minY)
        return MKMapRect(x: x, y: y, width: max(maxX, rect.maxX) - x, height: max(maxY, rect.maxY) - y)
    }
    public func insetBy(dx: Double, dy: Double) -> MKMapRect {
        MKMapRect(x: minX + dx, y: minY + dy, width: width - 2 * dx, height: height - 2 * dy)
    }

    /// The smallest rectangle around the points.
    static func around(_ points: [MKMapPoint]) -> MKMapRect {
        guard let first = points.first else { return .null }
        var rect = MKMapRect(origin: first, size: MKMapSize())
        for point in points.dropFirst() { rect = rect.union(MKMapRect(origin: point, size: MKMapSize())) }
        return rect
    }
}

// MARK: - Overlays

/// The drawing level of an overlay, relative to the map's labels.
public enum MKOverlayLevel: Int, Sendable {
    case aboveRoads = 0
    case aboveLabels = 1
}

/// How the map follows the user's location.
public enum MKUserTrackingMode: Int, Sendable {
    case none = 0
    case follow = 1
    case followWithHeading = 2
}

/// An annotation that covers an area of the map.
public protocol MKOverlay: MKAnnotation {
    var boundingMapRect: MKMapRect { get }
    func intersects(_ mapRect: MKMapRect) -> Bool
    var canReplaceMapContent: Bool { get }
}

extension MKOverlay {
    public func intersects(_ mapRect: MKMapRect) -> Bool { boundingMapRect.intersects(mapRect) }
    public var canReplaceMapContent: Bool { false }
}

/// A shape with a title, the base of the overlay shapes.
open class MKShape: NSObject, MKAnnotation {
    open var title: String?
    open var subtitle: String?
    open var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: 0, longitude: 0) }
}

/// A shape made of points.
open class MKMultiPoint: MKShape {
    package let mapPoints: [MKMapPoint]
    package init(points: [MKMapPoint]) { self.mapPoints = points }

    open var pointCount: Int { mapPoints.count }
    /// Copies the shape's coordinates in `range` into `coordinates`.
    open func getCoordinates(_ coordinates: UnsafeMutablePointer<CLLocationCoordinate2D>, range: NSRange) {
        for index in 0..<range.length { coordinates[index] = mapPoints[range.location + index].coordinate }
    }
    open var boundingMapRect: MKMapRect { MKMapRect.around(mapPoints) }
    open override var coordinate: CLLocationCoordinate2D {
        let rect = boundingMapRect
        return rect.isNull ? super.coordinate : MKMapPoint(x: rect.midX, y: rect.midY).coordinate
    }
}

/// A line through points.
open class MKPolyline: MKMultiPoint, MKOverlay {
    public convenience init(coordinates: UnsafePointer<CLLocationCoordinate2D>, count: Int) {
        self.init(points: (0..<count).map { MKMapPoint(coordinates[$0]) })
    }
    public convenience init(points: UnsafePointer<MKMapPoint>, count: Int) {
        self.init(points: Array(UnsafeBufferPointer(start: points, count: count)))
    }
}

/// A closed shape through points.
open class MKPolygon: MKMultiPoint, MKOverlay {
    public let interiorPolygons: [MKPolygon]?
    package init(points: [MKMapPoint], interiorPolygons: [MKPolygon]?) {
        self.interiorPolygons = interiorPolygons
        super.init(points: points)
    }
    public convenience init(coordinates: UnsafePointer<CLLocationCoordinate2D>, count: Int, interiorPolygons: [MKPolygon]? = nil) {
        self.init(points: (0..<count).map { MKMapPoint(coordinates[$0]) }, interiorPolygons: interiorPolygons)
    }
}

/// A circle of a radius in meters around a coordinate.
open class MKCircle: MKShape, MKOverlay {
    public let radius: Double
    private let center: CLLocationCoordinate2D
    public init(center coordinate: CLLocationCoordinate2D, radius: Double) {
        self.center = coordinate
        self.radius = radius
    }
    open override var coordinate: CLLocationCoordinate2D { center }
    open var boundingMapRect: MKMapRect {
        let middle = MKMapPoint(center)
        // Map points per meter grow with latitude by 1 / cos(latitude).
        let perMeter = MKMapSize.world.width / 40_075_016.686 / cos(center.latitude * .pi / 180)
        let half = radius * perMeter
        return MKMapRect(x: middle.x - half, y: middle.y - half, width: 2 * half, height: 2 * half)
    }
}

// MARK: - Renderers

/// Draws an overlay. The web map doesn't paint overlays yet; the renderer keeps its styling.
open class MKOverlayRenderer: NSObject {
    public let overlay: any MKOverlay
    open var alpha: CGFloat = 1
    public init(overlay: any MKOverlay) { self.overlay = overlay }
    open func setNeedsDisplay() {}
}

/// Draws an overlay's shape with a fill and a stroke.
open class MKOverlayPathRenderer: MKOverlayRenderer {
    open var fillColor: UIColor?
    open var strokeColor: UIColor?
    open var lineWidth: CGFloat = 0
    open var lineCap: CGLineCap = .round
    open var lineJoin: CGLineJoin = .round
    open var lineDashPattern: [NSNumber]?
}

open class MKPolylineRenderer: MKOverlayPathRenderer {
    public convenience init(polyline: MKPolyline) { self.init(overlay: polyline) }
    open var polyline: MKPolyline? { overlay as? MKPolyline }
}

open class MKPolygonRenderer: MKOverlayPathRenderer {
    public convenience init(polygon: MKPolygon) { self.init(overlay: polygon) }
    open var polygon: MKPolygon? { overlay as? MKPolygon }
}

open class MKCircleRenderer: MKOverlayPathRenderer {
    public convenience init(circle: MKCircle) { self.init(overlay: circle) }
    open var circle: MKCircle? { overlay as? MKCircle }
}
