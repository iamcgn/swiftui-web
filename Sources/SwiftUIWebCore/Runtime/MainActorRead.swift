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
