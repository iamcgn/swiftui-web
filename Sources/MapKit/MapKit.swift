// `Map` for SwiftUIWeb (sw-frameworks, decision 0018): a painted map over OpenStreetMap's
// raster tiles, fetched like any URL image by the host (`AsyncImage`'s loader), with markers
// and annotations placed by Web Mercator. The tiles' look is OpenStreetMap's, not Apple's
// (recorded as approximate); the camera is a region (centre and span) and fits the view.
// Pans and zooms are not interactive yet.
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif
import SwiftUI
@_exported import CoreLocation

/// The span of a region in degrees.
public struct MKCoordinateSpan: Hashable, Sendable {
    public var latitudeDelta: CLLocationDegrees
    public var longitudeDelta: CLLocationDegrees
    public init() { latitudeDelta = 0; longitudeDelta = 0 }
    public init(latitudeDelta: CLLocationDegrees, longitudeDelta: CLLocationDegrees) {
        self.latitudeDelta = latitudeDelta
        self.longitudeDelta = longitudeDelta
    }
}

/// A rectangular region of the map: a centre and a span.
public struct MKCoordinateRegion: Hashable, Sendable {
    public var center: CLLocationCoordinate2D
    public var span: MKCoordinateSpan
    public init() { center = CLLocationCoordinate2D(); span = MKCoordinateSpan() }
    public init(center: CLLocationCoordinate2D, span: MKCoordinateSpan) {
        self.center = center
        self.span = span
    }
    /// A region around a centre by distances in metres.
    public init(center: CLLocationCoordinate2D, latitudinalMeters: CLLocationDistance, longitudinalMeters: CLLocationDistance) {
        self.center = center
        let latDelta = latitudinalMeters / 111_320
        let lonDelta = longitudinalMeters / (111_320 * max(0.01, _cosDegrees(center.latitude)))
        span = MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
    }
}

func _cosDegrees(_ degrees: Double) -> Double { _cos(degrees * .pi / 180) }

/// How the map's camera is placed.
public struct MapCameraPosition: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case automatic
        case region(MKCoordinateRegion)
        case camera(MapCamera)
        case userLocation
    }
    let kind: Kind

    public static var automatic: MapCameraPosition { MapCameraPosition(kind: .automatic) }
    public static func region(_ region: MKCoordinateRegion) -> MapCameraPosition { MapCameraPosition(kind: .region(region)) }
    public static func camera(_ camera: MapCamera) -> MapCameraPosition { MapCameraPosition(kind: .camera(camera)) }
    public static func userLocation(followsHeading: Bool = false, fallback: MapCameraPosition) -> MapCameraPosition { fallback }
    public static func item(_ item: MKMapItem, allowsAutomaticPitch: Bool = true) -> MapCameraPosition {
        MapCameraPosition(kind: .region(MKCoordinateRegion(center: item.coordinate, latitudinalMeters: 2000, longitudinalMeters: 2000)))
    }

    public var region: MKCoordinateRegion? {
        switch kind {
        case .region(let r): return r
        case .camera(let c): return MKCoordinateRegion(center: c.centerCoordinate, latitudinalMeters: c.distance, longitudinalMeters: c.distance)
        default: return nil
        }
    }
    public var positionedByUser: Bool { false }
}

/// A camera: a centre and a distance in metres (pitch and heading are accepted, not shown).
public struct MapCamera: Hashable, Sendable {
    public var centerCoordinate: CLLocationCoordinate2D
    public var distance: CLLocationDistance
    public var heading: CLLocationDirection
    public var pitch: Double
    public init(centerCoordinate: CLLocationCoordinate2D, distance: CLLocationDistance, heading: CLLocationDirection = 0, pitch: Double = 0) {
        self.centerCoordinate = centerCoordinate
        self.distance = distance
        self.heading = heading
        self.pitch = pitch
    }
}

/// A place on the map.
public final class MKMapItem: @unchecked Sendable {
    public let coordinate: CLLocationCoordinate2D
    public var name: String?
    public init(coordinate: CLLocationCoordinate2D, name: String? = nil) {
        self.coordinate = coordinate
        self.name = name
    }
    public init(placemark: MKPlacemark) {
        coordinate = placemark.coordinate
        name = placemark.name
    }
}

