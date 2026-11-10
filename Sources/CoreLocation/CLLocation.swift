// CoreLocation for the web (sw-frameworks, pf-corelocation): coordinates, locations and
// distances, and in the files beside this one the location manager over the browser's
// geolocation (`CLLocationManager.swift`), regions, beacons, headings and visits
// (`CLTypes.swift`), the geocoder and placemarks (`CLGeocoder.swift`).
#if os(WASI)
@_exported import WebFoundation
#else
@_exported import Foundation
#endif

public typealias CLLocationDegrees = Double
public typealias CLLocationDistance = Double
public typealias CLLocationDirection = Double
public typealias CLLocationAccuracy = Double
public typealias CLLocationSpeed = Double
public typealias CLLocationSpeedAccuracy = Double
public typealias CLLocationDirectionAccuracy = Double

public let kCLLocationAccuracyBestForNavigation: CLLocationAccuracy = -2
public let kCLLocationAccuracyBest: CLLocationAccuracy = -1
public let kCLLocationAccuracyNearestTenMeters: CLLocationAccuracy = 10
public let kCLLocationAccuracyHundredMeters: CLLocationAccuracy = 100
public let kCLLocationAccuracyKilometer: CLLocationAccuracy = 1000
public let kCLLocationAccuracyThreeKilometers: CLLocationAccuracy = 3000
public let kCLLocationAccuracyReduced: CLLocationAccuracy = 3000
public let kCLDistanceFilterNone: CLLocationDistance = -1
public let CLLocationDistanceMax: CLLocationDistance = .greatestFiniteMagnitude
public let CLTimeIntervalMax: TimeInterval = .greatestFiniteMagnitude

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

public func CLLocationCoordinate2DMake(_ latitude: CLLocationDegrees, _ longitude: CLLocationDegrees) -> CLLocationCoordinate2D {
    CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
}

public func CLLocationCoordinate2DIsValid(_ coordinate: CLLocationCoordinate2D) -> Bool {
    abs(coordinate.latitude) <= 90 && abs(coordinate.longitude) <= 180
}

public let kCLLocationCoordinate2DInvalid = CLLocationCoordinate2D(latitude: -180, longitude: -180)

/// The floor of a building a location is on.
open class CLFloor: NSObject, @unchecked Sendable {
    public let level: Int
    package init(level: Int) { self.level = level }
    open override func isEqual(_ object: Any?) -> Bool { (object as? CLFloor)?.level == level }
    open override var hash: Int { level.hashValue }
}

/// Whether a location came from a simulator or an accessory: on the web, from neither.
open class CLLocationSourceInformation: NSObject, @unchecked Sendable {
    public let isSimulatedBySoftware: Bool
    public let isProducedByAccessory: Bool
    public init(softwareSimulationState isSoftware: Bool, andExternalAccessoryState wasProcessedByAccessory: Bool) {
        isSimulatedBySoftware = isSoftware
        isProducedByAccessory = wasProcessedByAccessory
    }
    public override convenience init() { self.init(softwareSimulationState: false, andExternalAccessoryState: false) }
}

/// A location: a coordinate, its altitude and accuracies, course and speed, and when it was
/// measured. Negative accuracies, course and speed mean "not known", as on Apple platforms. Equal
/// only to itself (`NSObject`'s identity), so a model that stores one can be `Hashable`
/// (FoodTruck's `ParkingSpot`).
open class CLLocation: NSObject, @unchecked Sendable {
    public let coordinate: CLLocationCoordinate2D
    public let altitude: CLLocationDistance
    public let ellipsoidalAltitude: CLLocationDistance
    public let horizontalAccuracy: CLLocationAccuracy
    public let verticalAccuracy: CLLocationAccuracy
    public let course: CLLocationDirection
    public let courseAccuracy: CLLocationDirectionAccuracy
    public let speed: CLLocationSpeed
    public let speedAccuracy: CLLocationSpeedAccuracy
    public let timestamp: Date
    public let floor: CLFloor?
    public let sourceInformation: CLLocationSourceInformation?

