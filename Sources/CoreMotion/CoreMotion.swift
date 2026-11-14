// CoreMotion on the web: `CMMotionManager` over the browser's `devicemotion` and
// `deviceorientation` events (through CoreMotionHost). The accelerometer reads the
// acceleration the device feels in g, as Apple's does (lying flat it reads z = -1); device
// motion splits it into gravity and the person's acceleration, adds the rotation rate in radians
// per second and the attitude from the browser's orientation angles. Updates arrive as often
// as the browser fires its events (about 60 a second) and no more often than the update
// interval asks. A computer has no motion sensors, so there every sensor reads unavailable, as
// on a device without them. The magnetometer, the altimeter, the pedometer and activity
// recognition have nothing behind them in a browser and read unavailable everywhere, as does a
// watch's fall detection.
#if os(WASI)
import WebFoundation
import WASILibc
#else
import Foundation
#endif
import CoreMotionHost

// MARK: - Values

/// Acceleration in g along the device's axes.
public struct CMAcceleration: Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double
    public init() { x = 0; y = 0; z = 0 }
    public init(x: Double, y: Double, z: Double) { self.x = x; self.y = y; self.z = z }
}

/// Rotation in radians per second about the device's axes.
public struct CMRotationRate: Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double
    public init() { x = 0; y = 0; z = 0 }
    public init(x: Double, y: Double, z: Double) { self.x = x; self.y = y; self.z = z }
}

/// A magnetic field in microteslas.
public struct CMMagneticField: Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double
    public init() { x = 0; y = 0; z = 0 }
    public init(x: Double, y: Double, z: Double) { self.x = x; self.y = y; self.z = z }
}

/// How well calibrated a magnetic field reading is.
public enum CMMagneticFieldCalibrationAccuracy: Int32, Hashable, Sendable {
    case uncalibrated = -1
    case low = 0
    case medium = 1
    case high = 2
}

/// A magnetic field with its calibration (uncalibrated here: there is no magnetometer).
public struct CMCalibratedMagneticField: Hashable, Sendable {
    public var field: CMMagneticField
    public var accuracy: CMMagneticFieldCalibrationAccuracy
    public init() { field = CMMagneticField(); accuracy = .uncalibrated }
    public init(field: CMMagneticField, accuracy: CMMagneticFieldCalibrationAccuracy) { self.field = field; self.accuracy = accuracy }
}

/// A rotation as a unit quaternion.
public struct CMQuaternion: Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double
    public var w: Double
    public init() { x = 0; y = 0; z = 0; w = 1 }
    public init(x: Double, y: Double, z: Double, w: Double) { self.x = x; self.y = y; self.z = z; self.w = w }
}

/// A rotation as a 3 × 3 matrix.
public struct CMRotationMatrix: Hashable, Sendable {
    public var m11: Double, m12: Double, m13: Double
    public var m21: Double, m22: Double, m23: Double
    public var m31: Double, m32: Double, m33: Double
    public init() { (m11, m12, m13, m21, m22, m23, m31, m32, m33) = (1, 0, 0, 0, 1, 0, 0, 0, 1) }
    public init(m11: Double, m12: Double, m13: Double, m21: Double, m22: Double, m23: Double, m31: Double, m32: Double, m33: Double) {
        (self.m11, self.m12, self.m13, self.m21, self.m22, self.m23, self.m31, self.m32, self.m33) = (m11, m12, m13, m21, m22, m23, m31, m32, m33)
    }
}

/// The reference frames an attitude can be measured against.
public struct CMAttitudeReferenceFrame: OptionSet, Hashable, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let xArbitraryZVertical = CMAttitudeReferenceFrame(rawValue: 1 << 0)
    public static let xArbitraryCorrectedZVertical = CMAttitudeReferenceFrame(rawValue: 1 << 1)
    public static let xMagneticNorthZVertical = CMAttitudeReferenceFrame(rawValue: 1 << 2)
    public static let xTrueNorthZVertical = CMAttitudeReferenceFrame(rawValue: 1 << 3)
}

// MARK: - Readings

/// A reading at a time (seconds since the page loaded).
open class CMLogItem: NSObject, @unchecked Sendable {
    public let timestamp: TimeInterval
    package init(timestamp: TimeInterval) {
        self.timestamp = timestamp
        super.init()
    }
}

