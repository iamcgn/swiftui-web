// Managed objects: an entity's instances, their values by property name (key-value coding, as
// Core Data stores them), relationships kept in both directions, and the change tracking a
// context saves. Apple's `NSManagedObject` is an Objective-C class whose `@NSManaged`
// properties the runtime implements; here the CoreDataModel plugin writes those properties as
// accessors over `value(forKey:)`/`setValue(_:forKey:)`, as Xcode's generated classes read.
//
// Not Core Data: no faults (an object's values are all in memory once fetched), no undo, no
// `@objc` key-value observing. An object publishes `objectWillChange` (SwiftUI's
// `@ObservedObject`) when its context is a main-queue context.

// Apple's CoreData re-exports Foundation: a file importing only it names Date and URL.
@_exported import WebFoundation
import WebCombine

/// A type that a fetch request can return: managed objects, their IDs, counts and dictionaries.
public protocol NSFetchRequestResult {}

extension NSNumber: NSFetchRequestResult {}
extension Dictionary: NSFetchRequestResult {}

// MARK: - NSManagedObjectID

/// A compact, universal identifier for a managed object.
public final class NSManagedObjectID: NSFetchRequestResult, Hashable, CustomStringConvertible, @unchecked Sendable {
    /// The entity of the object the ID names.
    public let entity: NSEntityDescription
    let _number: Int
    /// Whether the ID is temporary (the object is inserted and not saved yet).
    public let isTemporaryID: Bool
    let _storeID: String
    /// The store that holds the object, when it is saved.
    public internal(set) weak var persistentStore: NSPersistentStore?

    init(entity: NSEntityDescription, number: Int, temporary: Bool, storeID: String, store: NSPersistentStore?) {
        self.entity = entity
        _number = number
        isTemporaryID = temporary
        _storeID = storeID
        persistentStore = store
    }

    nonisolated(unsafe) private static var nextTemporary = 0

    static func _temporary(for entity: NSEntityDescription) -> NSManagedObjectID {
        nextTemporary += 1
        return NSManagedObjectID(entity: entity, number: nextTemporary, temporary: true, storeID: "", store: nil)
    }

    var _entityName: String { entity.name ?? "" }
    /// The ID as a string key: `Entity/p3` (saved) or `Entity/t17` (temporary).
    var _key: String { "\(_entityName)/\(isTemporaryID ? "t" : "p")\(_number)" }

    /// A URL that names the object (`x-coredata://store/Entity/p3`).
    public func uriRepresentation() -> URL {
        URL(string: "x-coredata://\(_storeID.isEmpty ? "temporary" : _storeID)/\(_key)")!
    }

    public static func == (lhs: NSManagedObjectID, rhs: NSManagedObjectID) -> Bool {
        lhs === rhs || (lhs._number == rhs._number && lhs.isTemporaryID == rhs.isTemporaryID
            && lhs._entityName == rhs._entityName && lhs._storeID == rhs._storeID)
    }
    public func hash(into hasher: inout Hasher) {
        hasher.combine(_entityName)
        hasher.combine(_number)
        hasher.combine(isTemporaryID)
    }
    public var description: String { "<\(uriRepresentation().absoluteString)>" }
}

// MARK: - NSManagedObject

/// A base class that implements the behavior for a Core Data model object.
open class NSManagedObject: NSFetchRequestResult, _CDKeyValueCoding, ObservableObject, Hashable, CustomStringConvertible, @unchecked Sendable {
    /// The object's entity.
    public let entity: NSEntityDescription
    /// The object's ID: temporary until the object's context saves it.
    public internal(set) var objectID: NSManagedObjectID
    /// The context the object is registered with.
    public internal(set) weak var managedObjectContext: NSManagedObjectContext?
    /// Emits before the object changes (SwiftUI's `@ObservedObject`).
    public let objectWillChange = ObservableObjectPublisher()

    /// The object's values by property name: attributes as values (integers as `Int64`),
    /// to-one relationships as objects, to-many as `NSSet`/`NSOrderedSet` of objects.
    var _values: [String: Any] = [:]
    /// The values when the object was last fetched or saved.
    var _committed: [String: Any] = [:]
    /// The properties changed since then.
    var _changedKeys: Set<String> = []

