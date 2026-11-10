// CoreLocation's enums, errors, regions, beacons, headings and visits (pf-corelocation). The
// raw values are Apple's, so a value an app stored or sent keeps its meaning.

// MARK: - Authorization and configuration

public enum CLAuthorizationStatus: Int32, Sendable {
    case notDetermined = 0
    case restricted = 1
    case denied = 2
    case authorizedAlways = 3
    case authorizedWhenInUse = 4
    @available(*, deprecated, renamed: "authorizedAlways")
    public static var authorized: CLAuthorizationStatus { .authorizedAlways }
}

public enum CLAccuracyAuthorization: Int, Sendable {
    case fullAccuracy = 0
    case reducedAccuracy = 1
}

public enum CLActivityType: Int, Sendable {
    case other = 1
    case automotiveNavigation = 2
    case fitness = 3
    case otherNavigation = 4
    case airborne = 5
}

public enum CLDeviceOrientation: Int32, Sendable {
    case unknown = 0
    case portrait = 1
    case portraitUpsideDown = 2
    case landscapeLeft = 3
    case landscapeRight = 4
    case faceUp = 5
    case faceDown = 6
}

public enum CLProximity: Int, Sendable {
    case unknown = 0
    case immediate = 1
    case near = 2
    case far = 3
}

public enum CLRegionState: Int, Sendable {
    case unknown = 0
    case inside = 1
    case outside = 2
}

// MARK: - Errors

public let kCLErrorDomain = "kCLErrorDomain"

/// A CoreLocation error, as Swift sees Apple's `CLError`: a code in `kCLErrorDomain`.
public struct CLError: CustomNSError, Hashable, @unchecked Sendable {
    public enum Code: Int, Sendable {
        case locationUnknown = 0
        case denied = 1
        case network = 2
        case headingFailure = 3
        case regionMonitoringDenied = 4
        case regionMonitoringFailure = 5
        case regionMonitoringSetupDelayed = 6
        case regionMonitoringResponseDelayed = 7
        case geocodeFoundNoResult = 8
        case geocodeFoundPartialResult = 9
        case geocodeCanceled = 10
        case deferredFailed = 11
        case deferredNotUpdatingLocation = 12
        case deferredAccuracyTooLow = 13
        case deferredDistanceFiltered = 14
        case deferredCanceled = 15
        case rangingUnavailable = 16
        case rangingFailure = 17
        case promptDeclined = 18
        case historicalLocationError = 19
    }

    public let code: Code
    public let userInfo: [String: Any]
    public init(_ code: Code, userInfo: [String: Any] = [:]) {
        self.code = code
        self.userInfo = userInfo
    }

    public static var errorDomain: String { kCLErrorDomain }
    public var errorCode: Int { code.rawValue }
    public var errorUserInfo: [String: Any] { userInfo }

    public static func == (lhs: CLError, rhs: CLError) -> Bool { lhs.code == rhs.code }
    public func hash(into hasher: inout Hasher) { hasher.combine(code) }

    public static var locationUnknown: Code { .locationUnknown }
    public static var denied: Code { .denied }
    public static var network: Code { .network }
    public static var headingFailure: Code { .headingFailure }
    public static var regionMonitoringDenied: Code { .regionMonitoringDenied }
    public static var regionMonitoringFailure: Code { .regionMonitoringFailure }
    public static var regionMonitoringSetupDelayed: Code { .regionMonitoringSetupDelayed }
    public static var regionMonitoringResponseDelayed: Code { .regionMonitoringResponseDelayed }
    public static var geocodeFoundNoResult: Code { .geocodeFoundNoResult }
    public static var geocodeFoundPartialResult: Code { .geocodeFoundPartialResult }
    public static var geocodeCanceled: Code { .geocodeCanceled }
    public static var deferredFailed: Code { .deferredFailed }
    public static var deferredNotUpdatingLocation: Code { .deferredNotUpdatingLocation }
    public static var deferredAccuracyTooLow: Code { .deferredAccuracyTooLow }
    public static var deferredDistanceFiltered: Code { .deferredDistanceFiltered }
    public static var deferredCanceled: Code { .deferredCanceled }
    public static var rangingUnavailable: Code { .rangingUnavailable }
    public static var rangingFailure: Code { .rangingFailure }
    public static var promptDeclined: Code { .promptDeclined }
    public static var historicalLocationError: Code { .historicalLocationError }
}