public struct MKPlacemark: Hashable, Sendable {
    public var coordinate: CLLocationCoordinate2D
    public var name: String?
    public init(coordinate: CLLocationCoordinate2D) { self.coordinate = coordinate }
}

/// The map's style (accepted: the tiles are OpenStreetMap's standard ones).
public struct MapStyle: Hashable, Sendable {
    public enum Elevation: Hashable, Sendable { case automatic, flat, realistic }
    public enum Emphasis: Hashable, Sendable { case automatic, muted }
    let name: String
    public static var standard: MapStyle { MapStyle(name: "standard") }
    public static func standard(elevation: Elevation = .automatic, emphasis: Emphasis = .automatic, pointsOfInterest: PointOfInterestCategories = .all, showsTraffic: Bool = false) -> MapStyle { MapStyle(name: "standard") }
    public static var imagery: MapStyle { MapStyle(name: "imagery") }
    public static func imagery(elevation: Elevation = .automatic) -> MapStyle { MapStyle(name: "imagery") }
    public static var hybrid: MapStyle { MapStyle(name: "hybrid") }
    public static func hybrid(elevation: Elevation = .automatic, pointsOfInterest: PointOfInterestCategories = .all, showsTraffic: Bool = false) -> MapStyle { MapStyle(name: "hybrid") }
}

public struct PointOfInterestCategories: Hashable, Sendable {
    public static let all = PointOfInterestCategories()
    public static let excludingAll = PointOfInterestCategories()
    public static func including(_ categories: [String]) -> PointOfInterestCategories { PointOfInterestCategories() }
    public static func excluding(_ categories: [String]) -> PointOfInterestCategories { PointOfInterestCategories() }
}

public enum MapInteractionModes: Hashable, Sendable {
    case pan, zoom, rotate, pitch, all
}

// MARK: - Content

/// What a map shows: markers and annotations.
public protocol MapContent {
    @MainActor func _collect(into items: inout [_MapItem])
}

public struct _MapItem {
    package var coordinate: CLLocationCoordinate2D
    package var title: String?
    package var tint: Color?
    package var systemImage: String?
    package var content: AnyView?
    package var anchor: UnitPoint = .center
    package init(coordinate: CLLocationCoordinate2D, title: String? = nil, tint: Color? = nil, systemImage: String? = nil, content: AnyView? = nil, anchor: UnitPoint = .center) {
        self.coordinate = coordinate; self.title = title; self.tint = tint; self.systemImage = systemImage; self.content = content; self.anchor = anchor
    }
}

@resultBuilder
public struct MapContentBuilder {
    public static func buildBlock() -> EmptyMapContent { EmptyMapContent() }
    public static func buildBlock<C: MapContent>(_ content: C) -> C { content }
    public static func buildBlock<each C: MapContent>(_ content: repeat each C) -> _TupleMapContent<repeat each C> { _TupleMapContent(content: (repeat each content)) }
    public static func buildExpression<C: MapContent>(_ content: C) -> C { content }
    public static func buildOptional<C: MapContent>(_ content: C?) -> _OptionalMapContent<C> { _OptionalMapContent(content: content) }
    public static func buildEither<T: MapContent, F: MapContent>(first: T) -> _EitherMapContent<T, F> { .init(first: first, second: nil) }
    public static func buildEither<T: MapContent, F: MapContent>(second: F) -> _EitherMapContent<T, F> { .init(first: nil, second: second) }
    public static func buildArray<C: MapContent>(_ components: [C]) -> _ArrayMapContent<C> { _ArrayMapContent(contents: components) }
}

public struct EmptyMapContent: MapContent {
    public init() {}
    @MainActor public func _collect(into items: inout [_MapItem]) {}
}

public struct _TupleMapContent<each C: MapContent>: MapContent {
    let content: (repeat each C)
    @MainActor public func _collect(into items: inout [_MapItem]) { for c in repeat each content { c._collect(into: &items) } }
}

