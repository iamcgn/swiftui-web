// Contexts: the scratchpads objects live in. A context fetches from its store coordinator (or
// from its parent context), tracks what changed, and on `save()` writes the changes to the
// stores (or pushes them into its parent). Every context sees the stores' current rows when it
// fetches: an object it holds with no unsaved changes takes the stored values (what Core Data's
// `automaticallyMergesChangesFromParent` and `mergeChanges(fromContextDidSave:)` give).
//
// Not Core Data: blocks passed to `perform` run at once, on the caller's thread (Core Data
// queues them on the context's queue); merge policies are recorded, and a save's values win
// over the store's (`mergeByPropertyObjectTrump`).

import WebCombine

/// Constants that indicate the concurrency pattern of a context.
public enum NSManagedObjectContextConcurrencyType: UInt, Sendable {
    case confinementConcurrencyType = 0
    case privateQueueConcurrencyType = 1
    case mainQueueConcurrencyType = 2
}

/// A policy object that resolves conflicts between the persistent store and in-memory objects.
open class NSMergePolicy: @unchecked Sendable {
    public enum MergePolicyType: UInt, Sendable {
        case errorMergePolicyType = 0, mergeByPropertyStoreTrumpMergePolicyType, mergeByPropertyObjectTrumpMergePolicyType
        case overwriteMergePolicyType, rollbackMergePolicyType
    }
    public let mergeType: MergePolicyType
    public init(merge ty: MergePolicyType) { mergeType = ty }

    public static let error = NSMergePolicy(merge: .errorMergePolicyType)
    public static let mergeByPropertyStoreTrump = NSMergePolicy(merge: .mergeByPropertyStoreTrumpMergePolicyType)
    public static let mergeByPropertyObjectTrump = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
    public static let overwrite = NSMergePolicy(merge: .overwriteMergePolicyType)
    public static let rollback = NSMergePolicy(merge: .rollbackMergePolicyType)
}

nonisolated(unsafe) public let NSErrorMergePolicy: Any = NSMergePolicy.error
nonisolated(unsafe) public let NSMergeByPropertyStoreTrumpMergePolicy: Any = NSMergePolicy.mergeByPropertyStoreTrump
nonisolated(unsafe) public let NSMergeByPropertyObjectTrumpMergePolicy: Any = NSMergePolicy.mergeByPropertyObjectTrump
nonisolated(unsafe) public let NSOverwriteMergePolicy: Any = NSMergePolicy.overwrite
nonisolated(unsafe) public let NSRollbackMergePolicy: Any = NSMergePolicy.rollback

// The keys of a save notification's user info.
public let NSInsertedObjectsKey = "inserted"
public let NSUpdatedObjectsKey = "updated"
public let NSDeletedObjectsKey = "deleted"
public let NSRefreshedObjectsKey = "refreshed"
public let NSInvalidatedObjectsKey = "invalidated"
public let NSInvalidatedAllObjectsKey = "invalidatedAll"

extension Notification.Name {
    public static let NSManagedObjectContextWillSave = Notification.Name("NSManagedObjectContextWillSaveNotification")
    public static let NSManagedObjectContextDidSave = Notification.Name("NSManagedObjectContextDidSaveNotification")
    public static let NSManagedObjectContextObjectsDidChange = Notification.Name("NSManagedObjectContextObjectsDidChangeNotification")
    public static let NSPersistentStoreRemoteChange = Notification.Name("NSPersistentStoreRemoteChangeNotification")
}

/// A relationship's value in a row: the keys (`Entity/p3`) of the objects it holds.
enum _CDRef {
    case one(String)
    case many([String], ordered: Bool)
}

/// An object's values as a row: attributes as values, relationships as `_CDRef`s.
typealias _CDRow = [String: Any]

/// An object that represents a single object space or scratch pad that you use to fetch,
/// create, and save managed objects.
open class NSManagedObjectContext: CustomStringConvertible, @unchecked Sendable {
    public let concurrencyType: NSManagedObjectContextConcurrencyType
    public var name: String?
    public var transactionAuthor: String?
    /// Recorded; a context here always takes the stores' rows when it fetches.
    public var automaticallyMergesChangesFromParent = false
    public var mergePolicy: Any = NSMergePolicy.error
    public var stalenessInterval: TimeInterval = -1
    public var shouldDeleteInaccessibleFaults = true
    public var retainsRegisteredObjects = false
    public var propagatesDeletesAtEndOfEvent = true
    public var userInfo: [AnyHashable: Any] = [:]