/// An accelerometer reading.
open class CMAccelerometerData: CMLogItem, @unchecked Sendable {
    public let acceleration: CMAcceleration
    package init(acceleration: CMAcceleration, timestamp: TimeInterval) {
        self.acceleration = acceleration
        super.init(timestamp: timestamp)
    }
}

/// A gyroscope reading.
open class CMGyroData: CMLogItem, @unchecked Sendable {
    public let rotationRate: CMRotationRate
    package init(rotationRate: CMRotationRate, timestamp: TimeInterval) {
        self.rotationRate = rotationRate
        super.init(timestamp: timestamp)
    }
}

/// A magnetometer reading.
open class CMMagnetometerData: CMLogItem, @unchecked Sendable {
    public let magneticField: CMMagneticField
    package init(magneticField: CMMagneticField, timestamp: TimeInterval) {
        self.magneticField = magneticField
        super.init(timestamp: timestamp)
    }
}

/// The device's orientation: Euler angles in radians, a matrix and a quaternion.
open class CMAttitude: NSObject, @unchecked Sendable {
    public private(set) var roll: Double
    public private(set) var pitch: Double
    public private(set) var yaw: Double

    package init(roll: Double, pitch: Double, yaw: Double) {
        self.roll = roll
        self.pitch = pitch
        self.yaw = yaw
        super.init()
    }

    /// The rotation from the reference frame to the device: about z by the yaw, then x by the
    /// pitch, then y by the roll (the browser's order).
    open var rotationMatrix: CMRotationMatrix {
        let (cz, sz) = (cos(yaw), sin(yaw)), (cx, sx) = (cos(pitch), sin(pitch)), (cy, sy) = (cos(roll), sin(roll))
        return CMRotationMatrix(m11: cz * cy - sz * sx * sy, m12: -cx * sz, m13: cy * sz * sx + cz * sy,
                                m21: cy * sz + cz * sx * sy, m22: cz * cx, m23: sz * sy - cz * cy * sx,
                                m31: -cx * sy, m32: sx, m33: cx * cy)
    }

    open var quaternion: CMQuaternion {
        let m = rotationMatrix
        let trace = m.m11 + m.m22 + m.m33
        if trace > 0 {
            let s = (trace + 1).squareRoot() * 2
            return CMQuaternion(x: (m.m32 - m.m23) / s, y: (m.m13 - m.m31) / s, z: (m.m21 - m.m12) / s, w: s / 4)
        } else if m.m11 > m.m22 && m.m11 > m.m33 {
            let s = (1 + m.m11 - m.m22 - m.m33).squareRoot() * 2
            return CMQuaternion(x: s / 4, y: (m.m12 + m.m21) / s, z: (m.m13 + m.m31) / s, w: (m.m32 - m.m23) / s)
        } else if m.m22 > m.m33 {
            let s = (1 + m.m22 - m.m11 - m.m33).squareRoot() * 2
            return CMQuaternion(x: (m.m12 + m.m21) / s, y: s / 4, z: (m.m23 + m.m32) / s, w: (m.m13 - m.m31) / s)
        } else {
            let s = (1 + m.m33 - m.m11 - m.m22).squareRoot() * 2
            return CMQuaternion(x: (m.m13 + m.m31) / s, y: (m.m23 + m.m32) / s, z: s / 4, w: (m.m21 - m.m12) / s)
        }
    }

    /// Makes this attitude relative to `attitude` (the change since then).
    open func multiply(byInverseOf attitude: CMAttitude) {
        roll -= attitude.roll
        pitch -= attitude.pitch
        yaw = Self.wrapped(yaw - attitude.yaw)
    }

    static func wrapped(_ angle: Double) -> Double {
        var a = angle.truncatingRemainder(dividingBy: 2 * .pi)
        if a > .pi { a -= 2 * .pi }
        if a < -.pi { a += 2 * .pi }
        return a
    }
}

