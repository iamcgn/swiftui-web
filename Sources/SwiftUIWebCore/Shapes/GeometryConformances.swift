// Conformances of the WebGraphics geometry types to SwiftUI's protocols (the types themselves
// live in Packages/WebGraphics so UIKitWeb shares them).

extension Angle: Animatable {
    public typealias AnimatableData = Double

    public var animatableData: Double {
        get { radians }
        set { radians = newValue }
    }
}

extension RectangleCornerRadii: Animatable {
    public typealias AnimatableData = AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>>
    public var animatableData: AnimatableData {
        get { .init(.init(topLeading, bottomLeading), .init(bottomTrailing, topTrailing)) }
        set {
            topLeading = newValue.first.first
            bottomLeading = newValue.first.second
            bottomTrailing = newValue.second.first
            topTrailing = newValue.second.second
        }
    }
}

extension Path: Shape {
    nonisolated public func path(in rect: CGRect) -> Path { self }
    public typealias AnimatableData = EmptyAnimatableData
}
