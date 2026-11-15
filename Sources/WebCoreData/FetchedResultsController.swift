// Fetched results controllers: a fetch request's results kept current as the context changes,
// split into sections by a key path, with a delegate told what moved. The controller refetches
// once per turn of the event loop after the changes the context sees (an insert, a property
// set, a delete, a save, another context's save), and at once when the context saves or
// processes its pending changes, as Core Data's does at the end of an event. The delegate is
// told the section and object changes between the results before and after: an object that
// left is a delete, one that arrived an insert, and one that changed a move (when its index
// path changed) or an update.
//
// Not Core Data: the caches named by `cacheName` are not kept (a fetch is a fetch from memory
// here), sections follow the order the fetch returns their objects in (Core Data requires the
// first sort descriptor to sort by the section key path), and the delegate's diffable-snapshot
// and collection-difference callbacks are not called.

import WebCombine

/// The kinds of change a fetched results controller reports.
public enum NSFetchedResultsChangeType: UInt, Sendable {
    case insert = 1
    case delete = 2
    case move = 3
    case update = 4
}

/// A section of a fetched results controller's results.
public protocol NSFetchedResultsSectionInfo {
    /// The section's name: the section key path's value for its objects, as text.
    var name: String { get }
    /// The section's index title (the name's first letter, capitalized).
    var indexTitle: String? { get }
    var numberOfObjects: Int { get }
    var objects: [Any]? { get }
}

/// What a fetched results controller tells its delegate when its results change. Every
/// method is optional (an empty default), as Core Data's are.
public protocol NSFetchedResultsControllerDelegate: AnyObject {
    func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>)
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?)
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange sectionInfo: NSFetchedResultsSectionInfo, atSectionIndex sectionIndex: Int, for type: NSFetchedResultsChangeType)
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>)
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, sectionIndexTitleForSectionName sectionName: String) -> String?
}

extension NSFetchedResultsControllerDelegate {
    public func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {}
    public func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {}
    public func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange sectionInfo: NSFetchedResultsSectionInfo, atSectionIndex sectionIndex: Int, for type: NSFetchedResultsChangeType) {}
    public func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {}
    public func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, sectionIndexTitleForSectionName sectionName: String) -> String? {
        _FRCCore.defaultIndexTitle(sectionName)
    }
}

/// A section of the results.
struct _FRCSection: NSFetchedResultsSectionInfo {
    let name: String
    let indexTitle: String?
    var items: [Any]
    var numberOfObjects: Int { items.count }
    var objects: [Any]? { items }
}

/// What a controller and the type-erased view of it its delegate gets share: the request, the
/// context, and the results.
final class _FRCCore: @unchecked Sendable {
    let request: AnyObject
    let context: NSManagedObjectContext
    let sectionNameKeyPath: String?
    let cacheName: String?
    weak var delegate: (any NSFetchedResultsControllerDelegate)?
    /// Fetches the request's results (the typed request, captured where its type is known).
    let fetch: () throws -> [Any]
    var sections: [_FRCSection]?
    /// The controller the delegate gets (`NSFetchedResultsController<NSFetchRequestResult>`).
    var erased: (() -> NSFetchedResultsController<NSFetchRequestResult>?)?

    private var stop: (() -> Void)?
    private var stopObjects: (() -> Void)?
    private var stopPending: (() -> Void)?
    /// The objects changed since the last refetch (by identity).
    private var changed: Set<AnyHashable> = []
    private var dirty = false
    private var scheduled = false

    init(request: AnyObject, context: NSManagedObjectContext, sectionNameKeyPath: String?, cacheName: String?, fetch: @escaping () throws -> [Any]) {
        self.request = request
        self.context = context
        self.sectionNameKeyPath = sectionNameKeyPath
        self.cacheName = cacheName
        self.fetch = fetch
    }

    deinit {
        stop?()
        stopObjects?()
        stopPending?()
    }

    /// An item's identity in the results: a managed object's own, another value's equality.
    static func key(_ item: Any) -> AnyHashable {
        if let object = item as? NSManagedObject { return ObjectIdentifier(object) }
        return item as? AnyHashable ?? AnyHashable("\(item)")
    }

    static func defaultIndexTitle(_ name: String) -> String? {
        guard let first = name.first else { return nil }
        return String(first).uppercased()
    }

    var fetchedObjects: [Any]? { sections.map { $0.flatMap(\.items) } }

