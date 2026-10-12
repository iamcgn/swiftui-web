// CoreLocation's value types for SwiftUIWeb's `MapKit` (sw-frameworks): coordinates and
// distances. There is no location manager: the browser's geolocation is not bridged.
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif

public typealias CLLocationDegrees = Double
public typealias CLLocationDistance = Double
public typealias CLLocationDirection = Double

/// A latitude and longitude in degrees.
public struct CLLocationCoordinate2D: Hashable, Sendable, Codable {
    public var latitude: CLLocationDegrees
    public var longitude: CLLocationDegrees
    public init() { latitude = 0; longitude = 0 }
    public init(latitude: CLLocationDegrees, longitude: CLLocationDegrees) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

public func CLLocationCoordinate2DIsValid(_ coordinate: CLLocationCoordinate2D) -> Bool {
    abs(coordinate.latitude) <= 90 && abs(coordinate.longitude) <= 180
}

public let kCLLocationCoordinate2DInvalid = CLLocationCoordinate2D(latitude: -180, longitude: -180)

/// A location: a coordinate with a timestamp (altitude and accuracy are nominal).
public final class CLLocation: Sendable {
    public let coordinate: CLLocationCoordinate2D
    public let altitude: CLLocationDistance
    public let timestamp: Date
    public init(latitude: CLLocationDegrees, longitude: CLLocationDegrees) {
        coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        altitude = 0
        timestamp = Date()
    }

    /// The great-circle distance in metres.
    public func distance(from other: CLLocation) -> CLLocationDistance {
        let r = 6_371_000.0
        let a = coordinate.latitude * .pi / 180, b = other.coordinate.latitude * .pi / 180
        let dLon = (other.coordinate.longitude - coordinate.longitude) * .pi / 180
        let x = _sinD(a) * _sinD(b) + _cosD(a) * _cosD(b) * _cosD(dLon)
        return r * _acosD(min(max(x, -1), 1))
    }
}

// Math without Foundation's overlays on wasm (WebGraphics has the same helpers; this module
// stays free of it).
@inline(__always) func _sinD(_ x: Double) -> Double { x.sin() }
@inline(__always) func _cosD(_ x: Double) -> Double { x.cos() }
@inline(__always) func _acosD(_ x: Double) -> Double { x.acos() }

extension Double {
    @inline(__always) func sin() -> Double { _taylorSin(self) }
    @inline(__always) func cos() -> Double { _taylorSin(self + .pi / 2) }
    @inline(__always) func acos() -> Double { _acos(self) }
}

/// A sine for any argument: reduced to (−π, π] and summed to 13 terms.
func _taylorSin(_ x: Double) -> Double {
    var r = x.truncatingRemainder(dividingBy: 2 * .pi)
    if r > .pi { r -= 2 * .pi } else if r <= -.pi { r += 2 * .pi }
    var term = r, sum = r
    for i in 1...12 {
        term *= -r * r / Double((2 * i) * (2 * i + 1))
        sum += term
    }
    return sum
}

/// `acos` by Newton's method over the sine.
func _acos(_ x: Double) -> Double {
    if x >= 1 { return 0 }
    if x <= -1 { return .pi }
    var y = .pi / 2 - x   // a start near the answer for small x
    for _ in 0..<30 {
        let f = _taylorSin(y + .pi / 2) - x   // cos(y) − x
        let d = -_taylorSin(y)                // −sin(y)
        if d == 0 { break }
        let next = y - f / d
        if abs(next - y) < 1e-12 { y = next; break }
        y = next
    }
    return y
}