    private var _coordinator: NSPersistentStoreCoordinator?
    /// The coordinator the context fetches from and saves to (its parent's, for a child).
    public var persistentStoreCoordinator: NSPersistentStoreCoordinator? {
        get { _coordinator ?? parent?.persistentStoreCoordinator }
        set {
            _coordinator = newValue
            newValue?._attach(self)
        }
    }
    /// The parent context: a save pushes the changes there instead of to the stores.
    public var parent: NSManagedObjectContext? {
        didSet { _syncedVersion = -1 }
    }

    var _model: NSManagedObjectModel? { persistentStoreCoordinator?.managedObjectModel }

    /// The objects the context holds, by ID key (`Entity/p3`, `Entity/t17`).
    var _registered: [String: NSManagedObject] = [:]
    private var _inserted: [NSManagedObject] = []
    private var _deleted: [NSManagedObject] = []
    /// Counts the context's changes (a child context syncs when its parent's count moved).
    private(set) var _version = 0
    /// The source version (the coordinator's generation, or the parent's version) last synced.
    private var _syncedVersion = -1
    private var _observers: [Int: (Bool) -> Void] = [:]
    private var _nextObserver = 0

    public init(concurrencyType ct: NSManagedObjectContextConcurrencyType) {
        concurrencyType = ct
    }

    @available(*, deprecated, message: "Use init(concurrencyType:)")
    public convenience init() { self.init(concurrencyType: .confinementConcurrencyType) }

    // MARK: State

    public var hasChanges: Bool { !_inserted.isEmpty || !_deleted.isEmpty || _registered.values.contains { $0.isUpdated } }
    public var insertedObjects: Set<NSManagedObject> { Set(_inserted) }
    public var updatedObjects: Set<NSManagedObject> { Set(_registered.values.filter { $0.isUpdated }) }
    public var deletedObjects: Set<NSManagedObject> { Set(_deleted) }
    public var registeredObjects: Set<NSManagedObject> { Set(_registered.values) }

    // MARK: Observing (the SwiftUI fetch requests)

    /// Tells `run` after every change and every save the context sees; `run` gets whether the
    /// change happened on the main actor (in a main-queue context).
    func _observe(_ run: @escaping (Bool) -> Void) -> () -> Void {
        _nextObserver += 1
        let id = _nextObserver
        _observers[id] = run
        return { [weak self] in self?._observers[id] = nil }
    }

    private func _tellObservers(onMain: Bool) {
        for observer in Array(_observers.values) { observer(onMain) }
    }

    /// An object changed (a property set, an object inserted or deleted).
    func _objectDidChange(_ object: NSManagedObject) {
        _version += 1
        _tellObservers(onMain: concurrencyType == .mainQueueConcurrencyType)
    }

    /// The stores changed (another context saved, or a batch request ran): the next fetch
    /// takes the new rows, and fetch requests refetch.
    func _sourceDidChange(onMain: Bool) {
        _tellObservers(onMain: onMain)
    }

    // MARK: Registering

    func _register(_ object: NSManagedObject) {
        object.managedObjectContext = self
        _registered[object.objectID._key] = object
    }

    func _unregister(_ object: NSManagedObject) {
        if _registered[object.objectID._key] === object { _registered[object.objectID._key] = nil }
    }

    /// The object's ID changed (saved: temporary to permanent).
    func _rekey(_ object: NSManagedObject, from oldKey: String) {
        if _registered[oldKey] === object { _registered[oldKey] = nil }
        _registered[object.objectID._key] = object
    }

    /// Registers an object with the context (an object made with `insertInto: nil`, or one
    /// deleted and inserted again).
    open func insert(_ object: NSManagedObject) {
        if object.managedObjectContext === self {
            if object.isDeleted {
                object.isDeleted = false
                _deleted.removeAll { $0 === object }
                _objectDidChange(object)
            }
            return
        }
        _register(object)
        object.isInserted = true
        _inserted.append(object)
        object.awakeFromInsert()
        // Values set before the insert count as changes.
        for key in object._values.keys { object._changedKeys.insert(key) }
        _objectDidChange(object)
    }