/// The device's motion: its attitude, rotation, gravity and the person's acceleration.
open class CMDeviceMotion: CMLogItem, @unchecked Sendable {
    public let attitude: CMAttitude
    public let rotationRate: CMRotationRate
    public let gravity: CMAcceleration
    public let userAcceleration: CMAcceleration
    public let magneticField: CMCalibratedMagneticField
    /// Degrees from north, or -1 when the reference frame has no north (here always).
    public let heading: Double
    public let sensorLocation: SensorLocation

    /// Where the sensors that measured the motion are (the device itself, here).
    public enum SensorLocation: Int, Hashable, Sendable {
        case `default` = 0
        case headphoneLeft = 1
        case headphoneRight = 2
    }

    package init(attitude: CMAttitude, rotationRate: CMRotationRate, gravity: CMAcceleration, userAcceleration: CMAcceleration, timestamp: TimeInterval) {
        self.attitude = attitude
        self.rotationRate = rotationRate
        self.gravity = gravity
        self.userAcceleration = userAcceleration
        magneticField = CMCalibratedMagneticField()
        heading = -1
        sensorLocation = .default
        super.init(timestamp: timestamp)
    }
}

// MARK: - Errors

/// The domain of CoreMotion's errors.
public let CMErrorDomain = "CMErrorDomain"

/// CoreMotion's error codes.
public struct CMError: RawRepresentable, Hashable, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public init(_ rawValue: UInt32) { self.rawValue = rawValue }
}

public let CMErrorNULL = CMError(100)
public let CMErrorDeviceRequiresMovement = CMError(101)
public let CMErrorTrueNorthNotAvailable = CMError(102)
public let CMErrorUnknown = CMError(103)
public let CMErrorMotionActivityNotAvailable = CMError(104)
public let CMErrorMotionActivityNotAuthorized = CMError(105)
public let CMErrorMotionActivityNotEntitled = CMError(106)
public let CMErrorInvalidParameter = CMError(107)
public let CMErrorInvalidAction = CMError(108)
public let CMErrorNotAvailable = CMError(109)
public let CMErrorNotEntitled = CMError(110)
public let CMErrorNotAuthorized = CMError(111)
public let CMErrorNilData = CMError(112)
public let CMErrorSize = CMError(113)

/// The error a sensor with nothing behind it reports.
func _notAvailable() -> any Error { NSError(domain: CMErrorDomain, code: Int(CMErrorNotAvailable.rawValue)) }

// MARK: - The motion manager

public typealias CMAccelerometerHandler = (CMAccelerometerData?, (any Error)?) -> Void
public typealias CMGyroHandler = (CMGyroData?, (any Error)?) -> Void
public typealias CMDeviceMotionHandler = (CMDeviceMotion?, (any Error)?) -> Void
public typealias CMMagnetometerHandler = (CMMagnetometerData?, (any Error)?) -> Void

/// Whether the app may read motion and fitness data.
public enum CMAuthorizationStatus: Int, Hashable, Sendable {
    case notDetermined = 0
    case restricted = 1
    case denied = 2
    case authorized = 3
}

/// Reads the accelerometer, the gyroscope and device motion.
open class CMMotionManager: NSObject, @unchecked Sendable {
    /// Seconds between the updates each sensor delivers (at least the browser's own interval).
    open var accelerometerUpdateInterval: TimeInterval = 0.01
    open var gyroUpdateInterval: TimeInterval = 0.01
    open var magnetometerUpdateInterval: TimeInterval = 0.01
    open var deviceMotionUpdateInterval: TimeInterval = 0.01
    open var showsDeviceMovementDisplay = false

    /// The latest readings while the sensor runs.
    open private(set) var accelerometerData: CMAccelerometerData?
    open private(set) var gyroData: CMGyroData?
    open private(set) var magnetometerData: CMMagnetometerData?
    open private(set) var deviceMotion: CMDeviceMotion?
    open private(set) var attitudeReferenceFrame: CMAttitudeReferenceFrame = .xArbitraryZVertical

    private struct Feed {
        var handler: ((_CoreMotionHost.Sample) -> Void)?
        var last: Double = -.infinity
    }
    private var accelerometer: Feed?
    private var gyro: Feed?
    private var motion: Feed?
    private var stopHost: (() -> Void)?

    public override init() { super.init() }