    public internal(set) var isInserted = false
    public internal(set) var isDeleted = false
    /// Whether the object's changes are saved (its context saves it).
    public var isUpdated: Bool { !isInserted && !isDeleted && !_changedKeys.isEmpty }
    public var hasChanges: Bool { isInserted || isDeleted || !_changedKeys.isEmpty }
    public var hasPersistentChangedValues: Bool {
        _changedKeys.contains { key in !(entity.propertiesByName[key]?.isTransient ?? false) }
    }
    /// Objects here are never faults: their values are in memory.
    public var isFault: Bool { false }
    public var faultingState: Int { 0 }
    /// A deny delete rule refused the deletion: the save fails.
    var _deniedBy: String?

    /// Makes an object of the entity, inserted into the context when one is given.
    public required init(entity: NSEntityDescription, insertInto context: NSManagedObjectContext?) {
        self.entity = entity
        objectID = NSManagedObjectID._temporary(for: entity)
        for case let attribute as NSAttributeDescription in entity.properties {
            if let value = attribute.defaultValue { _values[attribute.name] = _cdNormalize(value, for: attribute) }
        }
        if let context { context.insert(self) }
    }

    /// Makes an object of the class's entity in the context's model, inserted into the context.
    public convenience init(context moc: NSManagedObjectContext) {
        guard let entity = Self._entity(in: moc) else {
            fatalError("NSManagedObject: no entity in the context's model is represented by \(Self.self)")
        }
        self.init(entity: entity, insertInto: moc)
    }

    /// The entity whose class is this one.
    open class func entity() -> NSEntityDescription {
        guard let entity = _CDModelRegistry.entity(for: self) else {
            fatalError("NSManagedObject: no model registered describes \(self)")
        }
        return entity
    }

    /// A fetch request for the class's entity (generated classes declare a typed one).
    open class func fetchRequest() -> NSFetchRequest<NSFetchRequestResult> {
        let request = NSFetchRequest<NSFetchRequestResult>()
        request.entity = _CDModelRegistry.entity(for: self)
        request.entityName = request.entity?.name
        return request
    }

    static func _entity(in context: NSManagedObjectContext) -> NSEntityDescription? {
        if let model = context._model,
           let entity = model.entities.first(where: { ObjectIdentifier($0.managedObjectClass) == ObjectIdentifier(self) }) { return entity }
        return _CDModelRegistry.entity(for: self)
    }

    // MARK: Lifecycle hooks

    open func awakeFromInsert() {}
    open func awakeFromFetch() {}
    open func awake(fromSnapshotEvents flags: Int) {}
    open func willSave() {}
    open func didSave() {}
    open func willTurnIntoFault() {}
    open func didTurnIntoFault() {}
    open func prepareForDeletion() {}
    open func validateForInsert() throws { try _validate() }
    open func validateForUpdate() throws { try _validate() }
    open func validateForDelete() throws {
        if let name = _deniedBy {
            throw NSError(domain: NSCocoaErrorDomain, code: NSValidationRelationshipDeniedDeleteError,
                          userInfo: [NSValidationKeyErrorKey: name, NSLocalizedDescriptionKey: "The relationship \(name) denies the deletion."])
        }
    }

    /// Non-optional properties hold values (Core Data's validation before a save).
    func _validate() throws {
        for property in entity.properties where !property.isOptional && !property.isTransient {
            let value = _values[property.name]
            let missing: Bool
            if let relationship = property as? NSRelationshipDescription {
                if relationship.isToMany {
                    let count = _cdElements(value)?.count ?? 0
                    missing = count < max(relationship.minCount, 1) && relationship.minCount > 0
                } else {
                    missing = _cdUnwrap(value) == nil
                }
            } else {
                missing = _cdUnwrap(value) == nil
            }
            if missing {
                throw NSError(domain: NSCocoaErrorDomain, code: NSValidationMissingMandatoryPropertyError,
                              userInfo: [NSValidationKeyErrorKey: property.name, NSLocalizedDescriptionKey: "\(property.name) is a required value."])
            }
        }
    }

