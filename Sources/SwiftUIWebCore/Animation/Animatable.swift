/// A type that can serve as the animatable data of an animatable type.
public protocol VectorArithmetic: AdditiveArithmetic {
    /// Multiplies each component of this value by the given value.
    mutating func scale(by rhs: Double)

    /// Returns the dot-product of this vector arithmetic instance with itself.
    var magnitudeSquared: Double { get }
}

extension VectorArithmetic {
    /// Returns a value with each component of this value multiplied by the given value.
    public func scaled(by rhs: Double) -> Self {
        var copy = self
        copy.scale(by: rhs)
        return copy
    }

    /// Interpolates this value with `other` by the specified `amount`.
    public mutating func interpolate(towards other: Self, amount: Double) {
        var delta = other
        delta -= self
        delta.scale(by: amount)
        self += delta
    }

    /// Returns this value interpolated with `other` by the specified `amount`.
    public func interpolated(towards other: Self, amount: Double) -> Self {
        var copy = self
        copy.interpolate(towards: other, amount: amount)
        return copy
    }
}

extension Double: VectorArithmetic {
    public mutating func scale(by rhs: Double) { self *= rhs }
    public var magnitudeSquared: Double { self * self }
}

extension Float: VectorArithmetic {
    public mutating func scale(by rhs: Double) { self *= Float(rhs) }
    public var magnitudeSquared: Double { Double(self * self) }
}

#if !os(WASI)
extension CGFloat: VectorArithmetic {
    public mutating func scale(by rhs: Double) { self *= CGFloat(rhs) }
    public var magnitudeSquared: Double { Double(self * self) }
}
#endif

/// An empty type for animatable data.
@frozen
public struct EmptyAnimatableData: VectorArithmetic, Sendable {
    @inlinable public init() {}
    @inlinable public static var zero: EmptyAnimatableData { EmptyAnimatableData() }
    @inlinable public static func += (lhs: inout EmptyAnimatableData, rhs: EmptyAnimatableData) {}
    @inlinable public static func -= (lhs: inout EmptyAnimatableData, rhs: EmptyAnimatableData) {}
    @inlinable public static func + (lhs: EmptyAnimatableData, rhs: EmptyAnimatableData) -> EmptyAnimatableData { lhs }
    @inlinable public static func - (lhs: EmptyAnimatableData, rhs: EmptyAnimatableData) -> EmptyAnimatableData { lhs }
    @inlinable public mutating func scale(by rhs: Double) {}
    @inlinable public var magnitudeSquared: Double { 0 }
}

/// A pair of animatable values, which is itself animatable.
@frozen
public struct AnimatablePair<First: VectorArithmetic, Second: VectorArithmetic>: VectorArithmetic {
    public var first: First
    public var second: Second

    @inlinable public init(_ first: First, _ second: Second) {
        self.first = first
        self.second = second
    }

    public static var zero: AnimatablePair { AnimatablePair(.zero, .zero) }
    public static func += (lhs: inout AnimatablePair, rhs: AnimatablePair) { lhs.first += rhs.first; lhs.second += rhs.second }
    public static func -= (lhs: inout AnimatablePair, rhs: AnimatablePair) { lhs.first -= rhs.first; lhs.second -= rhs.second }
    public static func + (lhs: AnimatablePair, rhs: AnimatablePair) -> AnimatablePair { AnimatablePair(lhs.first + rhs.first, lhs.second + rhs.second) }
    public static func - (lhs: AnimatablePair, rhs: AnimatablePair) -> AnimatablePair { AnimatablePair(lhs.first - rhs.first, lhs.second - rhs.second) }
    public mutating func scale(by rhs: Double) { first.scale(by: rhs); second.scale(by: rhs) }
    public var magnitudeSquared: Double { first.magnitudeSquared + second.magnitudeSquared }
}

extension AnimatablePair: Sendable where First: Sendable, Second: Sendable {}

/// A type that describes how to animate a property of a view.
public protocol Animatable {
    /// The type defining the data to animate.
    associatedtype AnimatableData: VectorArithmetic = EmptyAnimatableData

    /// The data to animate.
    var animatableData: AnimatableData { get set }
}

extension Animatable where AnimatableData == EmptyAnimatableData {
    public var animatableData: EmptyAnimatableData {
        get { EmptyAnimatableData() }
        set {}
    }
}

extension Animatable where Self: VectorArithmetic {
    public var animatableData: Self {
        get { self }
        set { self = newValue }
    }
}

extension Double: Animatable {}
extension Float: Animatable {}
#if !os(WASI)   // CGFloat is Double on wasm (the CoreGraphics shim)
extension CGFloat: Animatable {}
#endif