    private static var sensors: Bool { _CoreMotionHost.available?() ?? false }
    open var isAccelerometerAvailable: Bool { Self.sensors }
    open var isGyroAvailable: Bool { Self.sensors }
    open var isDeviceMotionAvailable: Bool { Self.sensors }
    /// A browser reports no magnetic field.
    open var isMagnetometerAvailable: Bool { false }

    open var isAccelerometerActive: Bool { accelerometer != nil }
    open var isGyroActive: Bool { gyro != nil }
    open var isDeviceMotionActive: Bool { motion != nil }
    open var isMagnetometerActive: Bool { false }

    /// The reference frames device motion can use: an arbitrary heading with z vertical.
    open class func availableAttitudeReferenceFrames() -> CMAttitudeReferenceFrame {
        sensors ? [.xArbitraryZVertical, .xArbitraryCorrectedZVertical] : []
    }

    open class func authorizationStatus() -> CMAuthorizationStatus { .authorized }

    // Accelerometer

    open func startAccelerometerUpdates() { startAccelerometer(nil, nil) }
    open func startAccelerometerUpdates(to queue: OperationQueue, withHandler handler: @escaping CMAccelerometerHandler) {
        startAccelerometer(queue, handler)
    }
    open func stopAccelerometerUpdates() { accelerometer = nil; accelerometerData = nil; stopIfIdle() }

    private func startAccelerometer(_ queue: OperationQueue?, _ handler: CMAccelerometerHandler?) {
        guard Self.sensors else { return }
        accelerometer = Feed(handler: { [unowned self] sample in
            guard let reading = Self.felt(sample) else { return }
            guard self.due(&self.accelerometer, sample, every: self.accelerometerUpdateInterval) else { return }
            let data = CMAccelerometerData(acceleration: reading, timestamp: sample.timestamp)
            self.accelerometerData = data
            Self.call(queue, handler, data)
        })
        startHost()
    }

    // Gyroscope

    open func startGyroUpdates() { startGyro(nil, nil) }
    open func startGyroUpdates(to queue: OperationQueue, withHandler handler: @escaping CMGyroHandler) { startGyro(queue, handler) }
    open func stopGyroUpdates() { gyro = nil; gyroData = nil; stopIfIdle() }

    private func startGyro(_ queue: OperationQueue?, _ handler: CMGyroHandler?) {
        guard Self.sensors else { return }
        gyro = Feed(handler: { [unowned self] sample in
            guard let rate = Self.rotation(sample) else { return }
            guard self.due(&self.gyro, sample, every: self.gyroUpdateInterval) else { return }
            let data = CMGyroData(rotationRate: rate, timestamp: sample.timestamp)
            self.gyroData = data
            Self.call(queue, handler, data)
        })
        startHost()
    }

    // Magnetometer (nothing behind it)

    open func startMagnetometerUpdates() {}
    open func startMagnetometerUpdates(to queue: OperationQueue, withHandler handler: @escaping CMMagnetometerHandler) {
        Self.call(queue, handler, nil as CMMagnetometerData?, _notAvailable())
    }
    open func stopMagnetometerUpdates() {}

    // Device motion

    open func startDeviceMotionUpdates() { startMotion(.xArbitraryZVertical, nil, nil) }
    open func startDeviceMotionUpdates(to queue: OperationQueue, withHandler handler: @escaping CMDeviceMotionHandler) {
        startMotion(.xArbitraryZVertical, queue, handler)
    }
    open func startDeviceMotionUpdates(using referenceFrame: CMAttitudeReferenceFrame) { startMotion(referenceFrame, nil, nil) }
    open func startDeviceMotionUpdates(using referenceFrame: CMAttitudeReferenceFrame, to queue: OperationQueue,
                                       withHandler handler: @escaping CMDeviceMotionHandler) {
        startMotion(referenceFrame, queue, handler)
    }
    open func stopDeviceMotionUpdates() { motion = nil; deviceMotion = nil; stopIfIdle() }

