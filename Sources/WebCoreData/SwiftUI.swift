// SwiftUI's Core Data integration: `@FetchRequest` and `@SectionedFetchRequest` over the
// environment's `managedObjectContext`. A fetch request reads its context on every read and
// refetches after every change the context sees (an insert, a property set, a save, another
// context's save), as Apple's does through a fetched results controller.

import SwiftUIWebCore
import WebCombine

// MARK: - The environment

extension EnvironmentValues {
    /// The context `@FetchRequest` reads (`.environment(\.managedObjectContext, ...)`); without
    /// one, a context over an empty in-memory store.
    public var managedObjectContext: NSManagedObjectContext {
        get { self[_ManagedObjectContextKey.self] ?? _ManagedObjectContextKey.fallback }
        set { self[_ManagedObjectContextKey.self] = newValue }
    }
}

struct _ManagedObjectContextKey: EnvironmentKey {
    static let defaultValue: NSManagedObjectContext? = nil

    nonisolated(unsafe) private static var fallbackContext: NSManagedObjectContext?
    static var fallback: NSManagedObjectContext {
        if let fallbackContext { return fallbackContext }
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: NSManagedObjectModel())
        _ = try? coordinator.addPersistentStore(ofType: NSInMemoryStoreType, configurationName: nil, at: nil)
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        fallbackContext = context
        return context
    }
}

// MARK: - The subscription

/// What a fetch request keeps across body evaluations: its subscription to the context, and the
/// predicate and sort descriptors set through its results (`nsPredicate`, `nsSortDescriptors`).
final class _FetchBox: ObservableObject, @unchecked Sendable {
    private var stop: (() -> Void)?
    private weak var watched: NSManagedObjectContext?
    /// The request the view last made (its predicate and sort descriptors, as text): a new one
    /// drops the overrides set through the results.
    private var signature: String?
    var predicateOverride: NSPredicate??
    var sortOverride: [NSSortDescriptor]?

    init() {}

    func watch(_ context: NSManagedObjectContext) {
        guard watched !== context else { return }
        stop?()
        watched = context
        stop = context._observe { [weak self] onMain in
            guard let self else { return }
            if onMain { self.objectWillChange.send() }
            else { Task { @MainActor in self.objectWillChange.send() } }
        }
    }

    func adopt<T>(_ request: NSFetchRequest<T>) {
        let new = "\(request.entityName ?? "")|\(request.predicate?.predicateFormat ?? "")|\(request.sortDescriptors ?? [])"
        if signature != new {
            signature = new
            predicateOverride = nil
            sortOverride = nil
        }
    }

    func predicate<T>(_ request: NSFetchRequest<T>) -> NSPredicate? {
        if let predicateOverride { return predicateOverride }
        return request.predicate
    }

    func sortDescriptors<T>(_ request: NSFetchRequest<T>) -> [NSSortDescriptor] { sortOverride ?? request.sortDescriptors ?? [] }

    func setPredicate(_ predicate: NSPredicate?) {
        predicateOverride = .some(predicate)
        objectWillChange.send()
    }

    func setSortDescriptors(_ descriptors: [NSSortDescriptor]) {
        sortOverride = descriptors
        objectWillChange.send()
    }

    /// The request's results in the context, with the overrides applied.
    func fetch<T>(_ request: NSFetchRequest<T>, in context: NSManagedObjectContext) -> [T] {
        if request.entity == nil, request.entityName == nil, let type = T.self as? NSManagedObject.Type {
            request.entity = type._entity(in: context)
        }
        let saved = (request.predicate, request.sortDescriptors)
        request.predicate = predicate(request)
        request.sortDescriptors = sortDescriptors(request)
        defer { (request.predicate, request.sortDescriptors) = saved }
        do { return try context.fetch(request) } catch {
            print("FetchRequest: \(error)")
            return []
        }
    }

    deinit { stop?() }
}

// MARK: - FetchRequest

/// A property wrapper type that retrieves entities from a Core Data persistent store.
@MainActor
@propertyWrapper
public struct FetchRequest<Result: NSFetchRequestResult>: DynamicProperty {
    @Environment(\.managedObjectContext) private var context
    @StateObject private var box = _FetchBox()
    private let request: NSFetchRequest<Result>
    private let animation: Animation?

    /// The fetched results of the fetch request.
    public var wrappedValue: FetchedResults<Result> {
        box.watch(context)
        box.adopt(request)
        return FetchedResults(results: box.fetch(request, in: context), box: box, request: request)
    }

    /// The request's configuration, as a binding (`$items.nsPredicate`).
    public var projectedValue: Binding<Configuration> {
        let box = self.box
        let request = self.request
        return Binding(
            get: { Configuration(nsPredicate: box.predicate(request), nsSortDescriptors: box.sortDescriptors(request)) },
            set: { configuration in
                box.predicateOverride = .some(configuration.nsPredicate)
                box.sortOverride = configuration.nsSortDescriptors
                box.objectWillChange.send()
            }
        )
    }

    /// The request's predicate and sort descriptors.
    public struct Configuration {
        public var nsPredicate: NSPredicate?
        public var nsSortDescriptors: [NSSortDescriptor]
    }

    nonisolated public mutating func update() {}

    /// A request for the entity's objects, sorted and filtered.
    public init(entity: NSEntityDescription, sortDescriptors: [NSSortDescriptor], predicate: NSPredicate? = nil, animation: Animation? = nil) {
        let request = NSFetchRequest<Result>()
        request.entity = entity
        request.sortDescriptors = sortDescriptors
        request.predicate = predicate
        self.request = request
        self.animation = animation
    }

    /// A request made from a fetch request.
    public init(fetchRequest: NSFetchRequest<Result>, animation: Animation? = nil) {
        request = fetchRequest
        self.animation = animation
    }

