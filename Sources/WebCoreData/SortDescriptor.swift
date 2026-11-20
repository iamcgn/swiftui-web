// Foundation's `SortDescriptor` in Core Data apps: `@FetchRequest(sortDescriptors:
// [SortDescriptor(\.date, order: .reverse)])`, and `NSSortDescriptor(_:)` to turn one into the
// descriptor a fetch request sorts with. SwiftData declares the type (its `FetchDescriptor`
// sorts with it); an app that imports only CoreData names it through this alias.
import SwiftData
import SwiftUIWebCore

/// A description of how to order values by one of their properties.
public typealias SortDescriptor<Compared> = SwiftData.SortDescriptor<Compared>

extension NSSortDescriptor {
    /// The descriptor that orders as `sortDescriptor` does, named by its key path.
    public convenience init<Compared>(_ sortDescriptor: SortDescriptor<Compared>) {
        let forward = sortDescriptor.order == .forward
        self.init(keyPath: sortDescriptor.keyPath, rootType: Compared.self, ascending: forward) { a, b in
            guard let a = a as? Compared, let b = b as? Compared else { return false }
            // `compare` applies the order already; the descriptor applies `ascending` itself.
            return sortDescriptor.compare(forward ? a : b, forward ? b : a) == .orderedAscending
        }
        _origin = AnyHashable(sortDescriptor)
    }
}

extension SortDescriptor {
    /// The descriptor that orders `Compared` values as `descriptor` does, or nil when the
    /// descriptor names neither a key path into `Compared` nor a key.
    public init?(_ descriptor: NSSortDescriptor, comparing: Compared.Type) {
        if let origin = descriptor._origin as? SortDescriptor<Compared> {
            self = origin
            return
        }
        let keyPath = descriptor.keyPath as? PartialKeyPath<Compared>
        guard keyPath != nil || descriptor.key != nil else { return nil }
        self.init(_keyPath: keyPath, order: descriptor.ascending ? .forward : .reverse, comparison: AnyHashable(descriptor)) { a, b in
            descriptor.compare(a, to: b) == .orderedAscending
        }
    }
}

extension FetchedResults where Result: NSManagedObject {
    /// The request's sort descriptors as Foundation `SortDescriptor`s; setting them refetches.
    public var sortDescriptors: [SortDescriptor<Result>] {
        get { nsSortDescriptors.compactMap { SortDescriptor($0, comparing: Result.self) } }
        nonmutating set { nsSortDescriptors = newValue.map { NSSortDescriptor($0) } }
    }
}

extension SectionedFetchResults where Result: NSManagedObject {
    /// The request's sort descriptors as Foundation `SortDescriptor`s; setting them refetches.
    public var sortDescriptors: [SortDescriptor<Result>] {
        get { nsSortDescriptors.compactMap { SortDescriptor($0, comparing: Result.self) } }
        nonmutating set { nsSortDescriptors = newValue.map { NSSortDescriptor($0) } }
    }
}

extension FetchRequest.Configuration where Result: NSManagedObject {
    /// The configuration's sort descriptors as Foundation `SortDescriptor`s.
    public var sortDescriptors: [SortDescriptor<Result>] {
        get { nsSortDescriptors.compactMap { SortDescriptor($0, comparing: Result.self) } }
        set { nsSortDescriptors = newValue.map { NSSortDescriptor($0) } }
    }
}

extension FetchRequest where Result: NSManagedObject {
    /// A request for the objects of `Result`'s entity, sorted by Foundation sort descriptors.
    @_disfavoredOverload
    public init(sortDescriptors: [SortDescriptor<Result>], predicate: NSPredicate? = nil, animation: Animation? = nil) {
        self.init(sortDescriptors: sortDescriptors.map { NSSortDescriptor($0) }, predicate: predicate, animation: animation)
    }
}

extension SectionedFetchRequest where Result: NSManagedObject {
    /// A sectioned request for the objects of `Result`'s entity, sorted by Foundation sort
    /// descriptors.
    @_disfavoredOverload
    public init(sectionIdentifier: KeyPath<Result, SectionIdentifier>, sortDescriptors: [SortDescriptor<Result>], predicate: NSPredicate? = nil, animation: Animation? = nil) {
        self.init(sectionIdentifier: sectionIdentifier, sortDescriptors: sortDescriptors.map { NSSortDescriptor($0) }, predicate: predicate, animation: animation)
    }
}
