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