    /// Marks the object to be deleted from its store at the next save; its relationships'
    /// delete rules run now (nullify, cascade, deny).
    open func delete(_ object: NSManagedObject) {
        guard object.managedObjectContext === self, !object.isDeleted else { return }
        object.prepareForDeletion()
        if object.isInserted {
            object.isInserted = false
            _inserted.removeAll { $0 === object }
            object.isDeleted = true
        } else {
            object.isDeleted = true
            _deleted.append(object)
        }
        for case let relationship as NSRelationshipDescription in object.entity.properties {
            let targets = object._targets(relationship.name)
            guard !targets.isEmpty else { continue }
            switch relationship.deleteRule {
            case .denyDeleteRule:
                object._deniedBy = relationship.name
            case .cascadeDeleteRule:
                for target in targets { delete(target) }
            case .nullifyDeleteRule, .noActionDeleteRule:
                break
            }
            if relationship.deleteRule != .noActionDeleteRule, let inverse = relationship.inverseRelationship {
                for target in targets where !target.isDeleted { target._inverseRemove(inverse, object) }
            }
        }
        if !_inserted.contains(where: { $0 === object }) && !_deleted.contains(where: { $0 === object }) {
            // An inserted object deleted before a save: it was never stored.
            _unregister(object)
            _objectDidChange(object)
            object.managedObjectContext = nil
            return
        }
        _objectDidChange(object)
    }

    // MARK: Fetching

    /// The rows the context's source holds now: the stores' (a root context) or the parent's
    /// objects as they are in the parent (a child context).
    private func _sourceVersion() -> Int {
        if let parent {
            parent._sync()
            return parent._version
        }
        return persistentStoreCoordinator?._generation ?? 0
    }

    private func _sourceRows() -> [String: _CDRow] {
        if let parent {
            var rows: [String: _CDRow] = [:]
            for object in parent._registered.values where !object.isDeleted {
                rows[object.objectID._key] = _cdRow(of: object)
            }
            return rows
        }
        return persistentStoreCoordinator?._rows() ?? [:]
    }

    /// Takes the source's rows: objects not held yet are made, held objects with no unsaved
    /// changes take the rows' values, and held objects whose rows are gone are let go.
    func _sync(force: Bool = false) {
        let coordinator = persistentStoreCoordinator
        // Objects saved since they were registered here: their permanent keys.
        if let coordinator, !coordinator._permanentKeys.isEmpty {
            for (key, object) in _registered where object.objectID.isTemporaryID {
                guard let permanent = coordinator._permanentKeys[key], let id = coordinator._objectID(forKey: permanent) else { continue }
                object.objectID = id
                _rekey(object, from: key)
                if let index = _inserted.firstIndex(where: { $0 === object }), parent == nil {
                    // Saved by another context: no longer an insertion here.
                    _inserted.remove(at: index)
                    object.isInserted = false
                }
            }
        }
        let version = _sourceVersion()
        guard force || version != _syncedVersion else { return }
        _syncedVersion = version
        let rows = _sourceRows()

        _cdApplyingSnapshot = true
        defer { _cdApplyingSnapshot = false }

        // Gone from the source: let go, unless this context changed or inserted them.
        for (key, object) in _registered where rows[key] == nil && !object.hasChanges {
            object.managedObjectContext = nil
            _registered[key] = nil
        }
        var made: [NSManagedObject] = []
        var refreshed: [(NSManagedObject, _CDRow)] = []
        for key in rows.keys.sorted(by: _cdKeyOrder) {
            guard let row = rows[key] else { continue }
            if let object = _registered[key] {
                guard !object.hasChanges else { continue }
                refreshed.append((object, row))
                continue
            }
            guard let id = _objectID(forKey: key) else { continue }
            let object = id.entity.managedObjectClass.init(entity: id.entity, insertInto: nil)
            object.objectID = id
            object._values = [:]
            _register(object)
            made.append(object)
            refreshed.append((object, row))
        }
        // Attributes first, then relationships (every object of the rows is registered now).
        for (object, row) in refreshed {
            for (key, value) in row where !(value is _CDRef) { object._values[key] = value }
            for property in object.entity.properties where row[property.name] == nil && !property.isTransient {
                object._values[property.name] = nil
            }
        }
        for (object, row) in refreshed {
            for case let relationship as NSRelationshipDescription in object.entity.properties {
                switch row[relationship.name] as? _CDRef {
                case .one(let key)?:
                    object._values[relationship.name] = _registered[key]
                case .many(let keys, let ordered)?:
                    let objects = keys.compactMap { _registered[$0] }
                    if ordered {
                        var set = NSOrderedSet()
                        for object in objects { set._append(object) }
                        object._values[relationship.name] = set
                    } else {
                        object._values[relationship.name] = Set<AnyHashable>(objects.map { AnyHashable($0) })
                    }
                case nil:
                    object._values[relationship.name] = relationship.isToMany ? (relationship.isOrdered ? NSOrderedSet() as Any : Set<AnyHashable>() as Any) : nil
                }
            }
            object._committed = object._values
            object._changedKeys = []
        }
        _cdApplyingSnapshot = false
        for object in made { object.awakeFromFetch() }
        if !refreshed.isEmpty { _version += 1 }
    }

