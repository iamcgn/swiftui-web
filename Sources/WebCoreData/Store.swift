// Stores, the coordinator and the container. A store keeps rows (an object's attributes and its
// relationships as keys) and writes them, as JSON, through the host's storage: in the browser,
// localStorage (the same hook SwiftData's stores use); without a host, the process's memory.
// Two containers that open the same store name share its rows, as two Core Data stacks over
// the same file do. An in-memory store (`NSInMemoryStoreType`, or the `/dev/null` URL of
// Xcode's preview template) is its coordinator's alone.
//
// Not Core Data: no SQL, no migrations (a store's rows are read whatever model wrote them:
// unknown properties are ignored, missing ones are nil), no persistent history, and CloudKit
// containers keep their data on the device.

import SwiftData

public let NSSQLiteStoreType = "SQLite"
public let NSInMemoryStoreType = "InMemory"
public let NSBinaryStoreType = "Binary"
public let NSXMLStoreType = "XML"

public let NSPersistentHistoryTrackingKey = "NSPersistentHistoryTrackingKey"
public let NSPersistentStoreRemoteChangeNotificationPostOptionKey = "NSPersistentStoreRemoteChangeNotificationOptionKey"
public let NSMigratePersistentStoresAutomaticallyOption = "NSMigratePersistentStoresAutomaticallyOption"
public let NSInferMappingModelAutomaticallyOption = "NSInferMappingModelAutomaticallyOption"
public let NSReadOnlyPersistentStoreOption = "NSReadOnlyPersistentStoreOption"
public let NSPersistentStoreFileProtectionKey = "NSPersistentStoreFileProtectionKey"
public let NSSQLitePragmasOption = "NSSQLitePragmasOption"
public let NSPersistentStoreUbiquitousContainerIdentifierKey = "NSPersistentStoreUbiquitousContainerIdentifierKey"
public let NSStoreUUIDKey = "NSStoreUUID"
public let NSStoreTypeKey = "NSStoreType"

// MARK: - Store data

/// One store's rows, shared by every store object opened on the same name.
final class _CDStoreData {
    let name: String
    /// Whether the rows are written through the host's storage.
    let persistent: Bool
    var rows: [String: _CDRow] = [:]
    var counters: [String: Int] = [:]
    var uuid: String
    var generation = 0
    private var coordinators: [_CDWeakCoordinator] = []

    init(name: String, persistent: Bool) {
        self.name = name
        self.persistent = persistent
        uuid = UUID().uuidString
    }

    nonisolated(unsafe) private static var open: [String: _CDStoreData] = [:]

    /// The store with the name: the one already open in this process, or the host's copy, or
    /// an empty one.
    static func named(_ name: String) throws -> _CDStoreData {
        if let data = open[name] { return data }
        let data = _CDStoreData(name: name, persistent: true)
        if let host = _ModelStore.Host.store {
            let text: String?
            do { text = try host.load(_hostKey(name)) } catch {
                throw NSError(domain: NSCocoaErrorDomain, code: NSPersistentStoreOpenError,
                              userInfo: [NSLocalizedDescriptionKey: "The store \(name) could not be read: \(error)"])
            }
            if let text { try data.load(from: text) }
        }
        open[name] = data
        return data
    }

    /// Removes the store's rows, in memory and in the host's storage.
    static func destroy(_ name: String) throws {
        if let data = open[name] {
            data.rows = [:]
            data.counters = [:]
            data.generation += 1
            data.didChange(onMain: false)
        }
        try _ModelStore.Host.store?.save(_hostKey(name), nil)
    }

    static func _hostKey(_ name: String) -> String { "coredata." + name }

    func attach(_ coordinator: NSPersistentStoreCoordinator) {
        coordinators.removeAll { $0.coordinator == nil }
        if !coordinators.contains(where: { $0.coordinator === coordinator }) { coordinators.append(_CDWeakCoordinator(coordinator)) }
    }

    func didChange(onMain: Bool) {
        for entry in coordinators { entry.coordinator?._storesDidChange(onMain: onMain) }
    }