    public init(fetchRequest: NSFetchRequest<Result>, transaction: Transaction) {
        request = fetchRequest
        animation = transaction.animation
    }
}

extension FetchRequest where Result: NSManagedObject {
    /// A request for the objects of `Result`'s entity, sorted and filtered.
    public init(sortDescriptors: [NSSortDescriptor], predicate: NSPredicate? = nil, animation: Animation? = nil) {
        let request = NSFetchRequest<Result>()
        request.sortDescriptors = sortDescriptors
        request.predicate = predicate
        self.init(fetchRequest: request, animation: animation)
    }
}

/// A collection of results retrieved from a Core Data persistent store.
public struct FetchedResults<Result: NSFetchRequestResult>: RandomAccessCollection {
    let results: [Result]
    let box: _FetchBox?
    let request: NSFetchRequest<Result>?

    init(results: [Result], box: _FetchBox?, request: NSFetchRequest<Result>?) {
        self.results = results
        self.box = box
        self.request = request
    }

    public var startIndex: Int { results.startIndex }
    public var endIndex: Int { results.endIndex }
    public subscript(position: Int) -> Result { results[position] }

    /// The request's predicate; setting it refetches.
    public var nsPredicate: NSPredicate? {
        get { request.flatMap { box?.predicate($0) } }
        nonmutating set { box?.setPredicate(newValue) }
    }

    /// The request's sort descriptors; setting them refetches.
    public var nsSortDescriptors: [NSSortDescriptor] {
        get { request.flatMap { box?.sortDescriptors($0) } ?? [] }
        nonmutating set { box?.setSortDescriptors(newValue) }
    }
}

// MARK: - SectionedFetchRequest

/// A property wrapper type that retrieves entities, grouped into sections, from a Core Data
/// persistent store.
@MainActor
@propertyWrapper
public struct SectionedFetchRequest<SectionIdentifier: Hashable, Result: NSFetchRequestResult>: DynamicProperty {
    @Environment(\.managedObjectContext) private var context
    @StateObject private var box = _FetchBox()
    private let request: NSFetchRequest<Result>
    private let section: (Result) -> SectionIdentifier
    private let animation: Animation?

    /// The fetched results, by section.
    public var wrappedValue: SectionedFetchResults<SectionIdentifier, Result> {
        box.watch(context)
        box.adopt(request)
        return SectionedFetchResults(results: box.fetch(request, in: context), section: section, box: box, request: request)
    }

    nonisolated public mutating func update() {}

    public init(fetchRequest: NSFetchRequest<Result>, sectionIdentifier: KeyPath<Result, SectionIdentifier>, animation: Animation? = nil) {
        request = fetchRequest
        section = { $0[keyPath: sectionIdentifier] }
        self.animation = animation
    }

    public init(fetchRequest: NSFetchRequest<Result>, sectionIdentifier: KeyPath<Result, SectionIdentifier>, transaction: Transaction) {
        self.init(fetchRequest: fetchRequest, sectionIdentifier: sectionIdentifier, animation: transaction.animation)
    }

    public init(entity: NSEntityDescription, sectionIdentifier: KeyPath<Result, SectionIdentifier>, sortDescriptors: [NSSortDescriptor], predicate: NSPredicate? = nil, animation: Animation? = nil) {
        let request = NSFetchRequest<Result>()
        request.entity = entity
        request.sortDescriptors = sortDescriptors
        request.predicate = predicate
        self.init(fetchRequest: request, sectionIdentifier: sectionIdentifier, animation: animation)
    }
}

extension SectionedFetchRequest where Result: NSManagedObject {
    public init(sectionIdentifier: KeyPath<Result, SectionIdentifier>, sortDescriptors: [NSSortDescriptor], predicate: NSPredicate? = nil, animation: Animation? = nil) {
        let request = NSFetchRequest<Result>()
        request.sortDescriptors = sortDescriptors
        request.predicate = predicate
        self.init(fetchRequest: request, sectionIdentifier: sectionIdentifier, animation: animation)
    }
}

/// A collection of results retrieved from a Core Data store, grouped into sections.
public struct SectionedFetchResults<SectionIdentifier: Hashable, Result: NSFetchRequestResult>: RandomAccessCollection {
    /// A collection of fetched results that share a section identifier.
    public struct Section: Identifiable, RandomAccessCollection {
        public let id: SectionIdentifier
        let elements: [Result]
        public var startIndex: Int { elements.startIndex }
        public var endIndex: Int { elements.endIndex }
        public subscript(position: Int) -> Result { elements[position] }
    }

    let sections: [Section]
    let box: _FetchBox?
    let request: NSFetchRequest<Result>?

    init(results: [Result], section: (Result) -> SectionIdentifier, box: _FetchBox?, request: NSFetchRequest<Result>?) {
        var order: [SectionIdentifier] = []
        var grouped: [SectionIdentifier: [Result]] = [:]
        for result in results {
            let id = section(result)
            if grouped[id] == nil { order.append(id) }
            grouped[id, default: []].append(result)
        }
        sections = order.map { Section(id: $0, elements: grouped[$0] ?? []) }
        self.box = box
        self.request = request
    }

    public var startIndex: Int { sections.startIndex }
    public var endIndex: Int { sections.endIndex }
    public subscript(position: Int) -> Section { sections[position] }

    public var nsPredicate: NSPredicate? {
        get { request.flatMap { box?.predicate($0) } }
        nonmutating set { box?.setPredicate(newValue) }
    }

    public var nsSortDescriptors: [NSSortDescriptor] {
        get { request.flatMap { box?.sortDescriptors($0) } ?? [] }
        nonmutating set { box?.setSortDescriptors(newValue) }
    }
}