    private func startMotion(_ frame: CMAttitudeReferenceFrame, _ queue: OperationQueue?, _ handler: CMDeviceMotionHandler?) {
        // A north-referenced frame needs the magnetometer.
        if !frame.isDisjoint(with: [.xMagneticNorthZVertical, .xTrueNorthZVertical]) {
            if let handler {
                Self.call(queue, handler, nil as CMDeviceMotion?,
                          NSError(domain: CMErrorDomain, code: Int(CMErrorTrueNorthNotAvailable.rawValue)))
            }
            return
        }
        guard Self.sensors else { return }
        attitudeReferenceFrame = frame
        motion = Feed(handler: { [unowned self] sample in
            guard let reading = Self.deviceMotion(sample) else { return }
            guard self.due(&self.motion, sample, every: self.deviceMotionUpdateInterval) else { return }
            self.deviceMotion = reading
            Self.call(queue, handler, reading)
        })
        startHost()
    }

    // The browser's readings

    private func startHost() {
        guard stopHost == nil, Self.sensors, let start = _CoreMotionHost.start else { return }
        weak let manager = self
        stopHost = start { sample in
            guard let manager else { return }
            // Copied first: a handler may stop its own or another sensor.
            let feeds = [manager.accelerometer?.handler, manager.gyro?.handler, manager.motion?.handler]
            for feed in feeds { feed?(sample) }
        }
    }

    private func stopIfIdle() {
        guard accelerometer == nil, gyro == nil, motion == nil else { return }
        stopHost?()
        stopHost = nil
    }

    /// Whether a reading is at least `interval` after the feed's last one (and marks it taken).
    private func due(_ feed: inout Feed?, _ sample: _CoreMotionHost.Sample, every interval: TimeInterval) -> Bool {
        guard let last = feed?.last else { return false }
        // A little slack, so a 60 Hz event stream meets a 1/60 s interval.
        guard sample.timestamp - last >= interval * 0.9 else { return false }
        feed?.last = sample.timestamp
        return true
    }

    /// Calls `handler`: at once on the main queue (the browser's events arrive there), through
    /// any other queue.
    static func call<Data>(_ queue: OperationQueue?, _ handler: ((Data?, (any Error)?) -> Void)?, _ data: Data?,
                           _ error: (any Error)? = nil) {
        guard let handler else { return }
        guard let queue, queue !== OperationQueue.main else {
            handler(data, error)
            return
        }
        nonisolated(unsafe) let run = handler
        nonisolated(unsafe) let reading = data
        queue.addOperation { run(reading, error) }
    }

    // MARK: Converting the browser's readings

    /// Standard gravity, in metres per second squared.
    static let g = 9.80665

    /// What the accelerometer feels, in g (the browser reports the device's acceleration, which
    /// points the other way: up, at rest).
    static func felt(_ sample: _CoreMotionHost.Sample) -> CMAcceleration? {
        if let a = sample.accelerationIncludingGravity {
            return CMAcceleration(x: -a.x / g, y: -a.y / g, z: -a.z / g)
        }
        guard let gravity = gravity(sample) else { return nil }
        let user = sample.acceleration.map { CMAcceleration(x: -$0.x / g, y: -$0.y / g, z: -$0.z / g) } ?? CMAcceleration()
        return CMAcceleration(x: gravity.x + user.x, y: gravity.y + user.y, z: gravity.z + user.z)
    }

    /// Gravity in g, pointing down: from the acceleration with and without it, else from the
    /// orientation's tilt.
    static func gravity(_ sample: _CoreMotionHost.Sample) -> CMAcceleration? {
        if let all = sample.accelerationIncludingGravity {
            let moving = sample.acceleration ?? (0, 0, 0)
            return CMAcceleration(x: -(all.x - moving.x) / g, y: -(all.y - moving.y) / g, z: -(all.z - moving.z) / g)
        }
        guard let o = sample.orientation else { return nil }
        let beta = o.beta * .pi / 180, gamma = o.gamma * .pi / 180
        return CMAcceleration(x: cos(beta) * sin(gamma), y: -sin(beta), z: -cos(beta) * cos(gamma))
    }

    static func rotation(_ sample: _CoreMotionHost.Sample) -> CMRotationRate? {
        guard let r = sample.rotationRate else { return nil }
        let k = Double.pi / 180
        return CMRotationRate(x: r.beta * k, y: r.gamma * k, z: r.alpha * k)
    }

