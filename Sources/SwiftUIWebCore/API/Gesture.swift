// Gestures beyond the tap: `DragGesture`, `LongPressGesture`, `TapGesture` (with counts), the
// magnify and rotate gestures (API only: browsers deliver no pinch to a canvas yet), composition
// (`sequenced`, `simultaneously`, `exclusively`), `onChanged`/`onEnded`/`map`/`updating` with
// `@GestureState`, and the `gesture`/`highPriorityGesture`/`simultaneousGesture` modifiers.
// Recognition lives in `Runtime/GestureNodes.swift`. Docs/elements/Gestures.md.
#if os(WASI)
import FoundationEssentials
#else
import Foundation
#endif

/// A gesture: a recogniser over press events that produces values of `Value`.
public protocol Gesture {
    associatedtype Value
    associatedtype Body: Gesture
    var body: Body { get }
    /// Builds the recogniser for this gesture (primitives override; composites use `body`).
    @MainActor func _makeRecognizer() -> _GestureRecognizer<Value>
}

extension Gesture where Body.Value == Value {
    @MainActor public func _makeRecognizer() -> _GestureRecognizer<Value> { body._makeRecognizer() }
}

extension Never: Gesture {
    public typealias Value = Never
    @MainActor public func _makeRecognizer() -> _GestureRecognizer<Never> { fatalError("Never has no recogniser") }
}

/// How a view's gesture competes with its subviews' (`gesture(_:including:)`); accepted.
public struct GestureMask: OptionSet, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let none = GestureMask([])
    public static let gesture = GestureMask(rawValue: 1 << 0)
    public static let subviews = GestureMask(rawValue: 1 << 1)
    public static let all: GestureMask = [.gesture, .subviews]
}

// MARK: - Primitive gestures

/// Recognises one or more taps.
public struct TapGesture: Gesture {
    public typealias Value = Void
    public typealias Body = Never
    public var count: Int
    public init(count: Int = 1) { self.count = count }
    public var body: Never { fatalError() }
    @MainActor public func _makeRecognizer() -> _GestureRecognizer<Void> { TapRecognizer(count: count) }
}

/// Recognises a press held for `minimumDuration` without moving more than `maximumDistance`.
public struct LongPressGesture: Gesture {
    public typealias Value = Bool
    public typealias Body = Never
    public var minimumDuration: Double
    public var maximumDistance: CGFloat
    public init(minimumDuration: Double = 0.5, maximumDistance: CGFloat = 10) {
        self.minimumDuration = minimumDuration
        self.maximumDistance = maximumDistance
    }
    public var body: Never { fatalError() }
    @MainActor public func _makeRecognizer() -> _GestureRecognizer<Bool> { LongPressRecognizer(minimumDuration: minimumDuration, maximumDistance: maximumDistance) }
}

/// Recognises a drag once the pointer moved `minimumDistance`.
public struct DragGesture: Gesture {
    public typealias Body = Never

    public struct Value: Equatable, Sendable {
        public var time: Date
        public var location: CGPoint
        public var startLocation: CGPoint
        public var velocity: CGSize
        public var translation: CGSize { CGSize(width: location.x - startLocation.x, height: location.y - startLocation.y) }
        /// Where the drag would end if it decelerated from here (approximate: a quarter second of the velocity).
        public var predictedEndLocation: CGPoint { CGPoint(x: location.x + velocity.width / 4, y: location.y + velocity.height / 4) }
        public var predictedEndTranslation: CGSize { CGSize(width: predictedEndLocation.x - startLocation.x, height: predictedEndLocation.y - startLocation.y) }
        public init(time: Date, location: CGPoint, startLocation: CGPoint, velocity: CGSize) {
            self.time = time
            self.location = location
            self.startLocation = startLocation
            self.velocity = velocity
        }
    }

    public var minimumDistance: CGFloat
    public var coordinateSpace: CoordinateSpace

