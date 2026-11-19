// Reading main-actor content from nonisolated code that the runtime only reaches on the main
// actor: a builder or a column's `_makeContent` resolving a conformer's `body`.

/// Runs `operation` as if on the main actor. Callers are only reached from view bodies, which
/// run on the main actor (a page has one thread). Unlike `MainActor.assumeIsolated` it neither
/// checks the executor nor asks for a `Sendable` result, so a caller adds no copy of either to
/// a bundle.
@inline(__always)
package nonisolated func _readOnMainActor<T>(_ operation: @MainActor () -> T) -> T {
    withoutActuallyEscaping(operation) { operation in
        unsafeBitCast(operation, to: (() -> T).self)()
    }
}

/// `_readOnMainActor` for a nonisolated entry point that runs a main-actor implementation on
/// values it holds (a graphics context and its arguments): they are handed to `operation`
/// rather than captured by it, so nothing is sent across isolation.
@inline(__always)
package nonisolated func _runOnMainActor<V, T>(_ value: V, _ operation: @MainActor (V) -> T) -> T {
    withoutActuallyEscaping(operation) { operation in
        unsafeBitCast(operation, to: ((V) -> T).self)(value)
    }
}
