// Associated objects without the Objective-C runtime: `objc_setAssociatedObject` and
// `objc_getAssociatedObject`, which Apple's Foundation brings with the runtime, for the stock
// wasm SDK. Kingfisher keeps its per-view download state this way (Runtime.swift), in EhPanda,
// IceCubes and the other apps that use it. With the Objective-C runtime SDK the runtime's own
// functions are in scope instead (WebFoundation re-exports `ObjectiveC`, decision 0023).
//
// A value is kept for its object while the object lives: each object's values sit in a table
// with a weak reference to the object, and a table whose object has gone is dropped, releasing
// its values, when its identifier comes round again or at the next sweep of the tables. Without
// the runtime there is no hook at an object's end, so the tables are swept as they are used:
// every get, set and removal counts, and a sweep comes once the count reaches the number of
// tables kept at the last sweep (at least 32). Kingfisher reads its task key for each image it
// sets, so a gone view's download task is released within a few images, at a cost spread over
// the calls that came between. A value type has no identity
// to hang values on (Apple boxes it afresh each time, so its values are never found again);
// here it gets no values either. A page runs one thread, so the tables take no lock.
#if os(WASI) && !canImport(ObjectiveC)

/// How an associated value is held, as the Objective-C runtime names the policies. Weak,
/// unretained (`ASSIGN`) values are held weakly here; the others are retained, and the copying
/// ones store a copy of an `NSCopying` value. Atomicity means nothing on one thread.
public enum objc_AssociationPolicy: UInt, Sendable {
    case OBJC_ASSOCIATION_ASSIGN = 0
    case OBJC_ASSOCIATION_RETAIN_NONATOMIC = 1
    case OBJC_ASSOCIATION_COPY_NONATOMIC = 3
    case OBJC_ASSOCIATION_RETAIN = 769
    case OBJC_ASSOCIATION_COPY = 771
}

private enum AssociatedValue {
    case strong(Any)
    case weak(WeakBox)

    var value: Any? {
        switch self {
        case .strong(let value): value
        case .weak(let box): box.object
        }
    }
}

private final class WeakBox {
    weak var object: AnyObject?
    init(_ object: AnyObject) { self.object = object }
}

private final class AssociationTable {
    weak var owner: AnyObject?
    var values: [UnsafeRawPointer: AssociatedValue] = [:]
    init(owner: AnyObject) { self.owner = owner }
}

private enum Associations {
    nonisolated(unsafe) static var tables: [ObjectIdentifier: AssociationTable] = [:]
    nonisolated(unsafe) static var usesSinceSweep = 0
    nonisolated(unsafe) static var keptAtLastSweep = 0

    /// The object's table, if it has a live one; a table left by a dead object with the same
    /// identifier is dropped.
    static func table(for object: AnyObject, creating: Bool) -> AssociationTable? {
        sweepIfDue()
        let id = ObjectIdentifier(object)
        if let table = tables[id] {
            if table.owner === object { return table }
            // Held until the access ends: releasing a value can run a deinit that comes back here.
            withExtendedLifetime(tables.removeValue(forKey: id)) {}
        }
        guard creating else { return nil }
        let table = AssociationTable(owner: object)
        tables[id] = table
        return table
    }

    /// Drops the tables of objects that have gone, so their values are released, once the uses
    /// since the last sweep reach the tables it kept: the sweep's cost is spread over those uses.
    static func sweepIfDue() {
        usesSinceSweep += 1
        guard usesSinceSweep >= max(32, keptAtLastSweep) else { return }
        sweep()
    }

    static func sweep() {
        usesSinceSweep = 0
        let before = tables
        tables = before.filter { $0.value.owner != nil }
        keptAtLastSweep = tables.count
        withExtendedLifetime(before) {}   // the dropped values go once `tables` is settled
    }
}

/// The object as a class instance, or nil for a value type (which has no identity).
private func instance(_ object: Any) -> AnyObject? {
    guard type(of: object) is AnyClass else { return nil }
    return object as AnyObject
}

/// Sets, or with nil removes, the object's value for the key.
public func objc_setAssociatedObject(_ object: Any, _ key: UnsafeRawPointer, _ value: Any?, _ policy: objc_AssociationPolicy) {
    guard let owner = instance(object) else { return }
    guard let value else {
        let old = Associations.table(for: owner, creating: false)?.values.removeValue(forKey: key)
        withExtendedLifetime(old) {}
        return
    }
    let stored: AssociatedValue
    switch policy {
    case .OBJC_ASSOCIATION_ASSIGN:
        guard let target = instance(value) else { return }
        stored = .weak(WeakBox(target))
    case .OBJC_ASSOCIATION_COPY, .OBJC_ASSOCIATION_COPY_NONATOMIC:
        stored = .strong((value as? NSCopying)?.copy(with: nil) ?? value)
    case .OBJC_ASSOCIATION_RETAIN, .OBJC_ASSOCIATION_RETAIN_NONATOMIC:
        stored = .strong(value)
    }
    let old = Associations.table(for: owner, creating: true)?.values.updateValue(stored, forKey: key)
    withExtendedLifetime(old) {}
}

/// The object's value for the key, or nil.
public func objc_getAssociatedObject(_ object: Any, _ key: UnsafeRawPointer) -> Any? {
    guard let owner = instance(object) else { return nil }
    return Associations.table(for: owner, creating: false)?.values[key]?.value
}

/// Removes all of the object's associated values.
public func objc_removeAssociatedObjects(_ object: Any) {
    guard let owner = instance(object) else { return }
    Associations.sweepIfDue()
    let old = Associations.tables.removeValue(forKey: ObjectIdentifier(owner))
    withExtendedLifetime(old) {}
}
#endif