    static func deviceMotion(_ sample: _CoreMotionHost.Sample) -> CMDeviceMotion? {
        guard let gravity = gravity(sample) else { return nil }
        let user: CMAcceleration
        if let a = sample.acceleration {
            user = CMAcceleration(x: -a.x / g, y: -a.y / g, z: -a.z / g)
        } else if let felt = felt(sample) {
            user = CMAcceleration(x: felt.x - gravity.x, y: felt.y - gravity.y, z: felt.z - gravity.z)
        } else {
            user = CMAcceleration()
        }
        let attitude: CMAttitude
        if let o = sample.orientation {
            let k = Double.pi / 180
            attitude = CMAttitude(roll: o.gamma * k, pitch: o.beta * k, yaw: CMAttitude.wrapped(o.alpha * k))
        } else {
            // The tilt from gravity alone (no heading).
            attitude = CMAttitude(roll: atan2(gravity.x, -gravity.z), pitch: atan2(-gravity.y, (gravity.x * gravity.x + gravity.z * gravity.z).squareRoot()), yaw: 0)
        }
        return CMDeviceMotion(attitude: attitude, rotationRate: rotation(sample) ?? CMRotationRate(), gravity: gravity,
                              userAcceleration: user, timestamp: sample.timestamp)
    }
}

// MARK: - Sensors a browser does not have

/// Relative altitude and air pressure: unavailable in a browser.
open class CMAltimeter: NSObject, @unchecked Sendable {
    public override init() { super.init() }
    open class func isRelativeAltitudeAvailable() -> Bool { false }
    open class func isAbsoluteAltitudeAvailable() -> Bool { false }
    open class func authorizationStatus() -> CMAuthorizationStatus { .restricted }
    open func startRelativeAltitudeUpdates(to queue: OperationQueue, withHandler handler: @escaping (CMAltitudeData?, (any Error)?) -> Void) {
        CMMotionManager.call(queue, handler, nil as CMAltitudeData?, _notAvailable())
    }
    open func stopRelativeAltitudeUpdates() {}
}

/// A change in altitude and the air pressure.
open class CMAltitudeData: CMLogItem, @unchecked Sendable {
    public let relativeAltitude: NSNumber
    public let pressure: NSNumber
    package init(relativeAltitude: Double, pressure: Double, timestamp: TimeInterval) {
        self.relativeAltitude = NSNumber(value: relativeAltitude)
        self.pressure = NSNumber(value: pressure)
        super.init(timestamp: timestamp)
    }
}

/// Steps and distance walked: unavailable in a browser.
open class CMPedometer: NSObject, @unchecked Sendable {
    public override init() { super.init() }
    open class func isStepCountingAvailable() -> Bool { false }
    open class func isDistanceAvailable() -> Bool { false }
    open class func isFloorCountingAvailable() -> Bool { false }
    open class func isPaceAvailable() -> Bool { false }
    open class func isCadenceAvailable() -> Bool { false }
    open class func authorizationStatus() -> CMAuthorizationStatus { .restricted }
    open func queryPedometerData(from start: Date, to end: Date, withHandler handler: @escaping (CMPedometerData?, (any Error)?) -> Void) {
        handler(nil, _notAvailable())
    }
    open func startUpdates(from start: Date, withHandler handler: @escaping (CMPedometerData?, (any Error)?) -> Void) {
        handler(nil, _notAvailable())
    }
    open func stopUpdates() {}
    /// Whether the pedometer reports when walking pauses and resumes (never in a browser).
    open class func isPedometerEventTrackingAvailable() -> Bool { false }
    open func startEventUpdates(handler: @escaping CMPedometerEventHandler) {
        handler(nil, _notAvailable())
    }
    open func stopEventUpdates() {}
}

public typealias CMPedometerHandler = (CMPedometerData?, (any Error)?) -> Void
public typealias CMPedometerEventHandler = (CMPedometerEvent?, (any Error)?) -> Void