    // MARK: Key-value coding

    /// The value of the property with the name (integers as `Int`, as `NSNumber` bridges them).
    open func value(forKey key: String) -> Any? {
        guard let value = _values[key] else { return nil }
        if let integer = value as? Int64, let attribute = entity.attributesByName[key], attribute.attributeType._isInteger {
            return Int(exactly: integer) ?? integer
        }
        return value
    }

    /// Sets the property with the name; a relationship's inverse follows.
    open func setValue(_ value: Any?, forKey key: String) {
        if let relationship = entity.relationshipsByName[key] {
            _setRelationship(relationship, value)
            return
        }
        let newValue = entity.attributesByName[key].map { _cdNormalize(value, for: $0) } ?? _cdUnwrap(value)
        willChangeValue(forKey: key)
        if let newValue { _values[key] = newValue } else { _values[key] = nil }
        didChangeValue(forKey: key)
    }

    /// The value at a dotted key path (`owner.name`).
    open func value(forKeyPath keyPath: String) -> Any? { _cdValue(of: self, keyPath: keyPath) }
    open func setValue(_ value: Any?, forKeyPath keyPath: String) {
        var components = keyPath.split(separator: ".").map(String.init)
        let last = components.removeLast()
        guard let target = components.isEmpty ? self : _cdValue(of: self, keyPath: components.joined(separator: ".")) as? NSManagedObject else { return }
        target.setValue(value, forKey: last)
    }
    open func setValuesForKeys(_ keyedValues: [String: Any]) {
        for (key, value) in keyedValues { setValue(value is NSNull ? nil : value, forKey: key) }
    }
    open func dictionaryWithValues(forKeys keys: [String]) -> [String: Any] {
        var result: [String: Any] = [:]
        for key in keys { result[key] = value(forKey: key) ?? NSNull() }
        return result
    }

    /// The stored value, with no change notification.
    open func primitiveValue(forKey key: String) -> Any? { _values[key] }
    open func setPrimitiveValue(_ value: Any?, forKey key: String) {
        let newValue = entity.attributesByName[key].map { _cdNormalize(value, for: $0) } ?? _cdUnwrap(value)
        if let newValue { _values[key] = newValue } else { _values[key] = nil }
    }

    open func willAccessValue(forKey key: String?) {}
    open func didAccessValue(forKey key: String?) {}

    /// Called before a property changes: observers hear it.
    open func willChangeValue(forKey key: String) {
        if managedObjectContext?.concurrencyType == .mainQueueConcurrencyType { objectWillChange.send() }
    }

    /// Called after a property changed: the context records the change.
    open func didChangeValue(forKey key: String) {
        guard !_cdApplyingSnapshot else { return }
        _changedKeys.insert(key)
        managedObjectContext?._objectDidChange(self)
    }

    /// The changed properties' new values.
    open func changedValues() -> [String: Any] {
        var result: [String: Any] = [:]
        for key in _changedKeys { result[key] = value(forKey: key) ?? NSNull() }
        return result
    }
    open func changedValuesForCurrentEvent() -> [String: Any] { changedValues() }

    /// The values when last fetched or saved.
    open func committedValues(forKeys keys: [String]?) -> [String: Any] {
        var result: [String: Any] = [:]
        for key in keys ?? entity.properties.map(\.name) { result[key] = _committed[key] ?? NSNull() }
        return result
    }

    /// A mutable set proxy for a to-many relationship (changes go through the relationship).
    open func mutableSetValue(forKey key: String) -> NSMutableSet { NSMutableSet(object: self, key: key) }
    open func mutableOrderedSetValue(forKey key: String) -> NSMutableOrderedSet { NSMutableOrderedSet(object: self, key: key) }

    /// The IDs of the objects a relationship holds.
    open func objectIDs(forRelationshipNamed key: String) -> [NSManagedObjectID] {
        _targets(key).map(\.objectID)
    }

    // MARK: Relationships

