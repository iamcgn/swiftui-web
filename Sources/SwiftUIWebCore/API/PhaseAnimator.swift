// PhaseAnimator: cycles content through a sequence of phases, animating each step with the
// phase's animation, either forever or once per change of a trigger value (then back to the
// first phase). `View.phaseAnimator` wraps the view as `PlaceholderContentView`.

/// A view that animates its content through a sequence of phases.
public struct PhaseAnimator<Phase: Equatable, Content: View>: View {
    package let phases: [Phase]
    package let trigger: _AnyEquatable?
    package let content: (Phase) -> Content
    package let animation: (Phase) -> Animation?

    /// Cycles through the phases forever, starting with the first.
    public init(_ phases: some Sequence<Phase>, @ViewBuilder content: @escaping (Phase) -> Content,
                animation: @escaping (Phase) -> Animation? = { _ in .default }) {
        self.phases = Array(phases)
        self.trigger = nil
        self.content = content
        self.animation = animation
    }

    /// Shows the first phase; each change of `trigger` runs through the others and back.
    public init(_ phases: some Sequence<Phase>, trigger: some Equatable, @ViewBuilder content: @escaping (Phase) -> Content,
                animation: @escaping (Phase) -> Animation? = { _ in .default }) {
        self.phases = Array(phases)
        self.trigger = _AnyEquatable(trigger)
        self.content = content
        self.animation = animation
    }

    public var body: Never { fatalError("PhaseAnimator is a primitive view") }

    public static func _makeNode(_ context: _NodeContext<PhaseAnimator<Phase, Content>>) -> TypedNode<PhaseAnimator<Phase, Content>> {
        PhaseAnimatorNode(context)
    }
}

/// The modified view handed to a `phaseAnimator` or `keyframeAnimator` content closure.
public struct PlaceholderContentView<Value: View>: View {
    package let value: Value
    package init(_ value: Value) { self.value = value }
    public var body: some View { value }
}

extension View {
    /// Cycles this view through `phases` forever, restyling it per phase.
    public func phaseAnimator<Phase: Equatable, V: View>(
        _ phases: some Sequence<Phase>,
        @ViewBuilder content: @escaping (PlaceholderContentView<Self>, Phase) -> V,
        animation: @escaping (Phase) -> Animation? = { _ in .default }
    ) -> some View {
        let placeholder = PlaceholderContentView(self)
        return PhaseAnimator(phases, content: { content(placeholder, $0) }, animation: animation)
    }

    /// Runs this view through `phases` (and back to the first) whenever `trigger` changes.
    public func phaseAnimator<Phase: Equatable, V: View>(
        _ phases: some Sequence<Phase>,
        trigger: some Equatable,
        @ViewBuilder content: @escaping (PlaceholderContentView<Self>, Phase) -> V,
        animation: @escaping (Phase) -> Animation? = { _ in .default }
    ) -> some View {
        let placeholder = PlaceholderContentView(self)
        return PhaseAnimator(phases, trigger: trigger, content: { content(placeholder, $0) }, animation: animation)
    }
}

/// A type-erased equatable value (animator triggers).
public struct _AnyEquatable: Equatable {
    private let value: Any
    private let equals: (Any) -> Bool

    public init<T: Equatable>(_ value: T) {
        self.value = value
        self.equals = { other in (other as? T).map { $0 == value } ?? false }
    }

    public static func == (lhs: _AnyEquatable, rhs: _AnyEquatable) -> Bool { lhs.equals(rhs.value) }
}
