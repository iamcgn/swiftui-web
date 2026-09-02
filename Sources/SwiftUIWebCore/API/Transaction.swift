/// A key for accessing values in a transaction.
public protocol TransactionKey {
    /// The associated type representing the type of the transaction key's value.
    associatedtype Value

    /// The default value for the transaction key.
    static var defaultValue: Self.Value { get }
}

/// The context of the current state-processing update.
///
/// Stub for Phase 1: carries the documented flags and custom keys so modifiers and
/// `withTransaction` type-check. `animation` is added with the animation system in Phase 2.
@frozen
public struct Transaction {
    package var values: [ObjectIdentifier: Any] = [:]

    /// A Boolean value that indicates whether views should disable animations.
    public var disablesAnimations: Bool = false

    /// A Boolean value that indicates whether the transaction originated from an action that
    /// produces a series of values.
    public var isContinuous: Bool = false

    /// Creates a transaction.
    public init() {}

    /// Accesses the transaction value associated with a custom key.
    public subscript<K: TransactionKey>(key: K.Type) -> K.Value {
        get {
            if let stored = values[ObjectIdentifier(key)] {
                return stored as! K.Value
            }
            return K.defaultValue
        }
        set {
            values[ObjectIdentifier(key)] = newValue
        }
    }
}

/// Executes a closure with the specified transaction and returns the result.
///
/// The runtime consults `Transaction.current` while flushing the state changes made inside
/// `body`.
@MainActor
public func withTransaction<Result>(
    _ transaction: Transaction,
    _ body: () throws -> Result
) rethrows -> Result {
    let previous = Transaction._current
    Transaction._current = transaction
    defer { Transaction._current = previous }
    return try body()
}

extension Transaction {
    /// The transaction in effect for state changes made on the main actor right now, if any.
    @MainActor
    package static var _current: Transaction? = nil
}
