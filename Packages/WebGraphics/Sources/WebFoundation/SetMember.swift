// A member of Foundation's `NSSet` that is not `Hashable`, held as Apple's Foundation holds one in
// its `__SwiftValue` box: an object is the same member wherever it is added again, and a value
// (a struct, a closure) is equal only to itself. `NSSet(array:)`, `NSSet(objects:)` and the
// array literal keep such members instead of dropping them.
#if os(WASI)

public final class _WebSetMember: Hashable, @unchecked Sendable {
    /// The value the member stands for.
    public let base: Any
    private let object: AnyObject?

    private init(_ base: Any) {
        self.base = base
        object = type(of: base) is AnyClass ? base as AnyObject : nil
    }

    public static func == (lhs: _WebSetMember, rhs: _WebSetMember) -> Bool {
        if let left = lhs.object, let right = rhs.object { return left === right }
        return lhs === rhs
    }
    public func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(object ?? self)) }

    /// The value as a set's member: itself when it is hashable, boxed when it is not.
    public static func member(_ value: Any) -> AnyHashable {
        if let hashable = value as? AnyHashable { return hashable }
        return AnyHashable(_WebSetMember(value))
    }
    /// The value a member stands for, out of its box.
    public static func value(_ member: AnyHashable) -> Any { (member.base as? _WebSetMember)?.base ?? member.base }
    /// Members in order, each once.
    public static func distinct(_ values: [Any]) -> [AnyHashable] {
        var seen = Set<AnyHashable>(), members: [AnyHashable] = []
        for value in values {
            let boxed = member(value)
            if seen.insert(boxed).inserted { members.append(boxed) }
        }
        return members
    }
}
#endif