    /// The objects a relationship holds.
    func _targets(_ key: String) -> [NSManagedObject] {
        switch _values[key] {
        case let object as NSManagedObject: return [object]
        case let set as Set<AnyHashable>: return set.compactMap { $0.base as? NSManagedObject }
        case let ordered as NSOrderedSet: return ordered.array.compactMap { $0 as? NSManagedObject }
        default: return []
        }
    }

    /// Sets a relationship to the value (an object, a set, an ordered set, an array, or nil); the
    /// objects that left and joined have their inverse relationships follow.
    func _setRelationship(_ relationship: NSRelationshipDescription, _ value: Any?) {
        let key = relationship.name
        let old = _targets(key)
        let incoming = _cdRelationshipObjects(value)
        willChangeValue(forKey: key)
        if relationship.isToMany {
            if relationship.isOrdered {
                var ordered = NSOrderedSet()
                for object in incoming { ordered._append(object) }
                _values[key] = ordered
            } else {
                _values[key] = Set<AnyHashable>(incoming.map { AnyHashable($0) })
            }
        } else if let object = incoming.first {
            _values[key] = object
        } else {
            _values[key] = nil
        }
        didChangeValue(forKey: key)
        for object in incoming where object.managedObjectContext == nil {
            managedObjectContext?.insert(object)
        }
        guard let inverse = relationship.inverseRelationship else { return }
        let oldIDs = Set(old.map(ObjectIdentifier.init)), newIDs = Set(incoming.map(ObjectIdentifier.init))
        for object in old where !newIDs.contains(ObjectIdentifier(object)) { object._inverseRemove(inverse, self) }
        for object in incoming where !oldIDs.contains(ObjectIdentifier(object)) { object._inverseAdd(inverse, self) }
    }

    /// The other side of a relationship gained `object`: this side holds it too. A to-one side
    /// that held another object lets that one go.
    func _inverseAdd(_ relationship: NSRelationshipDescription, _ object: NSManagedObject) {
        let key = relationship.name
        if relationship.isToMany {
            if _targets(key).contains(where: { $0 === object }) { return }
            willChangeValue(forKey: key)
            if relationship.isOrdered {
                var ordered = _values[key] as? NSOrderedSet ?? NSOrderedSet()
                ordered._append(object)
                _values[key] = ordered
            } else {
                var set = _values[key] as? Set<AnyHashable> ?? []
                set.insert(AnyHashable(object))
                _values[key] = set
            }
            didChangeValue(forKey: key)
        } else {
            let previous = _values[key] as? NSManagedObject
            if previous === object { return }
            willChangeValue(forKey: key)
            _values[key] = object
            didChangeValue(forKey: key)
            if let previous, let back = relationship.inverseRelationship { previous._inverseRemove(back, self) }
        }
    }

    /// The other side of a relationship let `object` go: this side lets it go too.
    func _inverseRemove(_ relationship: NSRelationshipDescription, _ object: NSManagedObject) {
        let key = relationship.name
        if relationship.isToMany {
            guard _targets(key).contains(where: { $0 === object }) else { return }
            willChangeValue(forKey: key)
            if relationship.isOrdered {
                var ordered = _values[key] as? NSOrderedSet ?? NSOrderedSet()
                ordered._remove(object)
                _values[key] = ordered
            } else {
                var set = _values[key] as? Set<AnyHashable> ?? []
                set.remove(AnyHashable(object))
                _values[key] = set
            }
            didChangeValue(forKey: key)
        } else {
            guard _values[key] as? NSManagedObject === object else { return }
            willChangeValue(forKey: key)
            _values[key] = nil
            didChangeValue(forKey: key)
        }
    }

    /// Adds objects to a to-many relationship (the generated `addToX` accessors).
    func _addTargets(_ key: String, _ objects: [NSManagedObject]) {
        guard let relationship = entity.relationshipsByName[key] else { return }
        var current = _targets(key)
        for object in objects where !current.contains(where: { $0 === object }) { current.append(object) }
        _setRelationship(relationship, current)
    }

    /// Removes objects from a to-many relationship (the generated `removeFromX` accessors).
    func _removeTargets(_ key: String, _ objects: [NSManagedObject]) {
        guard let relationship = entity.relationshipsByName[key] else { return }
        let removed = Set(objects.map(ObjectIdentifier.init))
        _setRelationship(relationship, _targets(key).filter { !removed.contains(ObjectIdentifier($0)) })
    }