    func performFetch() throws {
        sections = try group(fetch())
        dirty = false
        changed = []
        guard stop == nil else { return }
        stop = context._observe { [weak self] _ in self?.contextChanged() }
        stopObjects = context._observeObjects { [weak self] object in self?.changed.insert(Self.key(object)) }
        stopPending = context._observePendingChanges { [weak self] in self?.flush() }
    }

    private func contextChanged() {
        dirty = true
        guard !scheduled else { return }
        scheduled = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.scheduled = false
            self.flush()
        }
    }

    /// Refetches if the context changed, and tells the delegate what changed.
    func flush() {
        guard dirty, let old = sections else { return }
        dirty = false
        let changedNow = changed
        changed = []
        guard let new = try? group(fetch()) else { return }
        sections = new
        guard let delegate, let controller = erased?() ?? nil else { return }

        let key = Self.key
        func paths(_ sections: [_FRCSection]) -> [AnyHashable: IndexPath] {
            var result: [AnyHashable: IndexPath] = [:]
            for (s, section) in sections.enumerated() {
                for (r, item) in section.items.enumerated() { result[key(item)] = IndexPath(indexes: [s, r]) }
            }
            return result
        }
        let oldPaths = paths(old), newPaths = paths(new)
        let oldNames = old.map(\.name), newNames = new.map(\.name)

        var sectionChanges: [(NSFetchedResultsSectionInfo, Int, NSFetchedResultsChangeType)] = []
        for (index, section) in old.enumerated() where !newNames.contains(section.name) { sectionChanges.append((section, index, .delete)) }
        for (index, section) in new.enumerated() where !oldNames.contains(section.name) { sectionChanges.append((section, index, .insert)) }

        var objectChanges: [(Any, IndexPath?, NSFetchedResultsChangeType, IndexPath?)] = []
        for (s, section) in old.enumerated() {
            for (r, item) in section.items.enumerated() where newPaths[key(item)] == nil {
                objectChanges.append((item, IndexPath(indexes: [s, r]), .delete, nil))
            }
        }
        for (s, section) in new.enumerated() {
            for (r, item) in section.items.enumerated() {
                let here = IndexPath(indexes: [s, r])
                guard let before = oldPaths[key(item)] else {
                    objectChanges.append((item, nil, .insert, here))
                    continue
                }
                guard changedNow.contains(key(item)) else { continue }
                if before == here { objectChanges.append((item, before, .update, nil)) }
                else { objectChanges.append((item, before, .move, here)) }
            }
        }
        guard !sectionChanges.isEmpty || !objectChanges.isEmpty else { return }

        delegate.controllerWillChangeContent(controller)
        for (section, index, type) in sectionChanges { delegate.controller(controller, didChange: section, atSectionIndex: index, for: type) }
        for (item, at, type, to) in objectChanges { delegate.controller(controller, didChange: item, at: at, for: type, newIndexPath: to) }
        delegate.controllerDidChangeContent(controller)
    }

    /// Splits the results into sections by the section key path (one section without one).
    private func group(_ items: [Any]) -> [_FRCSection] {
        guard let keyPath = sectionNameKeyPath else {
            return [_FRCSection(name: "", indexTitle: nil, items: items)]
        }
        var order: [String] = []
        var members: [String: [Any]] = [:]
        for item in items {
            let value = _cdUnwrap(_cdValue(of: item, keyPath: keyPath))
            let name = value.map { "\($0)" } ?? ""
            if members[name] == nil { order.append(name) }
            members[name, default: []].append(item)
        }
        let controller = erased?() ?? nil
        return order.map { name in
            var title = Self.defaultIndexTitle(name)
            if let delegate, let controller { title = delegate.controller(controller, sectionIndexTitleForSectionName: name) }
            return _FRCSection(name: name, indexTitle: title, items: members[name] ?? [])
        }
    }
}

/// A controller that keeps a fetch request's results for a table or collection view, current
/// as the context changes.
open class NSFetchedResultsController<ResultType>: @unchecked Sendable {
    let _core: _FRCCore
    private let _request: NSFetchRequest<ResultType>

    /// A controller over the request's results in the context, split into sections by the key
    /// path's value (one section without one).
    public init(fetchRequest: NSFetchRequest<ResultType>, managedObjectContext context: NSManagedObjectContext, sectionNameKeyPath: String?, cacheName name: String?) {
        _request = fetchRequest
        _core = _FRCCore(request: fetchRequest, context: context, sectionNameKeyPath: sectionNameKeyPath, cacheName: name) {
            if fetchRequest.entity == nil, fetchRequest.entityName == nil, let type = ResultType.self as? NSManagedObject.Type {
                fetchRequest.entity = type._entity(in: context)
            }
            return try context.fetch(fetchRequest)
        }
        _core.erased = { [weak self] in self?._erased }
    }