/// Steps and distance over a period.
open class CMPedometerData: NSObject, @unchecked Sendable {
    public let startDate: Date
    public let endDate: Date
    public let numberOfSteps: NSNumber
    public let distance: NSNumber?
    public let floorsAscended: NSNumber? = nil
    public let floorsDescended: NSNumber? = nil
    /// Seconds per metre.
    public let currentPace: NSNumber? = nil
    /// Steps per second.
    public let currentCadence: NSNumber? = nil
    public let averageActivePace: NSNumber? = nil
    package init(startDate: Date, endDate: Date, numberOfSteps: Int, distance: Double?) {
        self.startDate = startDate
        self.endDate = endDate
        self.numberOfSteps = NSNumber(value: numberOfSteps)
        self.distance = distance.map { NSNumber(value: $0) }
        super.init()
    }
}

/// Whether walking paused or resumed.
public enum CMPedometerEventType: Int, Hashable, Sendable {
    case pause = 0
    case resume = 1
}

/// A pause or resumption of walking.
open class CMPedometerEvent: NSObject, @unchecked Sendable {
    public let date: Date
    public let type: CMPedometerEventType
    package init(date: Date, type: CMPedometerEventType) {
        self.date = date
        self.type = type
        super.init()
    }
}

// MARK: - Fall detection (a watch's; never available in a browser)

/// Reports the falls a watch detects: unavailable in a browser, as on a phone.
open class CMFallDetectionManager: NSObject, @unchecked Sendable {
    public override init() { super.init() }
    /// Whether the device detects falls.
    open class var isAvailable: Bool { false }
    open var authorizationStatus: CMAuthorizationStatus { .restricted }
    open weak var delegate: (any CMFallDetectionDelegate)?
    /// Asks the person to let the app hear of falls; answers with the status (restricted here).
    open func requestAuthorization(handler: @escaping (CMAuthorizationStatus) -> Void) {
        handler(authorizationStatus)
    }
}

/// A fall the watch detected, and how the person answered its alert.
open class CMFallDetectionEvent: NSObject, @unchecked Sendable {
    public enum UserResolution: Int, Hashable, Sendable {
        case confirmed = 0
        case dismissed = 1
        case rejected = 2
        case unresponsive = 3
    }
    public let date: Date
    public let resolution: UserResolution
    package init(date: Date, resolution: UserResolution) {
        self.date = date
        self.resolution = resolution
        super.init()
    }
}

/// What hears of falls and of changes to the app's authorization.
public protocol CMFallDetectionDelegate: AnyObject {
    func fallDetectionManager(_ fallDetectionManager: CMFallDetectionManager, didDetect event: CMFallDetectionEvent,
                              completionHandler handler: @escaping () -> Void)
    func fallDetectionManagerDidChangeAuthorization(_ fallDetectionManager: CMFallDetectionManager)
}

extension CMFallDetectionDelegate {
    public func fallDetectionManager(_ fallDetectionManager: CMFallDetectionManager, didDetect event: CMFallDetectionEvent,
                                     completionHandler handler: @escaping () -> Void) { handler() }
    public func fallDetectionManagerDidChangeAuthorization(_ fallDetectionManager: CMFallDetectionManager) {}
}

/// Walking, running, driving: unavailable in a browser.
open class CMMotionActivityManager: NSObject, @unchecked Sendable {
    public override init() { super.init() }
    open class func isActivityAvailable() -> Bool { false }
    open class func authorizationStatus() -> CMAuthorizationStatus { .restricted }
    open func startActivityUpdates(to queue: OperationQueue, withHandler handler: @escaping (CMMotionActivity?) -> Void) {}
    open func stopActivityUpdates() {}
    open func queryActivityStarting(from start: Date, to end: Date, to queue: OperationQueue,
                                    withHandler handler: @escaping ([CMMotionActivity]?, (any Error)?) -> Void) {
        CMMotionManager.call(queue, handler, nil as [CMMotionActivity]?,
                             NSError(domain: CMErrorDomain, code: Int(CMErrorMotionActivityNotAvailable.rawValue)))
    }
}

/// What the person was doing.
open class CMMotionActivity: CMLogItem, @unchecked Sendable {
    public enum Confidence: Int, Hashable, Sendable { case low = 0, medium, high }
    public let confidence: Confidence = .low
    public let startDate = Date()
    public let unknown = true
    public let stationary = false
    public let walking = false
    public let running = false
    public let automotive = false
    public let cycling = false
}

public typealias CMMotionActivityConfidence = CMMotionActivity.Confidence
