// SwiftData's `Predicate` (decision 0021, pf-swiftdata): a test over a model, run as a Swift
// closure, which is what `#Predicate` expands to here. It is declared in this module, not in
// SwiftData, because a declaration shadows Foundation's of the same name only from a module
// that re-exports Foundation, as this one does: an app's `func predicateToday() ->
// Predicate<Todo>` then names this type rather than being ambiguous with Foundation's.
public struct Predicate<T>: @unchecked Sendable {
    let test: (T) throws -> Bool
    public init(_ test: @escaping (T) throws -> Bool) { self.test = test }
    public func evaluate(_ value: T) throws -> Bool { try test(value) }
}