    public init(coordinate: CLLocationCoordinate2D, altitude: CLLocationDistance, horizontalAccuracy hAccuracy: CLLocationAccuracy,
                verticalAccuracy vAccuracy: CLLocationAccuracy, course: CLLocationDirection, courseAccuracy: CLLocationDirectionAccuracy,
                speed: CLLocationSpeed, speedAccuracy: CLLocationSpeedAccuracy, timestamp: Date, sourceInfo: CLLocationSourceInformation) {
        self.coordinate = coordinate
        self.altitude = altitude
        ellipsoidalAltitude = altitude
        horizontalAccuracy = hAccuracy
        verticalAccuracy = vAccuracy
        self.course = course
        self.courseAccuracy = courseAccuracy
        self.speed = speed
        self.speedAccuracy = speedAccuracy
        self.timestamp = timestamp
        floor = nil
        sourceInformation = sourceInfo
    }

    public convenience init(latitude: CLLocationDegrees, longitude: CLLocationDegrees) {
        self.init(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude), altitude: 0, horizontalAccuracy: 0,
                  verticalAccuracy: -1, timestamp: Date())
    }

    public convenience init(coordinate: CLLocationCoordinate2D, altitude: CLLocationDistance, horizontalAccuracy hAccuracy: CLLocationAccuracy,
                            verticalAccuracy vAccuracy: CLLocationAccuracy, timestamp: Date) {
        self.init(coordinate: coordinate, altitude: altitude, horizontalAccuracy: hAccuracy, verticalAccuracy: vAccuracy,
                  course: -1, courseAccuracy: -1, speed: -1, speedAccuracy: -1, timestamp: timestamp)
    }

    public convenience init(coordinate: CLLocationCoordinate2D, altitude: CLLocationDistance, horizontalAccuracy hAccuracy: CLLocationAccuracy,
                            verticalAccuracy vAccuracy: CLLocationAccuracy, course: CLLocationDirection, speed: CLLocationSpeed, timestamp: Date) {
        self.init(coordinate: coordinate, altitude: altitude, horizontalAccuracy: hAccuracy, verticalAccuracy: vAccuracy,
                  course: course, courseAccuracy: -1, speed: speed, speedAccuracy: -1, timestamp: timestamp)
    }

    public convenience init(coordinate: CLLocationCoordinate2D, altitude: CLLocationDistance, horizontalAccuracy hAccuracy: CLLocationAccuracy,
                            verticalAccuracy vAccuracy: CLLocationAccuracy, course: CLLocationDirection, courseAccuracy: CLLocationDirectionAccuracy,
                            speed: CLLocationSpeed, speedAccuracy: CLLocationSpeedAccuracy, timestamp: Date) {
        self.init(coordinate: coordinate, altitude: altitude, horizontalAccuracy: hAccuracy, verticalAccuracy: vAccuracy,
                  course: course, courseAccuracy: courseAccuracy, speed: speed, speedAccuracy: speedAccuracy, timestamp: timestamp,
                  sourceInfo: CLLocationSourceInformation())
    }

    /// The great-circle distance in metres.
    public func distance(from location: CLLocation) -> CLLocationDistance {
        _distance(coordinate, location.coordinate)
    }

    /// Apple's shape: `<+lat,+lon> +/- 5.00m (speed -1.00 mps / course -1.00) @ date`.
    open override var description: String {
        "<\(_signed(coordinate.latitude, 8)),\(_signed(coordinate.longitude, 8))> +/- \(_fixed(horizontalAccuracy, 2))m "
            + "(speed \(_fixed(speed, 2)) mps / course \(_fixed(course, 2))) @ \(timestamp)"
    }
}

/// The great-circle distance between two coordinates, in metres.
func _distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> CLLocationDistance {
    let r = 6_371_000.0
    let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
    let dLon = (b.longitude - a.longitude) * .pi / 180
    let x = _sinD(lat1) * _sinD(lat2) + _cosD(lat1) * _cosD(lat2) * _cosD(dLon)
    return r * _acosD(min(max(x, -1), 1))
}

/// A number with `places` decimals, without Foundation's `String(format:)`.
func _fixed(_ value: Double, _ places: Int) -> String {
    guard value.isFinite else { return "\(value)" }
    var scale = 1.0
    for _ in 0..<places { scale *= 10 }
    let negative = value < 0
    let scaled = (abs(value) * scale).rounded()
    guard scaled < 9e18 else { return "\(value)" }
    let whole = UInt64(scaled)
    let integer = whole / UInt64(scale), fraction = whole % UInt64(scale)
    var digits = String(fraction)
    while digits.count < places { digits = "0" + digits }
    return (negative && whole != 0 ? "-" : "") + String(integer) + (places > 0 ? "." + digits : "")
}

func _signed(_ value: Double, _ places: Int) -> String {
    let text = _fixed(value, places)
    return text.hasPrefix("-") ? text : "+" + text
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