    public init(minimumDistance: CGFloat = 10, coordinateSpace: CoordinateSpace = .local) {
        self.minimumDistance = minimumDistance
        self.coordinateSpace = coordinateSpace
    }

    public init(minimumDistance: CGFloat = 10, coordinateSpace: some CoordinateSpaceProtocol) {
        self.init(minimumDistance: minimumDistance, coordinateSpace: coordinateSpace.coordinateSpace)
    }

    public var body: Never { fatalError() }
    @MainActor public func _makeRecognizer() -> _GestureRecognizer<Value> { DragRecognizer(minimumDistance: minimumDistance, global: coordinateSpace.isGlobal) }
}

/// A pinch (API only: no host delivers one to the canvas yet, so it never recognises).
public struct MagnifyGesture: Gesture {
    public typealias Body = Never
    public struct Value: Equatable, Sendable {
        public var magnification: CGFloat
        public var velocity: CGFloat
        public var startAnchor: UnitPoint
        public var startLocation: CGPoint
    }
    public var minimumScaleDelta: CGFloat
    public init(minimumScaleDelta: CGFloat = 0.01) { self.minimumScaleDelta = minimumScaleDelta }
    public var body: Never { fatalError() }
    @MainActor public func _makeRecognizer() -> _GestureRecognizer<Value> { _GestureRecognizer<Value>() }
}

/// A rotation (API only, as `MagnifyGesture`).
public struct RotateGesture: Gesture {
    public typealias Body = Never
    public struct Value: Equatable, Sendable {
        public var rotation: Angle
        public var velocity: Angle
        public var startAnchor: UnitPoint
        public var startLocation: CGPoint
    }
    public var minimumAngleDelta: Angle
    public init(minimumAngleDelta: Angle = .degrees(1)) { self.minimumAngleDelta = minimumAngleDelta }
    public var body: Never { fatalError() }
    @MainActor public func _makeRecognizer() -> _GestureRecognizer<Value> { _GestureRecognizer<Value>() }
}

/// The older pinch gesture (API only).
public struct MagnificationGesture: Gesture {
    public typealias Value = CGFloat
    public typealias Body = Never
    public var minimumScaleDelta: CGFloat
    public init(minimumScaleDelta: CGFloat = 0.01) { self.minimumScaleDelta = minimumScaleDelta }
    public var body: Never { fatalError() }
    @MainActor public func _makeRecognizer() -> _GestureRecognizer<CGFloat> { _GestureRecognizer<CGFloat>() }
}

/// The older rotation gesture (API only).
public struct RotationGesture: Gesture {
    public typealias Value = Angle
    public typealias Body = Never
    public var minimumAngleDelta: Angle
    public init(minimumAngleDelta: Angle = .degrees(1)) { self.minimumAngleDelta = minimumAngleDelta }
    public var body: Never { fatalError() }
    @MainActor public func _makeRecognizer() -> _GestureRecognizer<Angle> { _GestureRecognizer<Angle>() }
}

// MARK: - Modifiers

/// A gesture with an `onChanged` handler.
public struct _ChangedGesture<G: Gesture>: Gesture {
    public typealias Value = G.Value
    public typealias Body = Never
    public let base: G
    public let action: @MainActor (G.Value) -> Void
    public var body: Never { fatalError() }
    @MainActor public func _makeRecognizer() -> _GestureRecognizer<G.Value> {
        let recognizer = base._makeRecognizer()
        recognizer.changedHandlers.append(action)
        return recognizer
    }
}

/// A gesture with an `onEnded` handler.
public struct _EndedGesture<G: Gesture>: Gesture {
    public typealias Value = G.Value
    public typealias Body = Never
    public let base: G
    public let action: @MainActor (G.Value) -> Void
    public var body: Never { fatalError() }
    @MainActor public func _makeRecognizer() -> _GestureRecognizer<G.Value> {
        let recognizer = base._makeRecognizer()
        recognizer.endedHandlers.append(action)
        return recognizer
    }
}