public struct _OptionalMapContent<C: MapContent>: MapContent {
    let content: C?
    @MainActor public func _collect(into items: inout [_MapItem]) { content?._collect(into: &items) }
}

public struct _EitherMapContent<T: MapContent, F: MapContent>: MapContent {
    let first: T?
    let second: F?
    @MainActor public func _collect(into items: inout [_MapItem]) { first?._collect(into: &items); second?._collect(into: &items) }
}

public struct _ArrayMapContent<C: MapContent>: MapContent {
    let contents: [C]
    @MainActor public func _collect(into items: inout [_MapItem]) { for c in contents { c._collect(into: &items) } }
}

extension ForEach: MapContent where Content: MapContent {
    @MainActor public func _collect(into items: inout [_MapItem]) { for element in data { content(element)._collect(into: &items) } }
}

extension ForEach where ID == Data.Element.ID, Content: MapContent, Data.Element: Identifiable {
    public init(_ data: Data, @MapContentBuilder content: @escaping (Data.Element) -> Content) { self.init(data: data, id: \.id, content: content) }
}

extension ForEach where Content: MapContent {
    public init(_ data: Data, id: KeyPath<Data.Element, ID>, @MapContentBuilder content: @escaping (Data.Element) -> Content) { self.init(data: data, id: id, content: content) }
}

/// A balloon marker with a title: a red pin (`tint` recolours it) with a glyph.
public struct Marker<Label: View>: MapContent {
    let coordinate: CLLocationCoordinate2D
    let title: String?
    let systemImage: String?
    var tint: Color?

    public init(coordinate: CLLocationCoordinate2D, @ViewBuilder label: () -> Label) {
        title = nil; self.coordinate = coordinate; systemImage = nil
    }

    public func tint<S: ShapeStyle>(_ style: S) -> Marker {
        var copy = self
        copy.tint = style as? Color
        return copy
    }

    @MainActor public func _collect(into items: inout [_MapItem]) {
        items.append(_MapItem(coordinate: coordinate, title: title, tint: tint, systemImage: systemImage))
    }
}

extension Marker where Label == Text {
    public init(_ title: String, coordinate: CLLocationCoordinate2D) {
        self.title = title; self.coordinate = coordinate; systemImage = nil
    }
    public init(_ title: String, systemImage: String, coordinate: CLLocationCoordinate2D) {
        self.title = title; self.coordinate = coordinate; self.systemImage = systemImage
    }
    public init(_ title: String, monogram: Text, coordinate: CLLocationCoordinate2D) {
        self.title = title; self.coordinate = coordinate; systemImage = nil
    }
    public init(_ title: Text, coordinate: CLLocationCoordinate2D) {
        self.title = "\(title)"; self.coordinate = coordinate; systemImage = nil
    }
    public init(item: MKMapItem) {
        title = item.name; coordinate = item.coordinate; systemImage = nil
    }
}

/// A custom view at a coordinate, with a title.
public struct Annotation<Label: View, Content: View>: MapContent {
    let coordinate: CLLocationCoordinate2D
    let title: String?
    let anchor: UnitPoint
    let content: Content

    public init(_ title: String, coordinate: CLLocationCoordinate2D, anchor: UnitPoint = .center, @ViewBuilder content: () -> Content) where Label == Text {
        self.title = title; self.coordinate = coordinate; self.anchor = anchor; self.content = content()
    }
    public init(coordinate: CLLocationCoordinate2D, anchor: UnitPoint = .center, @ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
        title = nil; self.coordinate = coordinate; self.anchor = anchor; self.content = content()
    }

    @MainActor public func _collect(into items: inout [_MapItem]) {
        items.append(_MapItem(coordinate: coordinate, title: title, tint: nil, systemImage: nil, content: AnyView(content), anchor: anchor))
    }
}

/// The user's location (not available to the hosts: shows nothing).
public struct UserAnnotation: MapContent {
    public init() {}
    @MainActor public func _collect(into items: inout [_MapItem]) {}
}