    /// The ID a key names, in this context's source.
    private func _objectID(forKey key: String) -> NSManagedObjectID? {
        if let parent, let object = parent._registered[key] { return object.objectID }
        return persistentStoreCoordinator?._objectID(forKey: key)
    }

    /// The objects that satisfy the request, in its order.
    func _entity<T>(of request: NSFetchRequest<T>) -> NSEntityDescription? {
        if let entity = request.entity { return entity }
        guard let name = request.entityName else { return nil }
        return _model?.entitiesByName[name] ?? _CDModelRegistry.entity(named: name)
    }

    func _objects<T>(for request: NSFetchRequest<T>) throws -> [NSManagedObject] {
        _sync()
        guard let entity = _entity(of: request) else {
            throw NSError(domain: NSCocoaErrorDomain, code: 134060, userInfo: [NSLocalizedDescriptionKey: "A fetch request must have an entity (\(request.entityName ?? "none named"))."])
        }
        var objects = _registered.values.filter { object in
            !object.isDeleted && (object.entity === entity || (request.includesSubentities && object.entity.isKindOf(entity: entity))
                || (object.entity.name == entity.name))
        }
        if !request.includesPendingChanges { objects.removeAll { $0.isInserted } }
        objects.sort { _cdKeyOrder($0.objectID._key, $1.objectID._key) }
        if let predicate = request.predicate { objects = objects.filter { predicate.evaluate(with: $0) } }
        var sorted = NSSortDescriptor._sort(objects, by: request.sortDescriptors ?? []).compactMap { $0 as? NSManagedObject }
        if request.fetchOffset > 0 { sorted = Array(sorted.dropFirst(request.fetchOffset)) }
        if request.fetchLimit > 0 { sorted = Array(sorted.prefix(request.fetchLimit)) }
        return sorted
    }

    /// Returns an array of items of the type the request names that meet its criteria.
    open func fetch<T>(_ request: NSFetchRequest<T>) throws -> [T] {
        let objects = try _objects(for: request)
        switch request.resultType {
        case .managedObjectResultType:
            return objects.compactMap { $0 as? T }
        case .managedObjectIDResultType:
            return objects.compactMap { $0.objectID as? T }
        case .countResultType:
            return [NSNumber(value: objects.count)].compactMap { $0 as? T }
        case .dictionaryResultType:
            let all: [Any] = _entity(of: request).map { $0.attributesByName.keys.sorted() } ?? []
            let names: [String] = (request.propertiesToFetch ?? all).compactMap { property in
                if let name = property as? String { return name }
                if let description = property as? NSPropertyDescription { return description.name }
                if let description = property as? NSExpressionDescription { return description.name }
                return nil
            }
            var rows: [[String: Any]] = objects.map { object in
                var row: [String: Any] = [:]
                for name in names {
                    if let value = _cdValue(of: object, keyPath: name) {
                        if let related = value as? NSManagedObject { row[name] = related.objectID } else { row[name] = value }
                    }
                }
                return row
            }
            if request.returnsDistinctResults {
                var seen: [String] = []
                rows = rows.filter { row in
                    let signature = names.map { "\(row[$0] ?? "nil")" }.joined(separator: "\u{1F}")
                    if seen.contains(signature) { return false }
                    seen.append(signature)
                    return true
                }
            }
            return rows.compactMap { $0 as? T }
        }
    }