/// `catch CLError.denied`: the code matches a `CLError` with that code.
public func ~= (code: CLError.Code, error: any Error) -> Bool { (error as? CLError)?.code == code }

// MARK: - Headings

public typealias CLHeadingComponentValue = Double
public let kCLHeadingFilterNone: CLLocationDegrees = -1

/// A compass heading. The browser has no compass here, so the manager never delivers one; apps
/// and tests that model one still have the type.
open class CLHeading: NSObject, @unchecked Sendable {
    public let magneticHeading: CLLocationDirection
    public let trueHeading: CLLocationDirection
    public let headingAccuracy: CLLocationDirection
    public let x: CLHeadingComponentValue
    public let y: CLHeadingComponentValue
    public let z: CLHeadingComponentValue
    public let timestamp: Date
    package init(magneticHeading: CLLocationDirection, trueHeading: CLLocationDirection, headingAccuracy: CLLocationDirection,
                 x: CLHeadingComponentValue = 0, y: CLHeadingComponentValue = 0, z: CLHeadingComponentValue = 0, timestamp: Date = Date()) {
        self.magneticHeading = magneticHeading
        self.trueHeading = trueHeading
        self.headingAccuracy = headingAccuracy
        self.x = x
        self.y = y
        self.z = z
        self.timestamp = timestamp
    }
    open override var description: String {
        "magneticHeading \(_fixed(magneticHeading, 2)) trueHeading \(_fixed(trueHeading, 2)) accuracy \(_fixed(headingAccuracy, 2)) "
            + "x \(_fixed(x, 3)) y \(_fixed(y, 3)) z \(_fixed(z, 3)) @ \(timestamp)"
    }
}

// MARK: - Regions

/// A region the manager can monitor.
open class CLRegion: NSObject, @unchecked Sendable {
    public let identifier: String
    open var notifyOnEntry = true
    open var notifyOnExit = true
    package init(identifier: String) { self.identifier = identifier }

    @available(*, deprecated, message: "Use CLCircularRegion")
    public convenience init(circularRegionWithCenter center: CLLocationCoordinate2D, radius: CLLocationDistance, identifier: String) {
        self.init(identifier: identifier)
    }

    // Subclasses describe themselves through `regionDescription`: under the Objective-C runtime a
    // second override of `description` also meets NSObject's protocol property and is refused.
    open override var description: String { regionDescription }
    var regionDescription: String { "\(type(of: self)) (identifier:'\(identifier)')" }
}

/// A circle on the Earth's surface: entered and left as the browser's positions cross it.
open class CLCircularRegion: CLRegion, @unchecked Sendable {
    public let center: CLLocationCoordinate2D
    public let radius: CLLocationDistance
    public init(center: CLLocationCoordinate2D, radius: CLLocationDistance, identifier: String) {
        self.center = center
        self.radius = radius
        super.init(identifier: identifier)
    }
    open func contains(_ coordinate: CLLocationCoordinate2D) -> Bool { _distance(center, coordinate) <= radius }
    override var regionDescription: String {
        "CLCircularRegion (identifier:'\(identifier)', center:<\(_signed(center.latitude, 8)),\(_signed(center.longitude, 8))>, radius:\(_fixed(radius, 2))m)"
    }
}

// MARK: - Beacons

public typealias CLBeaconMajorValue = UInt16
public typealias CLBeaconMinorValue = UInt16