/// Lines and shapes over the map (accepted; not painted yet).
public struct MapPolyline: MapContent {
    public init(coordinates: [CLLocationCoordinate2D], contourStyle: ContourStyle = .straight) {}
    public init(points: [CGPoint]) {}
    public enum ContourStyle: Sendable { case straight, geodesic }
    public func stroke<S: ShapeStyle>(_ style: S, lineWidth: CGFloat = 1) -> MapPolyline { self }
    public func stroke<S: ShapeStyle>(_ style: S, style strokeStyle: StrokeStyle) -> MapPolyline { self }
    @MainActor public func _collect(into items: inout [_MapItem]) {}
}

public struct MapCircle: MapContent {
    public init(center: CLLocationCoordinate2D, radius: CLLocationDistance) {}
    public func foregroundStyle<S: ShapeStyle>(_ style: S) -> MapCircle { self }
    public func stroke<S: ShapeStyle>(_ style: S, lineWidth: CGFloat = 1) -> MapCircle { self }
    @MainActor public func _collect(into items: inout [_MapItem]) {}
}

// MARK: - The map view

/// A view that displays an embedded map interface.
public struct Map<Content: MapContent>: View {
    let region: MKCoordinateRegion?
    let binding: Binding<MapCameraPosition>?
    let content: Content

    /// A map at an initial camera position.
    public init(initialPosition: MapCameraPosition = .automatic, bounds: MapCameraBounds? = nil, interactionModes: MapInteractionModes = .all, scope: Namespace.ID? = nil, @MapContentBuilder content: () -> Content) {
        region = initialPosition.region
        binding = nil
        self.content = content()
    }

    /// A map following a bound camera position.
    public init(position: Binding<MapCameraPosition>, bounds: MapCameraBounds? = nil, interactionModes: MapInteractionModes = .all, scope: Namespace.ID? = nil, @MapContentBuilder content: () -> Content) {
        region = nil
        binding = position
        self.content = content()
    }

    /// The older region binding.
    public init(coordinateRegion: Binding<MKCoordinateRegion>, interactionModes: MapInteractionModes = .all, showsUserLocation: Bool = false) where Content == EmptyMapContent {
        region = coordinateRegion.wrappedValue
        binding = nil
        content = EmptyMapContent()
    }

    public var body: some View {
        var items: [_MapItem] = []
        content._collect(into: &items)
        let region = binding?.wrappedValue.region ?? self.region ?? Self.automaticRegion(for: items)
        return GeometryReader { geometry in
            _MapTiles(region: region, size: geometry.size, items: items)
        }
        .clipped()
    }

    /// A region fitting the items (a 2 km region around a single one; a world view with none).
    package static func automaticRegion(for items: [_MapItem]) -> MKCoordinateRegion {
        guard let first = items.first else {
            return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 20, longitude: 0), span: MKCoordinateSpan(latitudeDelta: 120, longitudeDelta: 300))
        }
        var minLat = first.coordinate.latitude, maxLat = minLat, minLon = first.coordinate.longitude, maxLon = minLon
        for item in items {
            minLat = min(minLat, item.coordinate.latitude); maxLat = max(maxLat, item.coordinate.latitude)
            minLon = min(minLon, item.coordinate.longitude); maxLon = max(maxLon, item.coordinate.longitude)
        }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        if items.count == 1 { return MKCoordinateRegion(center: center, latitudinalMeters: 2000, longitudinalMeters: 2000) }
        return MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: max(maxLat - minLat, 0.001) * 1.4, longitudeDelta: max(maxLon - minLon, 0.001) * 1.4))
    }
}

extension Map where Content == EmptyMapContent {
    public init(initialPosition: MapCameraPosition = .automatic, bounds: MapCameraBounds? = nil, interactionModes: MapInteractionModes = .all, scope: Namespace.ID? = nil) {
        self.init(initialPosition: initialPosition, bounds: bounds, interactionModes: interactionModes, scope: scope) { EmptyMapContent() }
    }
    public init(position: Binding<MapCameraPosition>, bounds: MapCameraBounds? = nil, interactionModes: MapInteractionModes = .all, scope: Namespace.ID? = nil) {
        self.init(position: position, bounds: bounds, interactionModes: interactionModes, scope: scope) { EmptyMapContent() }
    }
}