    /// The number of objects the request would return.
    open func count<T>(for request: NSFetchRequest<T>) throws -> Int {
        try _objects(for: request).count
    }

    /// The object with the ID (made from its row if the context does not hold it yet).
    open func object(with objectID: NSManagedObjectID) -> NSManagedObject {
        if let object = _registered[objectID._key] { return object }
        _sync()
        if let object = _registered[objectID._key] { return object }
        // A deleted or unknown ID: an object of the entity with no values (Core Data's fault,
        // which raises when it is read).
        let object = objectID.entity.managedObjectClass.init(entity: objectID.entity, insertInto: nil)
        object.objectID = objectID
        object.managedObjectContext = self
        return object
    }

    /// The object with the ID, or an error when no store holds it.
    open func existingObject(with objectID: NSManagedObjectID) throws -> NSManagedObject {
        if let object = _registered[objectID._key] { return object }
        _sync()
        if let object = _registered[objectID._key] { return object }
        throw NSError(domain: NSCocoaErrorDomain, code: 133000, userInfo: [NSLocalizedDescriptionKey: "No object with the ID \(objectID)."])
    }

    /// The object with the ID if the context holds it.
    open func registeredObject(for objectID: NSManagedObjectID) -> NSManagedObject? { _registered[objectID._key] }

    /// Runs a store request: a batch delete removes the matching rows from the stores.
    open func execute(_ request: NSPersistentStoreRequest) throws -> NSPersistentStoreResult {
        if let fetch = request as? NSFetchRequest<NSFetchRequestResult> {
            return NSAsynchronousFetchResult(finalResult: try self.fetch(fetch).map { $0 as Any })
        }
        guard let delete = request as? NSBatchDeleteRequest else {
            throw NSError(domain: NSCocoaErrorDomain, code: 134091, userInfo: [NSLocalizedDescriptionKey: "Unsupported store request \(type(of: request))."])
        }
        guard let coordinator = persistentStoreCoordinator else {
            throw NSError(domain: NSCocoaErrorDomain, code: 134060, userInfo: [NSLocalizedDescriptionKey: "The context has no coordinator."])
        }
        var ids = delete.objectIDs ?? []
        if let fetch = delete.fetchRequest {
            // The stores' rows, not this context's unsaved changes (a batch request runs in
            // the store).
            let scratch = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
            scratch.persistentStoreCoordinator = coordinator
            let saved = fetch.includesPendingChanges
            fetch.includesPendingChanges = false
            defer { fetch.includesPendingChanges = saved }
            ids = try scratch._objects(for: fetch).map(\.objectID)
        }
        try coordinator._deleteRows(ids.map(\._key), by: self)
        switch delete.resultType {
        case .resultTypeStatusOnly: return NSBatchDeleteResult(result: true)
        case .resultTypeObjectIDs: return NSBatchDeleteResult(result: ids)
        case .resultTypeCount: return NSBatchDeleteResult(result: ids.count)
        }
    }

    /// Merges the objects a save notification names (here: the context takes the stores' rows).
    open func mergeChanges(fromContextDidSave notification: Notification) {
        _sync(force: true)
        _tellObservers(onMain: concurrencyType == .mainQueueConcurrencyType)
    }

    /// Merges a remote save's changes into the contexts (they take the stores' rows).
    open class func mergeChanges(fromRemoteContextSave changeNotificationData: [AnyHashable: Any], into contexts: [NSManagedObjectContext]) {
        for context in contexts { context.mergeChanges(fromContextDidSave: Notification(name: .NSManagedObjectContextDidSave)) }
    }

    // MARK: Saving