/// The UUID, and optionally major and minor values, a beacon must carry.
open class CLBeaconIdentityConstraint: NSObject, @unchecked Sendable {
    public let uuid: UUID
    public let major: CLBeaconMajorValue?
    public let minor: CLBeaconMinorValue?
    public init(uuid: UUID) { self.uuid = uuid; major = nil; minor = nil }
    public init(uuid: UUID, major: CLBeaconMajorValue) { self.uuid = uuid; self.major = major; minor = nil }
    public init(uuid: UUID, major: CLBeaconMajorValue, minor: CLBeaconMinorValue) { self.uuid = uuid; self.major = major; self.minor = minor }
    open override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? CLBeaconIdentityConstraint else { return false }
        return other.uuid == uuid && other.major == major && other.minor == minor
    }
    open override var hash: Int {
        var hasher = Hasher()
        hasher.combine(uuid)
        hasher.combine(major)
        hasher.combine(minor)
        return hasher.finalize()
    }
}

/// A region of beacons. A page has no Bluetooth beacon ranging, so monitoring one fails.
open class CLBeaconRegion: CLRegion, @unchecked Sendable {
    public let beaconIdentityConstraint: CLBeaconIdentityConstraint
    open var notifyEntryStateOnDisplay = false
    public var uuid: UUID { beaconIdentityConstraint.uuid }
    public var major: NSNumber? { beaconIdentityConstraint.major.map { NSNumber(value: $0) } }
    public var minor: NSNumber? { beaconIdentityConstraint.minor.map { NSNumber(value: $0) } }
    public init(beaconIdentityConstraint: CLBeaconIdentityConstraint, identifier: String) {
        self.beaconIdentityConstraint = beaconIdentityConstraint
        super.init(identifier: identifier)
    }
    public convenience init(uuid: UUID, identifier: String) {
        self.init(beaconIdentityConstraint: CLBeaconIdentityConstraint(uuid: uuid), identifier: identifier)
    }
    public convenience init(uuid: UUID, major: CLBeaconMajorValue, identifier: String) {
        self.init(beaconIdentityConstraint: CLBeaconIdentityConstraint(uuid: uuid, major: major), identifier: identifier)
    }
    public convenience init(uuid: UUID, major: CLBeaconMajorValue, minor: CLBeaconMinorValue, identifier: String) {
        self.init(beaconIdentityConstraint: CLBeaconIdentityConstraint(uuid: uuid, major: major, minor: minor), identifier: identifier)
    }
}

/// A beacon found while ranging (never, in a page; the type is for apps that model one).
open class CLBeacon: NSObject, @unchecked Sendable {
    public let uuid: UUID
    public let major: NSNumber
    public let minor: NSNumber
    public let proximity: CLProximity
    public let accuracy: CLLocationAccuracy
    public let rssi: Int
    public let timestamp: Date
    package init(uuid: UUID, major: CLBeaconMajorValue, minor: CLBeaconMinorValue, proximity: CLProximity = .unknown,
                 accuracy: CLLocationAccuracy = -1, rssi: Int = 0, timestamp: Date = Date()) {
        self.uuid = uuid
        self.major = NSNumber(value: major)
        self.minor = NSNumber(value: minor)
        self.proximity = proximity
        self.accuracy = accuracy
        self.rssi = rssi
        self.timestamp = timestamp
    }
}

// MARK: - Visits

/// A place the user stayed (never delivered in a page; the type is for apps that model one).
open class CLVisit: NSObject, @unchecked Sendable {
    public let arrivalDate: Date
    public let departureDate: Date
    public let coordinate: CLLocationCoordinate2D
    public let horizontalAccuracy: CLLocationAccuracy
    package init(arrivalDate: Date = .distantPast, departureDate: Date = .distantFuture, coordinate: CLLocationCoordinate2D,
                 horizontalAccuracy: CLLocationAccuracy = 0) {
        self.arrivalDate = arrivalDate
        self.departureDate = departureDate
        self.coordinate = coordinate
        self.horizontalAccuracy = horizontalAccuracy
    }
}
