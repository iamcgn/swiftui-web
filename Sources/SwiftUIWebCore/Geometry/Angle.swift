/// A geometric angle whose value you access in either radians or degrees.
@frozen
public struct Angle: Hashable, Sendable {
    public var radians: Double

    @inlinable public var degrees: Double {
        get { radians * 180 / .pi }
        set { radians = newValue * .pi / 180 }
    }

    @inlinable public init() { radians = 0 }
    @inlinable public init(radians: Double) { self.radians = radians }
    @inlinable public init(degrees: Double) { radians = degrees * .pi / 180 }

    @inlinable public static func radians(_ radians: Double) -> Angle { Angle(radians: radians) }
    @inlinable public static func degrees(_ degrees: Double) -> Angle { Angle(degrees: degrees) }

    public static let zero = Angle()
}

extension Angle: Comparable {
    @inlinable public static func < (lhs: Angle, rhs: Angle) -> Bool { lhs.radians < rhs.radians }
}

extension Angle: Animatable {
    public typealias AnimatableData = Double

    public var animatableData: Double {
        get { radians }
        set { radians = newValue }
    }
}

extension Angle: CustomStringConvertible {
    public var description: String { "Angle(radians: \(radians))" }
}