    /// The next permanent number for an entity's objects.
    func nextNumber(for entity: String) -> Int {
        let number = (counters[entity] ?? 0) + 1
        counters[entity] = number
        return number
    }

    /// The rows as JSON (what the host keeps).
    func encoded() throws -> String {
        var file = _CDStoreFile(counters: counters, uuid: uuid, rows: [:])
        for (key, row) in rows {
            var values: [String: _CDStoredValue] = [:]
            for (property, value) in row { if let stored = _CDStoredValue(value) { values[property] = stored } }
            file.rows[key] = values
        }
        return String(decoding: try JSONEncoder().encode(file), as: UTF8.self)
    }

    /// Takes the rows the JSON holds.
    func load(from text: String) throws {
        guard let file = try? JSONDecoder().decode(_CDStoreFile.self, from: Data(text.utf8)) else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSPersistentStoreOpenError,
                          userInfo: [NSLocalizedDescriptionKey: "The store \(name) holds data this app cannot read."])
        }
        counters = file.counters
        uuid = file.uuid ?? uuid
        rows = [:]
        for (key, values) in file.rows {
            var row: _CDRow = [:]
            for (property, value) in values { row[property] = value.value }
            rows[key] = row
        }
        generation += 1
    }

    /// Writes the rows through the host (a persistent store with a host).
    func flush() throws {
        guard persistent, let host = _ModelStore.Host.store else { return }
        do {
            try host.save(_CDStoreData._hostKey(name), try encoded())
        } catch {
            throw NSError(domain: NSCocoaErrorDomain, code: NSPersistentStoreSaveError,
                          userInfo: [NSLocalizedDescriptionKey: "The store \(name) could not be written: \(error)"])
        }
    }
}

final class _CDWeakCoordinator {
    weak var coordinator: NSPersistentStoreCoordinator?
    init(_ coordinator: NSPersistentStoreCoordinator) { self.coordinator = coordinator }
}

final class _CDWeakContext {
    weak var context: NSManagedObjectContext?
    init(_ context: NSManagedObjectContext) { self.context = context }
}

/// A store as JSON: its counters and its rows by key.
struct _CDStoreFile: Codable {
    var format = 1
    var counters: [String: Int]
    var uuid: String?
    var rows: [String: [String: _CDStoredValue]]
}

/// A stored value as JSON.
enum _CDStoredValue: Codable, Equatable {
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case date(Double)
    case data(String)
    case uuid(String)
    case url(String)
    case decimal(String)
    case one(String)
    case many([String])
    case ordered([String])

    init?(_ value: Any) {
        switch value {
        case let ref as _CDRef:
            switch ref {
            case .one(let key): self = .one(key)
            case .many(let keys, let ordered): self = ordered ? .ordered(keys) : .many(keys)
            }
        case let v as Bool: self = .bool(v)
        case let v as Int64: self = .int(v)
        case let v as Double: self = .double(v)
        case let v as String: self = .string(v)
        case let v as Date: self = .date(v.timeIntervalSinceReferenceDate)
        case let v as Data: self = .data(v.base64EncodedString())
        case let v as UUID: self = .uuid(v.uuidString)
        case let v as URL: self = .url(v.absoluteString)
        case let v as Decimal: self = .decimal("\(v)")
        default: return nil   // a transformable value: kept in memory, not written
        }
    }

    var value: Any {
        switch self {
        case .bool(let v): return v
        case .int(let v): return v
        case .double(let v): return v
        case .string(let v): return v
        case .date(let v): return Date(timeIntervalSinceReferenceDate: v)
        case .data(let v): return Data(base64Encoded: v) ?? Data()
        case .uuid(let v): return UUID(uuidString: v) ?? UUID()
        case .url(let v): return URL(string: v) ?? URL(fileURLWithPath: v)
        case .decimal(let v): return Decimal(Double(v) ?? 0)
        case .one(let key): return _CDRef.one(key)
        case .many(let keys): return _CDRef.many(keys, ordered: false)
        case .ordered(let keys): return _CDRef.many(keys, ordered: true)
        }
    }
}

