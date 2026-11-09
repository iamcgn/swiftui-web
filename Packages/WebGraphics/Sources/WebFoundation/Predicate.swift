// SwiftData's `Predicate` (decision 0021, pf-swiftdata): a test over a model, run as a Swift
// closure, which is what `#Predicate` expands to here. It is declared in this module, not in
// SwiftData, because a declaration shadows another of the same name when every import path
// to the other passes through its own module. For a wasm app every path to Foundation's
// `Predicate` (in FoundationEssentials) passes through this module, so an app's
// `func predicateToday() -> Predicate<Todo>` names this type. On macOS and Linux other modules
// import Foundation directly, so the bare name stays ambiguous there: our own code and tests
// spell `WebFoundation.Predicate`.
public struct Predicate<T>: @unchecked Sendable {
    let test: (T) throws -> Bool
    public init(_ test: @escaping (T) throws -> Bool) { self.test = test }
    public func evaluate(_ value: T) throws -> Bool { try test(value) }
}