    // MARK: Generated accessors (the CoreDataModel plugin writes these calls)

    /// An integer attribute (`Int16`, `Int32`, `Int64`): 0 when it has no value.
    public func _genInteger<T: FixedWidthInteger>(_ key: String) -> T {
        T(truncatingIfNeeded: _cdInt64(_values[key]) ?? 0)
    }
    /// A floating-point attribute (`Double`, `Float`): 0 when it has no value.
    public func _genDouble(_ key: String) -> Double { _cdDouble(_values[key]) ?? 0 }
    public func _genFloat(_ key: String) -> Float { Float(_cdDouble(_values[key]) ?? 0) }
    /// A Boolean attribute: false when it has no value.
    public func _genBool(_ key: String) -> Bool { (_cdInt64(_values[key]) ?? 0) != 0 }
    /// A number attribute that is not a scalar (`NSNumber?`).
    public func _genNumber(_ key: String) -> NSNumber? {
        switch _values[key] {
        case let v as Int64: return NSNumber(value: v)
        case let v as Double: return NSNumber(value: v)
        case let v as Bool: return NSNumber(value: v)
        case let v as NSNumber: return v
        default: return nil
        }
    }
    /// An attribute of any other type (`String?`, `Date?`, `UUID?`, a transformable class).
    public func _genValue<T>(_ key: String, as type: T.Type = T.self) -> T? { value(forKey: key) as? T }
    /// A to-one relationship.
    public func _genObject<T>(_ key: String, as type: T.Type = T.self) -> T? { _values[key] as? T }
    /// An unordered to-many relationship (`NSSet?`).
    public func _genSet(_ key: String) -> NSSet? { _values[key] as? Set<AnyHashable> }
    /// An ordered to-many relationship (`NSOrderedSet?`).
    public func _genOrdered(_ key: String) -> NSOrderedSet? { _values[key] as? NSOrderedSet }
    /// Sets any property.
    public func _genSetValue(_ value: Any?, _ key: String) { setValue(value, forKey: key) }
    /// `addToX(_:)` and `removeFromX(_:)`: one object, or a set or ordered set of them.
    public func _genAdd(_ value: Any, _ key: String) { _addTargets(key, _cdRelationshipObjects(value)) }
    public func _genRemove(_ value: Any, _ key: String) { _removeTargets(key, _cdRelationshipObjects(value)) }
    /// The ordered accessors: `insertIntoX(_:at:)`, `removeFromX(at:)`, `replaceX(at:with:)`.
    public func _genInsert(_ value: Any, at index: Int, _ key: String) {
        guard let relationship = entity.relationshipsByName[key] else { return }
        var current = _targets(key)
        let incoming = _cdRelationshipObjects(value).filter { object in !current.contains { $0 === object } }
        current.insert(contentsOf: incoming, at: min(max(index, 0), current.count))
        _setRelationship(relationship, current)
    }
    public func _genInsert(_ values: [Any], at indexes: IndexSet, _ key: String) {
        for (value, index) in zip(values, indexes) { _genInsert(value, at: index, key) }
    }
    public func _genRemove(at index: Int, _ key: String) {
        guard let relationship = entity.relationshipsByName[key] else { return }
        var current = _targets(key)
        guard current.indices.contains(index) else { return }
        current.remove(at: index)
        _setRelationship(relationship, current)
    }
    public func _genRemove(at indexes: IndexSet, _ key: String) {
        guard let relationship = entity.relationshipsByName[key] else { return }
        let current = _targets(key)
        _setRelationship(relationship, current.enumerated().filter { !indexes.contains($0.offset) }.map(\.element))
    }
    public func _genReplace(at index: Int, with value: Any, _ key: String) {
        guard let relationship = entity.relationshipsByName[key] else { return }
        var current = _targets(key)
        guard current.indices.contains(index), let object = _cdRelationshipObjects(value).first else { return }
        current[index] = object
        _setRelationship(relationship, current)
    }