// MARK: - NSPersistentStore

/// The abstract base class for all Core Data persistent stores.
open class NSPersistentStore: @unchecked Sendable {
    /// The kinds of stores, by name (`.sqlite`, `.inMemory`).
    public struct StoreType: RawRepresentable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let sqlite = StoreType(rawValue: NSSQLiteStoreType)
        public static let inMemory = StoreType(rawValue: NSInMemoryStoreType)
        public static let binary = StoreType(rawValue: NSBinaryStoreType)
    }

    public let type: String
    public let configurationName: String
    public var url: URL?
    public var options: [AnyHashable: Any]?
    public var isReadOnly = false
    public internal(set) weak var persistentStoreCoordinator: NSPersistentStoreCoordinator?
    let _data: _CDStoreData

    init(type: String, configurationName: String?, url: URL?, options: [AnyHashable: Any]?, data: _CDStoreData) {
        self.type = type
        self.configurationName = configurationName ?? "PF_DEFAULT_CONFIGURATION_NAME"
        self.url = url
        self.options = options
        _data = data
        isReadOnly = (options?[NSReadOnlyPersistentStoreOption] as? Bool) ?? false
    }

    /// The store's unique identifier.
    public var identifier: String! {
        get { _data.uuid }
        set { if let newValue { _data.uuid = newValue } }
    }

    public var metadata: [String: Any]! {
        get { [NSStoreUUIDKey: _data.uuid, NSStoreTypeKey: type] }
        set {}
    }

    public func loadMetadata() throws {}
    open func didAdd(to coordinator: NSPersistentStoreCoordinator) {}
    open func willRemove(from coordinator: NSPersistentStoreCoordinator?) {}
}

// MARK: - NSPersistentStoreDescription

/// A description object used to create and load a persistent store.
open class NSPersistentStoreDescription: CustomStringConvertible, @unchecked Sendable {
    public var type: String = NSSQLiteStoreType
    public var configuration: String?
    public var url: URL?
    public private(set) var options: [String: Any] = [:]
    public var isReadOnly = false
    public var timeout: TimeInterval = 240
    public private(set) var sqlitePragmas: [String: Any] = [:]
    public var shouldAddStoreAsynchronously = false
    public var shouldMigrateStoreAutomatically = true
    public var shouldInferMappingModelAutomatically = true
    /// Accepted: a CloudKit container keeps its data on the device here.
    public var cloudKitContainerOptions: NSPersistentCloudKitContainerOptions?

    public init() {}
    public convenience init(url: URL) {
        self.init()
        self.url = url
    }

    public func setOption(_ option: Any?, forKey key: String) { options[key] = option }
    public func setValue(_ value: Any?, forPragmaNamed name: String) { sqlitePragmas[name] = value }

    open var description: String { "<NSPersistentStoreDescription: type \(type), url \(url?.absoluteString ?? "nil")>" }

    /// The store name rows are kept under: the URL's file name without its extension.
    var _storeName: String? {
        guard type != NSInMemoryStoreType, let url, url.path != "/dev/null" else { return nil }
        let file = url.deletingPathExtension().lastPathComponent
        return file.isEmpty ? nil : file
    }
}

/// Options for a CloudKit-backed store (recorded).
open class NSPersistentCloudKitContainerOptions: @unchecked Sendable {
    public let containerIdentifier: String
    public var databaseScope: Int = 2
    public init(containerIdentifier: String) { self.containerIdentifier = containerIdentifier }
}

// MARK: - NSPersistentStoreCoordinator

/// An object that enables an app's contexts and the persistent stores to work together.
open class NSPersistentStoreCoordinator: @unchecked Sendable {
    public let managedObjectModel: NSManagedObjectModel
    public private(set) var persistentStores: [NSPersistentStore] = []
    public var name: String?
    /// Temporary keys of objects saved through this coordinator, and their permanent keys.
    var _permanentKeys: [String: String] = [:]
    private var contexts: [_CDWeakContext] = []
    private var storeChanges = 0
    private var ids: [String: NSManagedObjectID] = [:]