    /// The delegate's view of a controller: the same results, as `NSFetchRequestResult`s.
    init(_sharing core: _FRCCore, request: NSFetchRequest<ResultType>) {
        _core = core
        _request = request
    }

    private var _erasedView: NSFetchedResultsController<NSFetchRequestResult>?
    var _erased: NSFetchedResultsController<NSFetchRequestResult> {
        if let same = self as? NSFetchedResultsController<NSFetchRequestResult> { return same }
        if let _erasedView { return _erasedView }
        let request = _request as? NSFetchRequest<NSFetchRequestResult> ?? _request._erasedCopy()
        let view = NSFetchedResultsController<NSFetchRequestResult>(_sharing: _core, request: request)
        _erasedView = view
        return view
    }

    open var fetchRequest: NSFetchRequest<ResultType> { _request }
    open var managedObjectContext: NSManagedObjectContext { _core.context }
    open var sectionNameKeyPath: String? { _core.sectionNameKeyPath }
    open var cacheName: String? { _core.cacheName }

    open var delegate: (any NSFetchedResultsControllerDelegate)? {
        get { _core.delegate }
        set { _core.delegate = newValue }
    }

    /// Fetches the results, and from then on keeps them current.
    open func performFetch() throws { try _core.performFetch() }

    /// Core Data's caches are not kept here, so there is none to delete.
    open class func deleteCache(withName name: String?) {}

    /// The results, or nil before `performFetch()`.
    open var fetchedObjects: [ResultType]? { _core.fetchedObjects?.compactMap { $0 as? ResultType } }

    open var sections: [any NSFetchedResultsSectionInfo]? { _core.sections?.map { $0 as any NSFetchedResultsSectionInfo } }

    /// The object at the index path (section, then row).
    open func object(at indexPath: IndexPath) -> ResultType {
        guard let sections = _core.sections, indexPath.count == 2, sections.indices.contains(indexPath[0]),
              sections[indexPath[0]].items.indices.contains(indexPath[1]),
              let object = sections[indexPath[0]].items[indexPath[1]] as? ResultType
        else { fatalError("NSFetchedResultsController: no object at index path \(indexPath)") }
        return object
    }

    /// The index path of the object in the results, or nil if they do not hold it.
    open func indexPath(forObject object: ResultType) -> IndexPath? {
        guard let sections = _core.sections else { return nil }
        let target = _FRCCore.key(object)
        for (s, section) in sections.enumerated() {
            if let r = section.items.firstIndex(where: { _FRCCore.key($0) == target }) { return IndexPath(indexes: [s, r]) }
        }
        return nil
    }

    /// The index title for a section name (the name's first letter, capitalized).
    open func sectionIndexTitle(forSectionName sectionName: String) -> String? { _FRCCore.defaultIndexTitle(sectionName) }

    /// The sections' index titles, without repeats.
    open var sectionIndexTitles: [String] {
        var titles: [String] = []
        for title in (_core.sections ?? []).compactMap(\.indexTitle) where !titles.contains(title) { titles.append(title) }
        return titles
    }

    /// The first section whose index title is the title (or the index given, if none is).
    open func section(forSectionIndexTitle title: String, at sectionIndex: Int) -> Int {
        (_core.sections ?? []).firstIndex { $0.indexTitle == title } ?? sectionIndex
    }
}

extension NSFetchRequest {
    /// The same request, as one for `NSFetchRequestResult`s (the delegate's controller's).
    func _erasedCopy() -> NSFetchRequest<NSFetchRequestResult> {
        let copy = NSFetchRequest<NSFetchRequestResult>()
        copy.entityName = entityName
        if let entity { copy.entity = entity }
        copy.predicate = predicate
        copy.sortDescriptors = sortDescriptors
        copy.fetchLimit = fetchLimit
        copy.fetchOffset = fetchOffset
        copy.fetchBatchSize = fetchBatchSize
        copy.includesSubentities = includesSubentities
        copy.includesPendingChanges = includesPendingChanges
        copy.resultType = resultType
        copy.propertiesToFetch = propertiesToFetch
        copy.returnsDistinctResults = returnsDistinctResults
        return copy
    }
}