public struct MapCameraBounds: Sendable {
    public init(centerCoordinateBounds: MKCoordinateRegion? = nil, minimumDistance: CLLocationDistance? = nil, maximumDistance: CLLocationDistance? = nil) {}
}

extension View {
    public func mapStyle(_ style: MapStyle) -> some View { self }
    public func mapControls<V: View>(@ViewBuilder content: () -> V) -> some View { self }
    public func mapControlVisibility(_ visibility: Visibility) -> some View { self }
    public func mapScope(_ scope: Namespace.ID) -> some View { self }
    public func onMapCameraChange(frequency: MapCameraUpdateFrequency = .onEnd, _ action: @escaping (MapCameraUpdateContext) -> Void) -> some View { self }
    public func onMapCameraChange(frequency: MapCameraUpdateFrequency = .onEnd, _ action: @escaping () -> Void) -> some View { self }
}

public enum MapCameraUpdateFrequency: Sendable { case onEnd, continuous }
public struct MapCameraUpdateContext: Sendable {
    public var region: MKCoordinateRegion
    public var camera: MapCamera
}

/// The map controls (accepted; the painted map has none).
public struct MapCompass: View { public init() {}; public var body: some View { EmptyView() } }
public struct MapScaleView: View { public init() {}; public var body: some View { EmptyView() } }
public struct MapUserLocationButton: View { public init() {}; public var body: some View { EmptyView() } }
public struct MapPitchToggle: View { public init() {}; public var body: some View { EmptyView() } }
public struct MapZoomStepper: View { public init() {}; public var body: some View { EmptyView() } }

// MARK: - Tiles