    public init(managedObjectModel model: NSManagedObjectModel) {
        managedObjectModel = model
    }

    func _attach(_ context: NSManagedObjectContext) {
        contexts.removeAll { $0.context == nil }
        if !contexts.contains(where: { $0.context === context }) { contexts.append(_CDWeakContext(context)) }
    }

    /// Changes whenever a store's rows change.
    var _generation: Int { storeChanges + persistentStores.reduce(0) { $0 + $1._data.generation } }

    func _storesDidChange(onMain: Bool) {
        contexts.removeAll { $0.context == nil }
        for entry in contexts { entry.context?._sourceDidChange(onMain: onMain) }
    }

    /// Adds a store of the type at the URL.
    @discardableResult
    open func addPersistentStore(ofType storeType: String, configurationName configuration: String?, at storeURL: URL?, options: [AnyHashable: Any]? = nil) throws -> NSPersistentStore {
        let description = NSPersistentStoreDescription()
        description.type = storeType
        description.url = storeURL
        description.configuration = configuration
        return try _add(description, options: options)
    }

    /// Adds a store of the type at the URL.
    @discardableResult
    open func addPersistentStore(type: NSPersistentStore.StoreType, configuration: String? = nil, at storeURL: URL, options: [AnyHashable: Any]? = nil) throws -> NSPersistentStore {
        try addPersistentStore(ofType: type.rawValue, configurationName: configuration, at: storeURL, options: options)
    }

    /// Adds the store the description describes, and tells the handler.
    open func addPersistentStore(with storeDescription: NSPersistentStoreDescription, completionHandler block: @escaping (NSPersistentStoreDescription, Error?) -> Void) {
        do {
            _ = try _add(storeDescription, options: storeDescription.options)
            block(storeDescription, nil)
        } catch {
            block(storeDescription, error)
        }
    }

    private func _add(_ description: NSPersistentStoreDescription, options: [AnyHashable: Any]?) throws -> NSPersistentStore {
        let data: _CDStoreData
        if let name = description._storeName {
            if let existing = persistentStores.first(where: { $0._data.name == name && $0._data.persistent }) { return existing }
            data = try _CDStoreData.named(name)
        } else {
            data = _CDStoreData(name: "memory-\(UUID().uuidString)", persistent: false)
        }
        let store = NSPersistentStore(type: description.type, configurationName: description.configuration, url: description.url, options: options, data: data)
        store.isReadOnly = store.isReadOnly || description.isReadOnly
        store.persistentStoreCoordinator = self
        persistentStores.append(store)
        data.attach(self)
        storeChanges += 1
        store.didAdd(to: self)
        _storesDidChange(onMain: false)
        return store
    }

    /// Removes the store from the coordinator.
    open func remove(_ store: NSPersistentStore) throws {
        store.willRemove(from: self)
        persistentStores.removeAll { $0 === store }
        storeChanges += 1
        _storesDidChange(onMain: false)
    }

    open func persistentStore(for URL: URL) -> NSPersistentStore? {
        persistentStores.first { $0.url == URL }
    }

    open func url(for store: NSPersistentStore) -> URL { store.url ?? URL(fileURLWithPath: "/dev/null") }

    /// Deletes the store's rows (its file, on Core Data).
    open func destroyPersistentStore(at url: URL, ofType storeType: String, options: [AnyHashable: Any]? = nil) throws {
        let description = NSPersistentStoreDescription(url: url)
        description.type = storeType
        guard let name = description._storeName else { return }
        try _CDStoreData.destroy(name)
    }

    open func destroyPersistentStore(at url: URL, type storeType: NSPersistentStore.StoreType, options: [AnyHashable: Any]? = nil) throws {
        try destroyPersistentStore(at: url, ofType: storeType.rawValue, options: options)
    }