    // MARK: Identity

    public static func == (lhs: NSManagedObject, rhs: NSManagedObject) -> Bool { lhs === rhs }
    public func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }

    open var description: String {
        let values = entity.attributesByName.keys.sorted().map { "\($0) = \(_values[$0].map { "\($0)" } ?? "nil")" }
        return "<\(type(of: self)): \(objectID.description); data: {\(values.joined(separator: "; "))}>"
    }

    // MARK: Swift key paths

    /// The property name a Swift key path into a managed object class names (generated classes
    /// register their key paths; `\Item.name` is `"name"`).
    public static func _key(for keyPath: AnyKeyPath, in rootType: Any.Type) -> String? {
        if let key = _CDModelRegistry.key(for: keyPath) { return key }
        // `\Item.name` describes itself as `\Item.name`: the last component is the key.
        let text = "\(keyPath)"
        guard text.hasPrefix("\\") else { return nil }
        let components = text.dropFirst().split(separator: ".").dropFirst()
        let key = components.map { $0.hasSuffix("?") || $0.hasSuffix("!") ? String($0.dropLast()) : String($0) }.joined(separator: ".")
        return key.isEmpty ? nil : key
    }
}

/// Whether a context is applying stored values (no change is recorded).
nonisolated(unsafe) var _cdApplyingSnapshot = false

extension NSAttributeType {
    var _isInteger: Bool {
        self == .integer16AttributeType || self == .integer32AttributeType || self == .integer64AttributeType
    }
}

/// The objects a relationship value names: one object, a set, an ordered set or an array.
func _cdRelationshipObjects(_ value: Any?) -> [NSManagedObject] {
    guard let value = _cdUnwrap(value) else { return [] }
    if let object = value as? NSManagedObject { return [object] }
    return (_cdElements(value) ?? []).compactMap { _cdUnwrap($0) as? NSManagedObject }
}

/// A value as an attribute of the type stores it: integers as `Int64`, floating point as
/// `Double`, Booleans as `Bool`; other values as they are.
func _cdNormalize(_ value: Any?, for attribute: NSAttributeDescription) -> Any? {
    guard let value = _cdUnwrap(value), !(value is NSNull) else { return nil }
    switch attribute.attributeType {
    case .integer16AttributeType, .integer32AttributeType, .integer64AttributeType:
        if let string = value as? String { return Int64(string) }
        return _cdInt64(value) ?? _cdDouble(value).map { Int64($0) }
    case .doubleAttributeType, .floatAttributeType:
        if let string = value as? String { return Double(string) }
        return _cdDouble(value)
    case .booleanAttributeType:
        if let bool = value as? Bool { return bool }
        if let string = value as? String { return ["yes", "true", "1"].contains(string.lowercased()) }
        return _cdInt64(value).map { $0 != 0 }
    case .decimalAttributeType:
        if let decimal = value as? Decimal { return decimal }
        if let string = value as? String { return Double(string).map { Decimal($0) } }
        if let integer = _cdInt64(value) { return Decimal(integer) }
        return _cdDouble(value).map { Decimal($0) }
    case .stringAttributeType:
        return _cdString(value) ?? "\(value)"
    case .dateAttributeType:
        if let date = value as? Date { return date }
        return _cdDouble(value).map { Date(timeIntervalSinceReferenceDate: $0) }
    case .UUIDAttributeType:
        if let string = value as? String { return UUID(uuidString: string) }
        return value as? UUID
    case .URIAttributeType:
        if let string = value as? String { return URL(string: string) }
        return value as? URL
    default:
        return value
    }
}

// MARK: - Mutable collection proxies

/// A to-many relationship as a mutable set (`mutableSetValue(forKey:)`): changes go through the
/// relationship, so its inverse follows.
public final class NSMutableSet: Sequence, CustomStringConvertible {
    let object: NSManagedObject
    let key: String
    init(object: NSManagedObject, key: String) { self.object = object; self.key = key }