    /// Writes the context's changes to its stores (or into its parent).
    open func save() throws {
        guard hasChanges else { return }
        NotificationCenter.default.post(name: .NSManagedObjectContextWillSave, object: self, userInfo: nil)
        let inserted = _inserted
        let deleted = _deleted
        let updated = _registered.values.filter { $0.isUpdated }.sorted { _cdKeyOrder($0.objectID._key, $1.objectID._key) }
        for object in inserted + updated { object.willSave() }
        for object in inserted { try object.validateForInsert() }
        for object in updated { try object.validateForUpdate() }
        for object in deleted { try object.validateForDelete() }

        if let parent {
            _push(into: parent, inserted: inserted, updated: updated, deleted: deleted)
        } else {
            guard let coordinator = persistentStoreCoordinator, !coordinator.persistentStores.isEmpty else {
                throw NSError(domain: NSCocoaErrorDomain, code: 134060, userInfo: [NSLocalizedDescriptionKey: "This context has no persistent stores to save to."])
            }
            try coordinator._save(inserted: inserted, updated: updated, deleted: deleted, by: self)
        }

        for object in deleted {
            _unregister(object)
            object.managedObjectContext = nil
        }
        _inserted = []
        _deleted = []
        for object in inserted + updated {
            object.isInserted = false
            object._changedKeys = []
            object._committed = object._values
            object.didSave()
        }
        for object in deleted { object.didSave() }
        _version += 1
        if parent == nil { _syncedVersion = persistentStoreCoordinator?._generation ?? _syncedVersion }
        NotificationCenter.default.post(name: .NSManagedObjectContextDidSave, object: self, userInfo: [
            NSInsertedObjectsKey: Set(inserted), NSUpdatedObjectsKey: Set(updated), NSDeletedObjectsKey: Set(deleted),
        ])
        _tellObservers(onMain: concurrencyType == .mainQueueConcurrencyType)
    }

    /// A child's save: the parent holds the inserted objects (with the same IDs), takes the
    /// changed values, and deletes the deleted objects.
    private func _push(into parent: NSManagedObjectContext, inserted: [NSManagedObject], updated: [NSManagedObject], deleted: [NSManagedObject]) {
        parent._sync()
        var counterpart: [ObjectIdentifier: NSManagedObject] = [:]
        for object in inserted {
            let copy = object.entity.managedObjectClass.init(entity: object.entity, insertInto: nil)
            copy.objectID = object.objectID
            copy._values = [:]
            parent._register(copy)
            copy.isInserted = true
            parent._inserted.append(copy)
            counterpart[ObjectIdentifier(object)] = copy
        }
        func inParent(_ object: NSManagedObject) -> NSManagedObject? {
            counterpart[ObjectIdentifier(object)] ?? parent._registered[object.objectID._key]
        }
        for object in inserted + updated {
            guard let target = inParent(object) else { continue }
            let keys = object.isInserted ? Set(object._values.keys).union(object._changedKeys) : object._changedKeys
            for key in keys {
                if let relationship = object.entity.relationshipsByName[key] {
                    let objects = object._targets(key).compactMap(inParent)
                    target._setRelationship(relationship, relationship.isToMany ? objects as Any : objects.first as Any)
                } else {
                    target.setValue(object._values[key], forKey: key)
                }
            }
        }
        for object in deleted {
            if let target = parent._registered[object.objectID._key] { parent.delete(target) }
        }
        parent._version += 1
        parent._tellObservers(onMain: concurrencyType == .mainQueueConcurrencyType)
    }

    /// Discards the context's unsaved changes.
    open func rollback() {
        for object in _inserted {
            object.isInserted = false
            _unregister(object)
            object.managedObjectContext = nil
        }
        _inserted = []
        for object in _deleted { object.isDeleted = false; object._deniedBy = nil }
        _deleted = []
        for object in _registered.values where !object._changedKeys.isEmpty || object.isDeleted {
            object._values = object._committed
            object._changedKeys = []
            object.isDeleted = false
        }
        _version += 1
        _tellObservers(onMain: concurrencyType == .mainQueueConcurrencyType)
    }

    /// Lets go of every object the context holds.
    open func reset() {
        for object in _registered.values { object.managedObjectContext = nil }
        _registered = [:]
        _inserted = []
        _deleted = []
        _syncedVersion = -1
        _version += 1
        _tellObservers(onMain: concurrencyType == .mainQueueConcurrencyType)
    }

    /// The object takes its stored values again (`mergeChanges` keeps its unsaved changes).
    open func refresh(_ object: NSManagedObject, mergeChanges flag: Bool) {
        guard !flag, object.managedObjectContext === self, !object.isInserted else { return }
        object._values = object._committed
        object._changedKeys = []
        _sync(force: true)
    }