    /// Moves a store to another URL (here: its rows are copied under the new name).
    open func migratePersistentStore(_ store: NSPersistentStore, to URL: URL, options: [AnyHashable: Any]? = nil, withType storeType: String) throws -> NSPersistentStore {
        let description = NSPersistentStoreDescription(url: URL)
        description.type = storeType
        let new = try _add(description, options: options)
        new._data.rows = store._data.rows
        new._data.counters = store._data.counters
        new._data.generation += 1
        try new._data.flush()
        try remove(store)
        return new
    }

    open func metadata(for store: NSPersistentStore) -> [String: Any] { store.metadata }
    open func setMetadata(_ metadata: [String: Any]?, for store: NSPersistentStore) {}

    /// The ID a `uriRepresentation()` names.
    open func managedObjectID(forURIRepresentation url: URL) -> NSManagedObjectID? {
        let parts = url.absoluteString.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }
        return _objectID(forKey: parts[parts.count - 2] + "/" + parts[parts.count - 1])
    }

    /// The ID for a row key (`Entity/p3`), made once per key.
    func _objectID(forKey key: String) -> NSManagedObjectID? {
        if let id = ids[key] { return id }
        guard let slash = key.lastIndex(of: "/") else { return nil }
        let entityName = String(key[..<slash])
        let tail = key[key.index(after: slash)...]
        guard let kind = tail.first, let number = Int(tail.dropFirst()),
              let entity = managedObjectModel.entitiesByName[entityName] ?? _CDModelRegistry.entity(named: entityName) else { return nil }
        let store = persistentStores.first { $0._data.rows[key] != nil } ?? persistentStores.first
        let id = NSManagedObjectID(entity: entity, number: number, temporary: kind == "t", storeID: store?._data.uuid ?? "", store: store)
        if kind == "p" { ids[key] = id }
        return id
    }

    /// Every store's rows.
    func _rows() -> [String: _CDRow] {
        guard persistentStores.count > 1 else { return persistentStores.first?._data.rows ?? [:] }
        var rows: [String: _CDRow] = [:]
        for store in persistentStores { rows.merge(store._data.rows) { first, _ in first } }
        return rows
    }

    /// The store an object is saved to: the one of its entity's configuration, or the first.
    private func store(for entity: NSEntityDescription) -> NSPersistentStore? {
        persistentStores.first { store in
            store.configurationName != "PF_DEFAULT_CONFIGURATION_NAME"
                && managedObjectModel.entities(forConfigurationName: store.configurationName)?.contains(where: { $0 === entity }) == true
        } ?? persistentStores.first { !$0.isReadOnly } ?? persistentStores.first
    }

    /// A root context's save: inserted objects get permanent IDs, and the rows are written.
    func _save(inserted: [NSManagedObject], updated: [NSManagedObject], deleted: [NSManagedObject], by context: NSManagedObjectContext) throws {
        var touched: [ObjectIdentifier: NSPersistentStore] = [:]
        for object in inserted {
            guard let store = store(for: object.entity) else { continue }
            if store.isReadOnly {
                throw NSError(domain: NSCocoaErrorDomain, code: NSPersistentStoreSaveError, userInfo: [NSLocalizedDescriptionKey: "The store is read-only."])
            }
            let oldKey = object.objectID._key
            let entityName = object.entity.name ?? ""
            let id = NSManagedObjectID(entity: object.entity, number: store._data.nextNumber(for: entityName), temporary: false, storeID: store._data.uuid, store: store)
            object.objectID = id
            ids[id._key] = id
            _permanentKeys[oldKey] = id._key
            context._rekey(object, from: oldKey)
        }
        for object in inserted + updated {
            guard let store = object.objectID.persistentStore ?? self.store(for: object.entity) else { continue }
            store._data.rows[object.objectID._key] = _cdRow(of: object)
            touched[ObjectIdentifier(store)] = store
        }
        for object in deleted {
            for store in persistentStores where store._data.rows.removeValue(forKey: object.objectID._key) != nil {
                touched[ObjectIdentifier(store)] = store
            }
        }
        for store in touched.values {
            store._data.generation += 1
            try store._data.flush()
        }
        for store in touched.values { store._data.didChange(onMain: context.concurrencyType == .mainQueueConcurrencyType) }
    }

    /// A batch delete: the rows go, and every context's next fetch leaves them out.
    func _deleteRows(_ keys: [String], by context: NSManagedObjectContext) throws {
        var touched: [ObjectIdentifier: NSPersistentStore] = [:]
        for key in keys {
            for store in persistentStores where store._data.rows.removeValue(forKey: key) != nil { touched[ObjectIdentifier(store)] = store }
        }
        for store in touched.values {
            store._data.generation += 1
            try store._data.flush()
        }
        for store in touched.values { store._data.didChange(onMain: context.concurrencyType == .mainQueueConcurrencyType) }
    }
}

