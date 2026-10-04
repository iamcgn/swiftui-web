/// A key for accessing values in a transaction.
public protocol TransactionKey {
    /// The associated type representing the type of the transaction key's value.
    associatedtype Value

    /// The default value for the transaction key.
    static var defaultValue: Self.Value { get }
}

/// The context of the current state-processing update.
///
/// Carries the animation (`withAnimation`), the documented flags and custom keys; the runtime
/// reads `animation` while flushing the state changes made inside `withTransaction`.
@frozen
public struct Transaction {
    package var values: [ObjectIdentifier: Any] = [:]

    /// The animation, if any, for the current state changes.
    public var animation: Animation? = nil

    /// A Boolean value that indicates whether views should disable animations.
    public var disablesAnimations: Bool = false

    /// A Boolean value that indicates whether the transaction originated from an action that
    /// produces a series of values.
    public var isContinuous: Bool = false

    /// Completion callbacks registered by `withAnimation(_:completionCriteria:_:completion:)`
    /// and `addAnimationCompletion`; the runtime of the first node invalidated under the
    /// transaction claims them and calls them when its animation completes.
    package var _completions: [_AnimationCompletion] = []

    /// Creates a transaction.
    public init() {}

    /// Adds a completion to run when the animations of this transaction complete.
    public mutating func addAnimationCompletion(criteria: AnimationCompletionCriteria = .logicallyComplete, _ completion: @escaping () -> Void) {
        _completions.append(_AnimationCompletion(criteria: criteria, completion: completion))
    }

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

/// Returns the result of recomputing the view's body with the provided animation.
@MainActor
public func withAnimation<Result>(_ animation: Animation? = .default, _ body: () throws -> Result) rethrows -> Result {
    var transaction = Transaction()
    transaction.animation = animation
    return try withTransaction(transaction, body)
}

/// Returns the result of recomputing the view's body with the provided animation, and runs the
/// completion callback when all animations created by the changes complete (`logicallyComplete`:
/// the animation's duration has passed; `removed`: it has ended entirely, so a repeating one
/// never completes). Changes that animate nothing complete on the next turn.
@MainActor
public func withAnimation<Result>(_ animation: Animation? = .default, completionCriteria: AnimationCompletionCriteria = .logicallyComplete,
                                  _ body: () throws -> Result, completion: @escaping () -> Void) rethrows -> Result {
    var transaction = Transaction()
    transaction.animation = animation
    let entry = _AnimationCompletion(criteria: completionCriteria, completion: completion)
    transaction._completions = [entry]
    let result = try withTransaction(transaction, body)
    if !entry.claimed {
        // No node was invalidated: nothing animates, the completion runs on the next turn.
        entry.claimed = true
        Task { @MainActor in completion() }
    }
    return result
}

/// The criteria for when an animation is considered complete.
public enum AnimationCompletionCriteria: Hashable, Sendable {
    /// The animation has logically completed, even if it is still running (a settling spring).
    case logicallyComplete
    /// The animation has been removed entirely.
    case removed
}

/// A pending completion callback (a class: claimed once, by the runtime that animates; main
/// actor use only, as transactions are).
public final class _AnimationCompletion {
    package let criteria: AnimationCompletionCriteria
    package let completion: () -> Void
    package var claimed = false
    package init(criteria: AnimationCompletionCriteria, completion: @escaping () -> Void) {
        self.criteria = criteria
        self.completion = completion
    }
}

extension Transaction {
    /// The transaction in effect for state changes made on the main actor right now, if any.
    @MainActor
    package static var _current: Transaction? = nil
}
