// CoreMotion over a stand-in for the browser's motion events: the conversions from the
// browser's readings (m/s², degrees) to CoreMotion's (g, radians), the update interval, the
// pull-style properties, stopping, and the sensors a browser does not have.
#if !os(WASI)
import CoreMotion
import CoreMotionHost
import Foundation
import Testing

/// Plays the browser: has sensors, keeps the delivery and counts the stops.
@MainActor
private enum StandInSensors {
    nonisolated(unsafe) static var deliver: ((_CoreMotionHost.Sample) -> Void)?
    nonisolated(unsafe) static var starts = 0
    nonisolated(unsafe) static var stops = 0

    static func install() {
        deliver = nil
        starts = 0
        stops = 0
        _CoreMotionHost.available = { true }
        _CoreMotionHost.start = { deliver in
            StandInSensors.deliver = deliver
            StandInSensors.starts += 1
            return { StandInSensors.stops += 1; StandInSensors.deliver = nil }
        }
    }

    static func send(_ sample: _CoreMotionHost.Sample) { deliver?(sample) }
}

private func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }

@Suite(.serialized) @MainActor
struct CoreMotionTests {
    init() {
        _CoreMotionHost.available = nil
        _CoreMotionHost.start = nil
    }

    @Test func aComputerHasNoMotionSensors() {
        let manager = CMMotionManager()
        #expect(!manager.isAccelerometerAvailable && !manager.isGyroAvailable && !manager.isDeviceMotionAvailable)
        #expect(!manager.isMagnetometerAvailable)
        manager.startAccelerometerUpdates()
        manager.startDeviceMotionUpdates()
        #expect(!manager.isAccelerometerActive && !manager.isDeviceMotionActive)
        #expect(manager.accelerometerData == nil && manager.deviceMotion == nil)
        #expect(CMMotionManager.availableAttitudeReferenceFrames().isEmpty)
    }

    @Test func theAccelerometerReadsWhatTheDeviceFeelsInG() {
        StandInSensors.install()
        let manager = CMMotionManager()
        #expect(manager.isAccelerometerAvailable)
        var readings: [CMAcceleration] = []
        manager.startAccelerometerUpdates(to: .main) { data, error in
            #expect(error == nil)
            if let data { readings.append(data.acceleration) }
        }
        #expect(manager.isAccelerometerActive && StandInSensors.starts == 1)
        // Lying flat, face up: the browser reports +g up the z axis; Apple's accelerometer reads -1.
        StandInSensors.send(.init(accelerationIncludingGravity: (x: 0, y: 0, z: 9.80665), timestamp: 1))
        #expect(readings.count == 1)
        #expect(near(readings[0].x, 0) && near(readings[0].y, 0) && near(readings[0].z, -1))
        #expect(manager.accelerometerData.map { near($0.acceleration.z, -1) && $0.timestamp == 1 } == true)
    }

    @Test func updatesComeNoFasterThanTheInterval() {
        StandInSensors.install()
        let manager = CMMotionManager()
        manager.accelerometerUpdateInterval = 0.1
        var count = 0
        manager.startAccelerometerUpdates(to: .main) { _, _ in count += 1 }
        for t in [0.0, 0.02, 0.05, 0.1, 0.13, 0.2] {
            StandInSensors.send(.init(accelerationIncludingGravity: (x: 0, y: 0, z: 9.8), timestamp: t))
        }
        #expect(count == 3)
    }

    @Test func deviceMotionSplitsGravityFromThePersonsAcceleration() throws {
        StandInSensors.install()
        let manager = CMMotionManager()
        manager.startDeviceMotionUpdates()
        #expect(manager.isDeviceMotionActive)
        // Upright in portrait (beta 90°), pushed right at 1 m/s², turning 180°/s about x.
        StandInSensors.send(.init(accelerationIncludingGravity: (x: 1, y: 9.80665, z: 0), acceleration: (x: 1, y: 0, z: 0),
                                  rotationRate: (alpha: 0, beta: 180, gamma: 0), orientation: (alpha: 0, beta: 90, gamma: 0),
                                  timestamp: 2))
        let motion = try #require(manager.deviceMotion)
        #expect(near(motion.gravity.x, 0) && near(motion.gravity.y, -1) && near(motion.gravity.z, 0))
        #expect(near(motion.userAcceleration.x, -1 / 9.80665) && near(motion.userAcceleration.y, 0))
        #expect(near(motion.rotationRate.x, .pi) && near(motion.rotationRate.y, 0) && near(motion.rotationRate.z, 0))
        #expect(near(motion.attitude.pitch, .pi / 2) && near(motion.attitude.roll, 0) && near(motion.attitude.yaw, 0))
        #expect(motion.heading == -1)
        // OscarWeather's tilt: gravity alone, from the orientation, when there is no acceleration.
        StandInSensors.send(.init(orientation: (alpha: 0, beta: 0, gamma: 0), timestamp: 3))
        let flat = try #require(manager.deviceMotion)
        #expect(near(flat.gravity.x, 0) && near(flat.gravity.y, 0) && near(flat.gravity.z, -1))
    }

