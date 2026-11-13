// The browser's motion sensors as CoreMotion's motion manager reads them: the hook
// SwiftUIWebCanvas installs (MotionHost.swift) and CoreMotion uses. A module of its own,
// depending on nothing, so installing the hook links only this into an app that never makes a
// motion manager (decision 0006).

public enum _CoreMotionHost {
    /// One reading, as the browser's `devicemotion` and `deviceorientation` events report it
    /// (the device's axes: x to the right, y up the screen, z out of it).
    public struct Sample: Sendable {
        /// Metres per second squared, gravity included (`accelerationIncludingGravity`).
        public var accelerationIncludingGravity: (x: Double, y: Double, z: Double)?
        /// Metres per second squared, gravity removed (`acceleration`).
        public var acceleration: (x: Double, y: Double, z: Double)?
        /// Degrees per second about z, x and y (`rotationRate`'s alpha, beta, gamma).
        public var rotationRate: (alpha: Double, beta: Double, gamma: Double)?
        /// Degrees: the device's orientation (`deviceorientation`'s alpha, beta, gamma).
        public var orientation: (alpha: Double, beta: Double, gamma: Double)?
        /// Seconds since the page loaded.
        public var timestamp: Double

        public init(accelerationIncludingGravity: (x: Double, y: Double, z: Double)? = nil,
                    acceleration: (x: Double, y: Double, z: Double)? = nil,
                    rotationRate: (alpha: Double, beta: Double, gamma: Double)? = nil,
                    orientation: (alpha: Double, beta: Double, gamma: Double)? = nil,
                    timestamp: Double) {
            self.accelerationIncludingGravity = accelerationIncludingGravity
            self.acceleration = acceleration
            self.rotationRate = rotationRate
            self.orientation = orientation
            self.timestamp = timestamp
        }
    }

    /// Whether the device has motion sensors the page can read (a phone or tablet).
    nonisolated(unsafe) public static var available: (() -> Bool)?
    /// Starts the readings; `deliver` gets each one. Returns what stops them.
    nonisolated(unsafe) public static var start: ((_ deliver: @escaping (Sample) -> Void) -> () -> Void)?
}
