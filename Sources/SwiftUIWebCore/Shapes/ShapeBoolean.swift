// Boolean operations as shapes (`Shape.union` and friends); the path algebra lives in
// WebGraphics/Shapes/PathBoolean.swift.

// MARK: - Shape operations

/// A shape made from two shapes by a boolean operation.
public struct _BooleanShape<A: Shape, B: Shape> {
    public var a: A
    public var b: B
    package var operation: PathBooleanOperation
    package var eoFill: Bool
    package var otherEOFill: Bool

    package init(a: A, b: B, operation: PathBooleanOperation, eoFill: Bool, otherEOFill: Bool) {
        self.a = a
        self.b = b
        self.operation = operation
        self.eoFill = eoFill
        self.otherEOFill = otherEOFill
    }
}

extension _BooleanShape: Shape {
    nonisolated public func path(in rect: CGRect) -> Path {
        a.path(in: rect).combined(operation, with: b.path(in: rect), eoFill: eoFill, otherEOFill: otherEOFill)
    }

    nonisolated public func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize { a.sizeThatFits(proposal) }

    public typealias AnimatableData = AnimatablePair<A.AnimatableData, B.AnimatableData>
    public var animatableData: AnimatableData {
        get { .init(a.animatableData, b.animatableData) }
        set { a.animatableData = newValue.first; b.animatableData = newValue.second }
    }
}

/// The parts of a shape's outline inside or outside another shape.
public struct _LineClippedShape<A: Shape, B: Shape> {
    public var a: A
    public var b: B
    package var keepInside: Bool
    package var otherEOFill: Bool

    package init(a: A, b: B, keepInside: Bool, otherEOFill: Bool) {
        self.a = a
        self.b = b
        self.keepInside = keepInside
        self.otherEOFill = otherEOFill
    }
}

extension _LineClippedShape: Shape {
    nonisolated public func path(in rect: CGRect) -> Path {
        a.path(in: rect).lineClipped(by: b.path(in: rect), keepInside: keepInside, otherEOFill: otherEOFill)
    }

    nonisolated public func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize { a.sizeThatFits(proposal) }
    public static var role: ShapeRole { .stroke }

    public typealias AnimatableData = AnimatablePair<A.AnimatableData, B.AnimatableData>
    public var animatableData: AnimatableData {
        get { .init(a.animatableData, b.animatableData) }
        set { a.animatableData = newValue.first; b.animatableData = newValue.second }
    }
}

extension Shape {
    /// The area covered by this shape or `other`.
    nonisolated public func union<T: Shape>(_ other: T, eoFill: Bool = false) -> some Shape {
        _BooleanShape(a: self, b: other, operation: .union, eoFill: eoFill, otherEOFill: eoFill)
    }

    /// The area covered by both this shape and `other`.
    nonisolated public func intersection<T: Shape>(_ other: T, eoFill: Bool = false) -> some Shape {
        _BooleanShape(a: self, b: other, operation: .intersection, eoFill: eoFill, otherEOFill: eoFill)
    }

    /// This shape's area with `other`'s removed.
    nonisolated public func subtracting<T: Shape>(_ other: T, eoFill: Bool = false) -> some Shape {
        _BooleanShape(a: self, b: other, operation: .subtraction, eoFill: eoFill, otherEOFill: eoFill)
    }

    /// The area covered by exactly one of this shape and `other`.
    nonisolated public func symmetricDifference<T: Shape>(_ other: T, eoFill: Bool = false) -> some Shape {
        _BooleanShape(a: self, b: other, operation: .symmetricDifference, eoFill: eoFill, otherEOFill: eoFill)
    }

    /// The parts of this shape's outline inside `other`.
    nonisolated public func lineIntersection<T: Shape>(_ other: T, eoFill: Bool = false) -> some Shape {
        _LineClippedShape(a: self, b: other, keepInside: true, otherEOFill: eoFill)
    }

    /// The parts of this shape's outline outside `other`.
    nonisolated public func lineSubtraction<T: Shape>(_ other: T, eoFill: Bool = false) -> some Shape {
        _LineClippedShape(a: self, b: other, keepInside: false, otherEOFill: eoFill)
    }
}