/// A gesture whose values are transformed.
public struct _MapGesture<G: Gesture, V>: Gesture {
    public typealias Value = V
    public typealias Body = Never
    public let base: G
    public let transform: @MainActor (G.Value) -> V
    public var body: Never { fatalError() }
    @MainActor public func _makeRecognizer() -> _GestureRecognizer<V> { MapRecognizer(base: base._makeRecognizer(), transform: transform) }
}

/// A gesture that updates a `@GestureState` while it runs and resets it when it ends.
public struct _UpdatingGesture<G: Gesture, S>: Gesture {
    public typealias Value = G.Value
    public typealias Body = Never
    public let base: G
    public let state: GestureState<S>
    public let body_: @MainActor (G.Value, inout S, inout Transaction) -> Void
    public var body: Never { fatalError() }
    @MainActor public func _makeRecognizer() -> _GestureRecognizer<G.Value> {
        let recognizer = base._makeRecognizer()
        let state = state
        let update = body_
        recognizer.changedHandlers.append { value in
            var current = state.wrappedValue
            var transaction = Transaction()
            update(value, &current, &transaction)
            state._set(current)
        }
        recognizer.resetHandlers.append { state._reset() }
        return recognizer
    }
}

/// The value of a `SequenceGesture`.
public enum _SequenceValue<F, S> {
    case first(F)
    case second(F, S?)
}

/// The value of a `SimultaneousGesture`.
public struct _SimultaneousValue<F, S> {
    public var first: F?
    public var second: S?
    public init(first: F?, second: S?) {
        self.first = first
        self.second = second
    }
}

/// The value of an `ExclusiveGesture`.
public enum _ExclusiveValue<F, S> {
    case first(F)
    case second(S)
}

/// Two gestures in order: the second starts once the first ended.
public struct SequenceGesture<First: Gesture, Second: Gesture>: Gesture {
    public typealias Body = Never
    public typealias Value = _SequenceValue<First.Value, Second.Value>
    public let first: First
    public let second: Second
    public init(_ first: First, _ second: Second) {
        self.first = first
        self.second = second
    }
    public var body: Never { fatalError() }
    @MainActor public func _makeRecognizer() -> _GestureRecognizer<Value> { SequenceRecognizer(first: first._makeRecognizer(), second: second._makeRecognizer()) }
}

/// Two gestures recognised at once.
public struct SimultaneousGesture<First: Gesture, Second: Gesture>: Gesture {
    public typealias Body = Never
    public typealias Value = _SimultaneousValue<First.Value, Second.Value>
    public let first: First
    public let second: Second
    public init(_ first: First, _ second: Second) {
        self.first = first
        self.second = second
    }
    public var body: Never { fatalError() }
    @MainActor public func _makeRecognizer() -> _GestureRecognizer<Value> { SimultaneousRecognizer(first: first._makeRecognizer(), second: second._makeRecognizer()) }
}

/// Two gestures of which only the first to recognise runs.
public struct ExclusiveGesture<First: Gesture, Second: Gesture>: Gesture {
    public typealias Body = Never
    public typealias Value = _ExclusiveValue<First.Value, Second.Value>
    public let first: First
    public let second: Second
    public init(_ first: First, _ second: Second) {
        self.first = first
        self.second = second
    }
    public var body: Never { fatalError() }
    @MainActor public func _makeRecognizer() -> _GestureRecognizer<Value> { ExclusiveRecognizer(first: first._makeRecognizer(), second: second._makeRecognizer()) }
}

extension Gesture {
    /// Adds an action to run when the gesture's value changes.
    public func onChanged(_ action: @escaping @MainActor (Value) -> Void) -> _ChangedGesture<Self> { _ChangedGesture(base: self, action: action) }

    /// Adds an action to run when the gesture ends.
    public func onEnded(_ action: @escaping @MainActor (Value) -> Void) -> _EndedGesture<Self> { _EndedGesture(base: self, action: action) }

    /// Transforms the gesture's values.
    public func map<T>(_ transform: @escaping @MainActor (Value) -> T) -> _MapGesture<Self, T> { _MapGesture(base: self, transform: transform) }