    var objects: [NSManagedObject] { object._targets(key) }
    public var count: Int { objects.count }
    public var allObjects: [Any] { objects }
    public func anyObject() -> Any? { objects.first }
    public func contains(_ anObject: Any) -> Bool {
        let target = _cdUnwrap(anObject) as? NSManagedObject
        return objects.contains { $0 === target }
    }
    public func add(_ anObject: Any) { object._addTargets(key, _cdRelationshipObjects(anObject)) }
    public func addObjects(from array: [Any]) { object._addTargets(key, array.flatMap { _cdRelationshipObjects($0) }) }
    public func remove(_ anObject: Any) { object._removeTargets(key, _cdRelationshipObjects(anObject)) }
    public func removeAllObjects() { object._removeTargets(key, objects) }
    public func union(_ otherSet: Set<AnyHashable>) { addObjects(from: otherSet.allObjects) }
    public func minus(_ otherSet: Set<AnyHashable>) { object._removeTargets(key, otherSet.allObjects.flatMap { _cdRelationshipObjects($0) }) }
    public func makeIterator() -> IndexingIterator<[Any]> { (objects as [Any]).makeIterator() }
    public var description: String { "\(objects)" }
}

/// An ordered to-many relationship as a mutable ordered set (`mutableOrderedSetValue(forKey:)`).
public final class NSMutableOrderedSet: Sequence, CustomStringConvertible {
    let object: NSManagedObject
    let key: String
    init(object: NSManagedObject, key: String) { self.object = object; self.key = key }

    var objects: [NSManagedObject] { object._targets(key) }
    public var count: Int { objects.count }
    public var array: [Any] { objects }
    public var firstObject: Any? { objects.first }
    public var lastObject: Any? { objects.last }
    public func object(at idx: Int) -> Any { objects[idx] }
    public func index(of anObject: Any) -> Int {
        let target = _cdUnwrap(anObject) as? NSManagedObject
        return objects.firstIndex { $0 === target } ?? Int.max
    }
    public func contains(_ anObject: Any) -> Bool { index(of: anObject) != Int.max }
    public func add(_ anObject: Any) { object._addTargets(key, _cdRelationshipObjects(anObject)) }
    public func addObjects(from array: [Any]) { object._addTargets(key, array.flatMap { _cdRelationshipObjects($0) }) }
    public func insert(_ anObject: Any, at idx: Int) { object._genInsert(anObject, at: idx, key) }
    public func remove(_ anObject: Any) { object._removeTargets(key, _cdRelationshipObjects(anObject)) }
    public func removeObject(at idx: Int) { object._genRemove(at: idx, key) }
    public func replaceObject(at idx: Int, with anObject: Any) { object._genReplace(at: idx, with: anObject, key) }
    public func removeAllObjects() { object._removeTargets(key, objects) }
    public func moveObjects(at indexes: IndexSet, to idx: Int) {
        guard let relationship = object.entity.relationshipsByName[key] else { return }
        var current = objects
        let moving = indexes.filter { current.indices.contains($0) }.map { current[$0] }
        let before = indexes.filter { $0 < idx }.count
        current = current.enumerated().filter { !indexes.contains($0.offset) }.map(\.element)
        current.insert(contentsOf: moving, at: min(max(idx - before, 0), current.count))
        object._setRelationship(relationship, current)
    }
    public func makeIterator() -> IndexingIterator<[Any]> { (objects as [Any]).makeIterator() }
    public var description: String { "\(objects)" }
}

// MARK: - Errors

// Core Data's error codes and keys (Foundation does not declare them).
public let NSValidationKeyErrorKey = "NSValidationErrorKey"
public let NSValidationObjectErrorKey = "NSValidationErrorObject"
public let NSValidationMissingMandatoryPropertyError = 1570
public let NSValidationRelationshipDeniedDeleteError = 1600
public let NSManagedObjectValidationError = 1550
public let NSManagedObjectMergeError = 133020
public let NSPersistentStoreOpenError = 134080
public let NSPersistentStoreSaveError = 134030
public let NSPersistentStoreIncompatibleVersionHashError = 134100
public let NSMigrationMissingSourceModelError = 134130
public let NSDetailedErrorsKey = "NSDetailedErrors"
public let NSAffectedObjectsErrorKey = "NSAffectedObjectsErrorKey"
