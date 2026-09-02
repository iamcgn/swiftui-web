/// A property wrapper type that can read and write a value managed by SwiftUI.
///
/// Storage lives in a `StateBox` owned by the view's node, so it survives re-evaluation of the
/// view's ancestors and is discarded when the view's identity changes (branch switch, `.id`,
/// `AnyView` type change, `ForEach` key removal).
@propertyWrapper
@frozen
public struct State<Value>: DynamicProperty {
    @usableFromInline
    package var initialValue: Value

    @usableFromInline
    package var box: StateBox<Value>?

    /// Creates a state property that stores an initial wrapped value.
    public init(wrappedValue value: Value) {
        initialValue = value
    }

    /// Creates a state property that stores an initial value.
    @_alwaysEmitIntoClient
    public init(initialValue value: Value) {
        self.init(wrappedValue: value)
    }

    /// The underlying value referenced by the state variable.
    public var wrappedValue: Value {
        get { box?.value ?? initialValue }
        nonmutating set {
            guard let box else {
                // Matches SwiftUI: writes before the view is installed are dropped.
                return
            }
            box.value = newValue
        }
    }

    /// A binding to the state value.
    public var projectedValue: Binding<Value> {
        if let box {
            return Binding(get: { box.value }, set: { newValue, transaction in
                box.set(newValue, transaction: transaction)
            })
        }
        let initial = initialValue
        return Binding(get: { initial }, set: { _ in })
    }

    @MainActor
    public mutating func _install(in node: ViewNode, slot: inout AnyObject?) {
        if let existing = slot as? StateBox<Value> {
            box = existing
        } else {
            let created = StateBox(initialValue, node: node)
            slot = created
            box = created
        }
    }
}

extension State where Value: ExpressibleByNilLiteral {
    /// Creates a state property without an initial value.
    @inlinable
    public init() {
        self.init(wrappedValue: nil)
    }
}

/// Persistent storage for one `State` property. Writes invalidate the owning node; the
/// scheduler coalesces any number of writes into one update.
///
/// `State.wrappedValue` is nonisolated, as in SwiftUI, so the box is a plain class; SwiftUI
/// requires state writes on the main actor and so do we (`assumeIsolated` traps otherwise).
@usableFromInline
package final class StateBox<Value>: @unchecked Sendable {
    package nonisolated(unsafe) var value: Value {
        didSet { invalidateNode() }
    }

    /// The transaction of the most recent write, consumed by the next flush.
    package nonisolated(unsafe) private(set) var lastTransaction: Transaction?

    package nonisolated(unsafe) private(set) weak var node: ViewNode?

    @MainActor
    package init(_ value: Value, node: ViewNode) {
        self.value = value
        self.node = node
    }

    package func set(_ newValue: Value, transaction: Transaction) {
        lastTransaction = transaction
        value = newValue
    }

    private func invalidateNode() {
        guard let node else { return }
        MainActor.assumeIsolated { node.invalidate() }
    }
}