    /// Updates `state` from the gesture's values while it runs; the state resets when it ends.
    public func updating<S>(_ state: GestureState<S>, body: @escaping @MainActor (Value, inout S, inout Transaction) -> Void) -> _UpdatingGesture<Self, S> {
        _UpdatingGesture(base: self, state: state, body_: body)
    }

    /// This gesture, then `other`.
    public func sequenced<Other: Gesture>(before other: Other) -> SequenceGesture<Self, Other> { SequenceGesture(self, other) }

    /// This gesture and `other` at once.
    public func simultaneously<Other: Gesture>(with other: Other) -> SimultaneousGesture<Self, Other> { SimultaneousGesture(self, other) }

    /// This gesture, or `other` if it recognises first.
    public func exclusively<Other: Gesture>(before other: Other) -> ExclusiveGesture<Self, Other> { ExclusiveGesture(self, other) }
}

// MARK: - GestureState

/// A property wrapper that a gesture updates while it runs and that resets when it ends.
@propertyWrapper
public struct GestureState<Value>: DynamicProperty {
    package var state: State<Value>
    package let resetValue: Value

    public init(wrappedValue: Value) {
        state = State(wrappedValue: wrappedValue)
        resetValue = wrappedValue
    }

    public init(initialValue: Value) { self.init(wrappedValue: initialValue) }

    public init(wrappedValue: Value, reset: @escaping (Value, inout Transaction) -> Void) { self.init(wrappedValue: wrappedValue) }

    public init(initialValue: Value, reset: @escaping (Value, inout Transaction) -> Void) { self.init(wrappedValue: initialValue) }

    public var wrappedValue: Value { state.wrappedValue }
    public var projectedValue: GestureState<Value> { self }

    package func _set(_ value: Value) { state.wrappedValue = value }
    package func _reset() { state.wrappedValue = resetValue }
}

// MARK: - View modifiers

/// Attaches a gesture to a view (`gesture`, `highPriorityGesture`, `simultaneousGesture`).
public struct _GestureModifier<G: Gesture> {
    public enum Priority: Sendable { case normal, high, simultaneous }
    public let gesture: G
    public let priority: Priority
    public let mask: GestureMask
}

extension _GestureModifier: ViewModifier {
    public typealias Body = Never

    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        GestureNode(context)
    }
}

extension View {
    /// Attaches a gesture with a lower precedence than gestures defined by the view's subviews.
    nonisolated public func gesture<G: Gesture>(_ gesture: G, including mask: GestureMask = .all) -> some View {
        modifier(_GestureModifier(gesture: gesture, priority: .normal, mask: mask))
    }

    /// Attaches a gesture with a higher precedence than gestures defined by the view's subviews.
    nonisolated public func highPriorityGesture<G: Gesture>(_ gesture: G, including mask: GestureMask = .all) -> some View {
        modifier(_GestureModifier(gesture: gesture, priority: .high, mask: mask))
    }

    /// Attaches a gesture to run alongside the subviews' (here: with normal precedence).
    nonisolated public func simultaneousGesture<G: Gesture>(_ gesture: G, including mask: GestureMask = .all) -> some View {
        modifier(_GestureModifier(gesture: gesture, priority: .simultaneous, mask: mask))
    }

    /// Runs `action` after a press held for `minimumDuration`; `onPressingChanged` follows the press.
    nonisolated public func onLongPressGesture(minimumDuration: Double = 0.5, maximumDistance: CGFloat = 10,
                                              perform action: @escaping @MainActor () -> Void,
                                              onPressingChanged: (@MainActor (Bool) -> Void)? = nil) -> some View {
        let gesture = LongPressGesture(minimumDuration: minimumDuration, maximumDistance: maximumDistance)
            .onChanged { pressing in onPressingChanged?(pressing) }
            .onEnded { _ in action() }
        return modifier(_GestureModifier(gesture: gesture, priority: .normal, mask: .all))
    }
}