    /// Every object without unsaved changes takes its stored values again.
    open func refreshAllObjects() { _sync(force: true) }

    open func processPendingChanges() {}

    /// Gives the objects their permanent IDs now (here: the IDs they get when saved, assigned
    /// at the save).
    open func obtainPermanentIDs(for objects: [NSManagedObject]) throws {}

    open func shouldHandleInaccessibleFault(_ fault: NSManagedObject, for oid: NSManagedObjectID, triggeredByProperty property: NSPropertyDescription?) -> Bool { true }

    // MARK: Running work

    /// Runs the block (at once here; Core Data runs it on the context's queue).
    open func perform(_ block: @escaping () -> Void) { block() }

    /// Runs the block and returns when it has run.
    open func performAndWait(_ block: () -> Void) { block() }

    /// Runs the block and returns its value.
    public func performAndWait<T>(_ block: () throws -> T) rethrows -> T { try block() }

    /// How an asynchronous `perform` schedules its block.
    public enum ScheduledTaskType: Sendable {
        case immediate, enqueued
    }

    /// Runs the block on the context and returns its value.
    nonisolated(nonsending) public func perform<T>(schedule: ScheduledTaskType = .immediate, _ block: @escaping () throws -> T) async rethrows -> T {
        try block()
    }

    open var description: String { "<NSManagedObjectContext: \(name ?? "unnamed"), \(_registered.count) objects>" }

    // MARK: Notification names, as Core Data spells them on the class

    public static let willSaveObjectsNotification = Notification.Name.NSManagedObjectContextWillSave
    public static let didSaveObjectsNotification = Notification.Name.NSManagedObjectContextDidSave
    public static let didChangeObjectsNotification = Notification.Name.NSManagedObjectContextObjectsDidChange
    public static let didMergeChangesObjectIDsNotification = Notification.Name("NSManagedObjectContextDidMergeChangesObjectIDsNotification")
    public static let didSaveObjectIDsNotification = Notification.Name("NSManagedObjectContextDidSaveObjectIDsNotification")

    /// The keys of a change notification's user info.
    public struct NotificationKey: RawRepresentable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let insertedObjects = NotificationKey(rawValue: NSInsertedObjectsKey)
        public static let updatedObjects = NotificationKey(rawValue: NSUpdatedObjectsKey)
        public static let deletedObjects = NotificationKey(rawValue: NSDeletedObjectsKey)
        public static let refreshedObjects = NotificationKey(rawValue: NSRefreshedObjectsKey)
        public static let invalidatedObjects = NotificationKey(rawValue: NSInvalidatedObjectsKey)
        public static let invalidatedAllObjects = NotificationKey(rawValue: NSInvalidatedAllObjectsKey)
    }
}

/// The order objects come out of a store: by entity, saved objects by number, then the
/// inserted ones in the order they were made.
func _cdKeyOrder(_ lhs: String, _ rhs: String) -> Bool {
    func parts(_ key: String) -> (String, Int, Int) {
        guard let slash = key.lastIndex(of: "/") else { return (key, 0, 0) }
        let entity = String(key[..<slash])
        let tail = key[key.index(after: slash)...]
        let temporary = tail.first == "t" ? 1 : 0
        return (entity, temporary, Int(tail.dropFirst()) ?? 0)
    }
    let a = parts(lhs), b = parts(rhs)
    if a.1 != b.1 { return a.1 < b.1 }
    if a.1 == 1 { return a.2 < b.2 }   // inserted objects: in the order they were made
    return (a.0, a.2) < (b.0, b.2)
}

/// An object's row: its persistent attributes and its relationships as keys.
func _cdRow(of object: NSManagedObject) -> _CDRow {
    var row: _CDRow = [:]
    for property in object.entity.properties where !property.isTransient {
        if let relationship = property as? NSRelationshipDescription {
            let targets = object._targets(relationship.name).filter { !$0.isDeleted }
            if relationship.isToMany {
                row[relationship.name] = _CDRef.many(targets.map(\.objectID._key), ordered: relationship.isOrdered)
            } else if let target = targets.first {
                row[relationship.name] = _CDRef.one(target.objectID._key)
            }
        } else if let value = object._values[property.name] {
            row[property.name] = value
        }
    }
    return row
}

// MARK: - Fetch requests