/// Web Mercator: the tile grid at a zoom, the tiles covering the view and the items' points.
package struct _MapTiles: View {
    package let region: MKCoordinateRegion
    package let size: CGSize
    package let items: [_MapItem]
    package init(region: MKCoordinateRegion, size: CGSize, items: [_MapItem]) { self.region = region; self.size = size; self.items = items }

    static let tileSize: CGFloat = 256
    static let tileURL = "https://tile.openstreetmap.org"

    /// The zoom whose tiles show the region's longitude span across the width (fractional
    /// zooms scale the tiles).
    package var zoom: Double {
        let lonSpan = max(region.span.longitudeDelta, 0.0001)
        let latSpan = max(region.span.latitudeDelta, 0.0001)
        let byWidth = _log2(Double(size.width) / Double(Self.tileSize) * 360 / lonSpan)
        let byHeight = _log2(Double(size.height) / Double(Self.tileSize) * 180 / latSpan)
        return min(max(min(byWidth, byHeight), 1), 19)
    }

    /// A coordinate's position in world pixels at a zoom.
    package static func worldPoint(_ coordinate: CLLocationCoordinate2D, zoom: Double) -> CGPoint {
        let scale = Double(tileSize) * _pow2(zoom)
        let x = (coordinate.longitude + 180) / 360 * scale
        let lat = min(max(coordinate.latitude, -85.05), 85.05) * .pi / 180
        let y = (1 - _ln((1 + _sin(lat)) / _cos(lat)) / .pi) / 2 * scale
        return CGPoint(x: x, y: y)
    }

    package var body: some View {
        let z = zoom
        let level = Int(z.rounded(.down))
        let tileScale = _pow2(z - Double(level))   // tiles of the integer level scaled up to the fractional zoom
        let center = Self.worldPoint(region.center, zoom: z)
        let origin = CGPoint(x: center.x - Double(size.width) / 2, y: center.y - Double(size.height) / 2)
        let scaledTile = Double(Self.tileSize) * tileScale
        let count = Int(_pow2(Double(level)))
        let firstX = Int((origin.x / scaledTile).rounded(.down)), lastX = Int(((origin.x + Double(size.width)) / scaledTile).rounded(.down))
        let firstY = Int((origin.y / scaledTile).rounded(.down)), lastY = Int(((origin.y + Double(size.height)) / scaledTile).rounded(.down))
        // Every child is positioned, so the stack stays the view's size whatever the tiles cover.
        ZStack {
            Color(red: 0.93, green: 0.93, blue: 0.91)
            ForEach(firstY...max(firstY, lastY), id: \.self) { ty in
                ForEach(firstX...max(firstX, lastX), id: \.self) { tx in
                    if ty >= 0 && ty < count {
                        let wrapped = ((tx % count) + count) % count
                        _Tile(url: "\(Self.tileURL)/\(level)/\(wrapped)/\(ty).png")
                            .frame(width: scaledTile, height: scaledTile)
                            .position(x: (Double(tx) + 0.5) * scaledTile - origin.x, y: (Double(ty) + 0.5) * scaledTile - origin.y)
                    }
                }
            }
            ForEach(Array(items.enumerated()), id: \.offset) { entry in
                let point = Self.worldPoint(entry.element.coordinate, zoom: z)
                _MapItemView(item: entry.element)
                    .position(x: point.x - origin.x, y: point.y - origin.y)
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

/// One tile image.
struct _Tile: View {
    let url: String
    var body: some View {
        AsyncImage(url: URL(string: url)) { image in
            image.resizable()
        } placeholder: {
            Color.clear
        }
    }
}

/// A marker balloon (28 pt, the tint or Apple's marker red) with its title below, or an
/// annotation's own content anchored at the coordinate.
struct _MapItemView: View {
    let item: _MapItem
    var body: some View {
        if let content = item.content {
            content
        } else {
            // A zero-size anchor at the coordinate holding the balloon and title at their own
            // sizes, top-aligned, moved up by the balloon's height so its tip is on the point.
            VStack(spacing: 2) {
                _Balloon(tint: item.tint ?? Color(red: 1, green: 0.23, blue: 0.19), glyph: item.systemImage)
                    .frame(width: 28, height: 36)
                if let title = item.title {
                    Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(Color(red: 0.2, green: 0.2, blue: 0.2))
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Color.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 4))
                }
            }
            .fixedSize()
            .frame(width: 0, height: 0, alignment: .top)
            .offset(y: -36)
        }
    }
}

struct _Balloon: View {
    let tint: Color
    let glyph: String?
    var body: some View {
        ZStack {
            Path { path in
                path.addArc(center: CGPoint(x: 14, y: 14), radius: 14, startAngle: .degrees(150), endAngle: .degrees(30), clockwise: false)
                path.addLine(to: CGPoint(x: 14, y: 36))
                path.closeSubpath()
            }
            .fill(tint)
            if let glyph {
                Image(systemName: glyph).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white).offset(y: -4)
            } else {
                Circle().fill(.white).frame(width: 8, height: 8).offset(y: -4)
            }
        }
    }
}

// Math helpers without Foundation (wasm).
func _log2(_ x: Double) -> Double { _ln(x) / _ln(2) }
func _pow2(_ x: Double) -> Double {
    // 2^x = e^(x ln 2) by the exponential series on the fractional part, shifted by the integer part.
    let whole = x.rounded(.down)
    let fraction = x - whole
    var term = 1.0, sum = 1.0
    let y = fraction * _ln(2)
    for i in 1...20 { term *= y / Double(i); sum += term }
    return sum * Double(sign: .plus, exponent: Int(whole), significand: 1)
}
func _ln(_ x: Double) -> Double {
    // ln x = 2 atanh((x − 1)/(x + 1)) after scaling x into [0.5, 1) by powers of two.
    guard x > 0 else { return -.infinity }
    let e = x.exponent
    let m = x / Double(sign: .plus, exponent: e, significand: 1)   // m in [1, 2)
    let t = (m - 1) / (m + 1)
    var term = t, sum = t
    for i in stride(from: 3, through: 41, by: 2) { term *= t * t; sum += term / Double(i) }
    return 2 * sum + Double(e) * 0.6931471805599453
}