    @Test func theAttitudesMatrixAndQuaternionAgree() {
        StandInSensors.install()
        let manager = CMMotionManager()
        manager.startDeviceMotionUpdates()
        StandInSensors.send(.init(accelerationIncludingGravity: (x: 0, y: 0, z: 9.8), orientation: (alpha: 0, beta: 0, gamma: 0), timestamp: 1))
        let level = manager.deviceMotion!.attitude
        let q = level.quaternion
        #expect(near(q.x, 0) && near(q.y, 0) && near(q.z, 0) && near(q.w, 1))
        StandInSensors.send(.init(accelerationIncludingGravity: (x: 0, y: 0, z: 9.8), orientation: (alpha: 90, beta: 0, gamma: 0), timestamp: 2))
        let turned = manager.deviceMotion!.attitude
        let half = (0.5).squareRoot()
        #expect(near(turned.quaternion.z, half) && near(turned.quaternion.w, half))
        #expect(near(turned.rotationMatrix.m12, -1) && near(turned.rotationMatrix.m21, 1))
        turned.multiply(byInverseOf: level)
        #expect(near(turned.yaw, .pi / 2))
    }

    @Test func stoppingEveryUpdateStopsTheBrowsersReadings() {
        StandInSensors.install()
        let manager = CMMotionManager()
        manager.startAccelerometerUpdates()
        manager.startGyroUpdates()
        #expect(StandInSensors.starts == 1)
        StandInSensors.send(.init(accelerationIncludingGravity: (x: 0, y: 0, z: 9.8), rotationRate: (alpha: 0, beta: 0, gamma: 90), timestamp: 1))
        #expect(manager.gyroData.map { near($0.rotationRate.y, .pi / 2) } == true)
        manager.stopAccelerometerUpdates()
        #expect(StandInSensors.stops == 0 && !manager.isAccelerometerActive && manager.accelerometerData == nil)
        manager.stopGyroUpdates()
        #expect(StandInSensors.stops == 1 && !manager.isGyroActive)
    }

    @Test func whatABrowserCannotMeasureIsUnavailable() {
        StandInSensors.install()
        let manager = CMMotionManager()
        var failure: (any Error)?
        manager.startDeviceMotionUpdates(using: .xTrueNorthZVertical, to: .main) { _, error in failure = error }
        #expect(!manager.isDeviceMotionActive)
        #expect(failure.map { ($0 as NSError).code } == Int(CMErrorTrueNorthNotAvailable.rawValue))
        #expect(!CMAltimeter.isRelativeAltitudeAvailable() && !CMPedometer.isStepCountingAvailable() && !CMMotionActivityManager.isActivityAvailable())
        var stepsError: (any Error)?
        CMPedometer().queryPedometerData(from: Date(), to: Date()) { _, error in stepsError = error }
        #expect(stepsError.map { ($0 as NSError).domain } == CMErrorDomain)
        var eventError: (any Error)?
        #expect(!CMPedometer.isPedometerEventTrackingAvailable())
        CMPedometer().startEventUpdates { event, error in
            #expect(event == nil)
            eventError = error
        }
        #expect(eventError.map { ($0 as NSError).code } == Int(CMErrorNotAvailable.rawValue))
        #expect(CMPedometerEventType.resume.rawValue == 1)
    }

    /// Fall detection is a watch's: a page, like a phone, has none, and the app is told so.
    @Test func noFallsAreDetected() {
        final class Listener: CMFallDetectionDelegate {}
        let manager = CMFallDetectionManager()
        let listener = Listener()
        manager.delegate = listener
        #expect(!CMFallDetectionManager.isAvailable)
        var status: CMAuthorizationStatus?
        manager.requestAuthorization { status = $0 }
        #expect(status == .restricted)
        #expect(manager.delegate === listener)
        #expect(CMFallDetectionEvent.UserResolution.unresponsive.rawValue == 3)
    }
}
#endif