// MARK: - NSPersistentContainer

/// A container that encapsulates the Core Data stack in your app.
open class NSPersistentContainer: @unchecked Sendable {
    public let name: String
    public let managedObjectModel: NSManagedObjectModel
    public let persistentStoreCoordinator: NSPersistentStoreCoordinator
    public var persistentStoreDescriptions: [NSPersistentStoreDescription]
    /// The main-queue context the app's views use.
    public let viewContext: NSManagedObjectContext

    /// A container for the data model with the name (the CoreDataModel plugin's model of
    /// `<name>.xcdatamodeld`, in the module that makes the container).
    public convenience init(name: String, _ fileID: String = #fileID) {
        let module = _cdModule(fileID)
        _CDModelRegistry.registerGenerated(module: module)
        let model: NSManagedObjectModel
        if let found = _CDModelRegistry.model(named: name, module: module) {
            model = found
        } else if let only = _CDModelRegistry.all.first, _CDModelRegistry.all.count == 1 {
            model = only
        } else {
            print("CoreData: no data model named \(name) was generated (an .xcdatamodeld and the CoreDataModel plugin make one)")
            let empty = NSManagedObjectModel()
            empty._pendingName = name
            empty._pendingModule = module
            model = empty
        }
        self.init(name: name, managedObjectModel: model)
    }

    public init(name: String, managedObjectModel model: NSManagedObjectModel) {
        self.name = name
        managedObjectModel = model
        persistentStoreCoordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        persistentStoreDescriptions = [NSPersistentStoreDescription(url: NSPersistentContainer.defaultDirectoryURL().appendingPathComponent(name + ".sqlite"))]
        viewContext = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        viewContext.persistentStoreCoordinator = persistentStoreCoordinator
    }

    /// The directory stores go in by default.
    open class func defaultDirectoryURL() -> URL {
        URL(fileURLWithPath: "/Library/Application Support/", isDirectory: true)
    }

    /// Loads the stores the descriptions describe, telling the handler about each.
    open func loadPersistentStores(completionHandler block: @escaping (NSPersistentStoreDescription, Error?) -> Void) {
        for description in persistentStoreDescriptions {
            persistentStoreCoordinator.addPersistentStore(with: description, completionHandler: block)
        }
    }

    /// A new private-queue context over the container's stores.
    open func newBackgroundContext() -> NSManagedObjectContext {
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = persistentStoreCoordinator
        return context
    }

    /// Runs the block with a new background context (at once, here).
    open func performBackgroundTask(_ block: @escaping (NSManagedObjectContext) -> Void) {
        block(newBackgroundContext())
    }

    /// Runs the block with a new background context and returns its value.
    nonisolated(nonsending) public func performBackgroundTask<T>(_ block: @escaping (NSManagedObjectContext) throws -> T) async rethrows -> T {
        try block(newBackgroundContext())
    }
}

/// A container whose stores mirror to CloudKit on Apple's platforms; here its data stays on the
/// device.
open class NSPersistentCloudKitContainer: NSPersistentContainer {
    /// Accepted: there is no CloudKit schema to initialize.
    open func initializeCloudKitSchema(options: Int = 0) throws {}
    open func canUpdateRecord(forManagedObjectWith objectID: NSManagedObjectID) -> Bool { true }
    open func canDeleteRecord(forManagedObjectWith objectID: NSManagedObjectID) -> Bool { true }
    open func canModifyManagedObjects(in store: NSPersistentStore) -> Bool { true }
}