/// The types of a fetch request's results.
public enum NSFetchRequestResultType: UInt, Sendable {
    case managedObjectResultType = 0
    case managedObjectIDResultType = 1
    case dictionaryResultType = 2
    case countResultType = 4
}

public enum NSPersistentStoreRequestType: UInt, Sendable {
    case fetchRequestType = 1, saveRequestType, batchInsertRequestType = 5, batchUpdateRequestType = 6, batchDeleteRequestType = 7
}

/// The criteria used to retrieve data from or save data to a persistent store.
open class NSPersistentStoreRequest: @unchecked Sendable {
    public var affectedStores: [NSPersistentStore]?
    open var requestType: NSPersistentStoreRequestType { .fetchRequestType }
    public init() {}
}

/// A description of search criteria used to retrieve data from a persistent store.
open class NSFetchRequest<ResultType>: NSPersistentStoreRequest, CustomStringConvertible, @unchecked Sendable {
    public var entityName: String?
    private var _entity: NSEntityDescription?
    public var entity: NSEntityDescription? {
        get { _entity }
        set { _entity = newValue; if let name = newValue?.name { entityName = name } }
    }
    public var predicate: NSPredicate?
    public var sortDescriptors: [NSSortDescriptor]?
    public var fetchLimit = 0
    public var fetchOffset = 0
    public var fetchBatchSize = 0
    public var includesSubentities = true
    public var includesPendingChanges = true
    public var includesPropertyValues = true
    public var returnsObjectsAsFaults = true
    public var shouldRefreshRefetchedObjects = false
    public var returnsDistinctResults = false
    public var resultType: NSFetchRequestResultType = .managedObjectResultType
    public var relationshipKeyPathsForPrefetching: [String]?
    public var propertiesToFetch: [Any]?
    public var propertiesToGroupBy: [Any]?
    public var havingPredicate: NSPredicate?

    public override init() { super.init() }

    public convenience init(entityName: String) {
        self.init()
        self.entityName = entityName
        _entity = _CDModelRegistry.entity(named: entityName)
    }

    open override var requestType: NSPersistentStoreRequestType { .fetchRequestType }

    open var description: String {
        "<NSFetchRequest: entity: \(entityName ?? "?"), predicate: (\(predicate?.predicateFormat ?? "nil")); sortDescriptors: \(sortDescriptors ?? []); limit: \(fetchLimit)>"
    }
}

/// A description of a column a dictionary fetch returns.
open class NSExpressionDescription: NSPropertyDescription, @unchecked Sendable {
    public var expression: NSExpression?
    public var expressionResultType: NSAttributeType = .undefinedAttributeType
    public override init() { super.init() }
}

/// The result of a store request.
open class NSPersistentStoreResult: @unchecked Sendable {
    public init() {}
}

/// The result of a fetch run as a store request.
open class NSAsynchronousFetchResult: NSPersistentStoreResult, @unchecked Sendable {
    public let finalResult: [Any]?
    init(finalResult: [Any]?) { self.finalResult = finalResult; super.init() }
}

/// What a batch delete request returns.
public enum NSBatchDeleteRequestResultType: UInt, Sendable {
    case resultTypeStatusOnly = 0, resultTypeObjectIDs, resultTypeCount
}

/// A request that deletes objects in the persistent store without loading them into memory.
open class NSBatchDeleteRequest: NSPersistentStoreRequest, @unchecked Sendable {
    public let fetchRequest: NSFetchRequest<NSFetchRequestResult>?
    let objectIDs: [NSManagedObjectID]?
    public var resultType: NSBatchDeleteRequestResultType = .resultTypeStatusOnly

    public init(fetchRequest fetch: NSFetchRequest<NSFetchRequestResult>) {
        fetchRequest = fetch
        objectIDs = nil
        super.init()
    }

    public init(objectIDs objects: [NSManagedObjectID]) {
        fetchRequest = nil
        objectIDs = objects
        super.init()
    }

    open override var requestType: NSPersistentStoreRequestType { .batchDeleteRequestType }
}

/// The result of a batch delete: a status, the deleted IDs, or their count.
open class NSBatchDeleteResult: NSPersistentStoreResult, @unchecked Sendable {
    public let result: Any?
    init(result: Any?) { self.result = result; super.init() }
}
