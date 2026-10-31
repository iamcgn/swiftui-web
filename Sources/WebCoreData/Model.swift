// The managed object model: entities with their attributes and relationships. On Apple's
// platforms Xcode compiles an `.xcdatamodeld` into a `.momd` the app loads by name; here the
// CoreDataModel build plugin turns the model into Swift (the entity classes Xcode would generate,
// and a description of the model) and `NSPersistentContainer(name:)` finds that description by
// the model's name, in the module that names it.

/// Types of attributes.
public enum NSAttributeType: UInt, Sendable {
    case undefinedAttributeType = 0
    case integer16AttributeType = 100
    case integer32AttributeType = 200
    case integer64AttributeType = 300
    case decimalAttributeType = 400
    case doubleAttributeType = 500
    case floatAttributeType = 600
    case stringAttributeType = 700
    case booleanAttributeType = 800
    case dateAttributeType = 900
    case binaryDataAttributeType = 1000
    case UUIDAttributeType = 1100
    case URIAttributeType = 1200
    case transformableAttributeType = 1800
    case objectIDAttributeType = 2000
    case compositeAttributeType = 2100
}

/// What a relationship does to its destinations when its source is deleted.
public enum NSDeleteRule: UInt, Sendable {
    case noActionDeleteRule = 0, nullifyDeleteRule, cascadeDeleteRule, denyDeleteRule
}

// MARK: - Properties

/// A description of a property of an entity.
open class NSPropertyDescription: Hashable, CustomStringConvertible, @unchecked Sendable {
    public var name: String
    public var isOptional = true
    public var isTransient = false
    public var isIndexed = false
    public var isIndexedBySpotlight = false
    public var renamingIdentifier: String?
    public var userInfo: [AnyHashable: Any]?
    public var versionHashModifier: String?
    /// The entity the property belongs to.
    public internal(set) weak var entity: NSEntityDescription!

    public init() { name = "" }
    init(name: String) { self.name = name }

    public static func == (lhs: NSPropertyDescription, rhs: NSPropertyDescription) -> Bool { lhs === rhs }
    public func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
    open var description: String { "\(type(of: self))(\(name))" }
}

/// A description of an attribute of an entity.
open class NSAttributeDescription: NSPropertyDescription, @unchecked Sendable {
    public var attributeType: NSAttributeType = .undefinedAttributeType
    public var attributeValueClassName: String?
    public var defaultValue: Any?
    public var valueTransformerName: String?
    public var allowsExternalBinaryDataStorage = false
    public var preservesValueInHistoryOnDeletion = false
    public var allowsCloudEncryption = false

    public override init() { super.init() }

    /// A generated model's attribute (the CoreDataModel plugin).
    public static func _generated(_ name: String, _ type: NSAttributeType, optional: Bool, transient: Bool = false, defaultValue: Any? = nil) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = optional
        attribute.isTransient = transient
        attribute.defaultValue = defaultValue
        return attribute
    }
}

/// A description of a relationship between two entities.
open class NSRelationshipDescription: NSPropertyDescription, @unchecked Sendable {
    public var destinationEntity: NSEntityDescription?
    public var inverseRelationship: NSRelationshipDescription?
    public var maxCount = 0
    public var minCount = 0
    public var deleteRule: NSDeleteRule = .nullifyDeleteRule
    public var isOrdered = false
    /// Whether the relationship can hold more than one destination.
    public var isToMany: Bool { maxCount != 1 }

    var _destinationName: String?
    var _inverseName: String?

    public override init() { super.init() }

    /// A generated model's relationship (the CoreDataModel plugin).
    public static func _generated(_ name: String, destination: String, inverse: String?, toMany: Bool, ordered: Bool = false,
                                  optional: Bool, deleteRule: NSDeleteRule, minCount: Int = 0, maxCount: Int = 0) -> NSRelationshipDescription {
        let relationship = NSRelationshipDescription()
        relationship.name = name
        relationship._destinationName = destination
        relationship._inverseName = inverse
        relationship.maxCount = toMany ? maxCount : 1
        relationship.minCount = minCount
        relationship.isOrdered = ordered
        relationship.isOptional = optional
        relationship.deleteRule = deleteRule
        return relationship
    }
}

// MARK: - Entities

/// A description of an entity in Core Data.
open class NSEntityDescription: Hashable, CustomStringConvertible, @unchecked Sendable {
    public var name: String?
    public var managedObjectClassName: String!
    public var isAbstract = false
    public var userInfo: [AnyHashable: Any]?
    public var uniquenessConstraints: [[Any]] = []
    public var renamingIdentifier: String?
    public var versionHashModifier: String?
    public internal(set) weak var managedObjectModel: NSManagedObjectModel!
    public internal(set) weak var superentity: NSEntityDescription?
    public var subentities: [NSEntityDescription] = [] {
        didSet { for entity in subentities { entity.superentity = self } }
    }

    private var ownProperties: [NSPropertyDescription] = []
    /// The entity's properties, its superentity's included.
    public var properties: [NSPropertyDescription] {
        get { (superentity?.properties ?? []) + ownProperties }
        set {
            ownProperties = newValue
            for property in newValue { property.entity = self }
        }
    }
    public var propertiesByName: [String: NSPropertyDescription] { Dictionary(properties.map { ($0.name, $0) }, uniquingKeysWith: { _, last in last }) }
    public var attributesByName: [String: NSAttributeDescription] {
        Dictionary(properties.compactMap { $0 as? NSAttributeDescription }.map { ($0.name, $0) }, uniquingKeysWith: { _, last in last })
    }
    public var relationshipsByName: [String: NSRelationshipDescription] {
        Dictionary(properties.compactMap { $0 as? NSRelationshipDescription }.map { ($0.name, $0) }, uniquingKeysWith: { _, last in last })
    }
    public func relationships(forDestination entity: NSEntityDescription) -> [NSRelationshipDescription] {
        relationshipsByName.values.filter { $0.destinationEntity === entity }
    }
    /// Whether the entity is this one or one of its subentities' ancestors.
    public func isKindOf(entity: NSEntityDescription) -> Bool {
        var current: NSEntityDescription? = self
        while let e = current { if e === entity { return true }; current = e.superentity }
        return false
    }

    // The class that represents the entity's objects, as the model names it.
    var _class: NSManagedObject.Type?
    var _module: String?
    var _superentityName: String?
    /// Swift key paths into the generated class, by property name.
    var _keyPaths: [AnyKeyPath: String] = [:]

    public init() {}

    /// The class of the entity's objects: the generated class, or the class the model names
    /// (looked up in the module the model was generated in), or the superentity's, or
    /// `NSManagedObject`.
    var managedObjectClass: NSManagedObject.Type {
        if let _class { return _class }
        if let className = managedObjectClassName, className != "NSManagedObject" {
            let parts = className.split(separator: ".").map(String.init)
            let bare = parts.last ?? className
            let modules = [parts.count > 1 && !parts[0].isEmpty ? parts[0] : nil, _module].compactMap { $0 }
            for module in modules {
                if let type = _cdType(named: bare, in: module, kind: "C") as? NSManagedObject.Type { _class = type; return type }
            }
        }
        return superentity?.managedObjectClass ?? NSManagedObject.self
    }

    /// The entity in the context's model with the name.
    open class func entity(forEntityName entityName: String, in context: NSManagedObjectContext) -> NSEntityDescription? {
        context._model?.entitiesByName[entityName] ?? _CDModelRegistry.entity(named: entityName)
    }

    /// Creates, configures, and returns an instance of the class for the entity with the name.
    open class func insertNewObject(forEntityName entityName: String, into context: NSManagedObjectContext) -> NSManagedObject {
        guard let entity = entity(forEntityName: entityName, in: context) else {
            fatalError("NSEntityDescription: no entity named \(entityName) in the context's model")
        }
        return entity.managedObjectClass.init(entity: entity, insertInto: context)
    }

    /// A generated model's entity (the CoreDataModel plugin).
    public static func _generated(_ name: String, className: String, class managedClass: NSManagedObject.Type?, module: String,
                                  parent: String? = nil, isAbstract: Bool = false, properties: [NSPropertyDescription],
                                  keyPaths: [AnyKeyPath: String] = [:]) -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = name
        entity.managedObjectClassName = className
        entity._class = managedClass
        entity._module = module
        entity._superentityName = parent
        entity.isAbstract = isAbstract
        entity.properties = properties
        entity._keyPaths = keyPaths
        return entity
    }

    public static func == (lhs: NSEntityDescription, rhs: NSEntityDescription) -> Bool { lhs === rhs }
    public func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
    open var description: String { "NSEntityDescription(\(name ?? "?"))" }
}

// MARK: - The model

/// A programmatic representation of a model, a collection of entities.
open class NSManagedObjectModel: CustomStringConvertible, @unchecked Sendable {
    private var _entities: [NSEntityDescription] = []
    /// The model's name when it was asked for by name before its description was registered:
    /// it is resolved from the registry when first used.
    var _pendingName: String?
    var _pendingModule: String?
    public var versionIdentifiers: Set<AnyHashable> = []
    public var localizationDictionary: [String: String]?
    var _configurations: [String: [String]] = [:]

    public init() {}

    /// The model whose compiled form is at the URL: here, the generated model with the URL's
    /// file name (`Model.momd` is the model of `Model.xcdatamodeld`).
    public convenience init?(contentsOf url: URL, _ fileID: String = #fileID) {
        let file = url.lastPathComponent
        let name = file.split(separator: ".", omittingEmptySubsequences: false).dropLast().joined(separator: ".")
        guard let model = _CDModelRegistry.model(named: name.isEmpty ? file : name, module: _cdModule(fileID)) else { return nil }
        self.init()
        _entities = model.entities
        _configurations = model._configurations
        for entity in _entities where entity.managedObjectModel == nil { entity.managedObjectModel = self }
    }

    /// The model made by merging the models found (here: every generated model registered).
    open class func mergedModel(from bundles: [Bundle]?, _ fileID: String = #fileID) -> NSManagedObjectModel? {
        _CDModelRegistry.registerGenerated(module: _cdModule(fileID))
        return NSManagedObjectModel(byMerging: _CDModelRegistry.all)
    }

    public convenience init?(byMerging models: [NSManagedObjectModel]?) {
        self.init()
        _entities = (models ?? []).flatMap(\.entities)
    }

    /// The entities in the model.
    public var entities: [NSEntityDescription] {
        get { resolvePending(); return _entities }
        set {
            _entities = newValue
            _pendingName = nil
            link()
        }
    }
    public var entitiesByName: [String: NSEntityDescription] {
        Dictionary(entities.compactMap { e in e.name.map { ($0, e) } }, uniquingKeysWith: { first, _ in first })
    }
    public var configurations: [String] { Array(_configurations.keys) }
    public func entities(forConfigurationName configuration: String?) -> [NSEntityDescription]? {
        guard let configuration, let names = _configurations[configuration] else { return entities }
        return entities.filter { names.contains($0.name ?? "") }
    }
    public func fetchRequestTemplate(forName name: String) -> NSFetchRequest<NSFetchRequestResult>? { nil }
    public var entityVersionHashesByName: [String: Data] { [:] }
    public func isConfiguration(withName configuration: String?, compatibleWithStoreMetadata metadata: [String: Any]) -> Bool { true }

    /// Connects the entities: superentities, relationship destinations and inverses.
    func link() {
        let byName = Dictionary(_entities.compactMap { e in e.name.map { ($0, e) } }, uniquingKeysWith: { first, _ in first })
        for entity in _entities {
            entity.managedObjectModel = self
            if let parent = entity._superentityName, let superentity = byName[parent], !superentity.subentities.contains(where: { $0 === entity }) {
                superentity.subentities.append(entity)
            }
        }
        for entity in _entities {
            for case let relationship as NSRelationshipDescription in entity.properties {
                if relationship.destinationEntity == nil, let destination = relationship._destinationName { relationship.destinationEntity = byName[destination] }
                if relationship.inverseRelationship == nil, let inverse = relationship._inverseName {
                    relationship.inverseRelationship = relationship.destinationEntity?.relationshipsByName[inverse]
                }
            }
        }
    }

    private func resolvePending() {
        guard let name = _pendingName, let model = _CDModelRegistry.model(named: name, module: _pendingModule), model !== self else { return }
        _pendingName = nil
        _entities = model._entities
        _configurations = model._configurations
    }

    /// A generated model (the CoreDataModel plugin): its entities linked, and registered by name.
    public static func _generated(name: String, entities: [NSEntityDescription], configurations: [String: [String]] = [:]) -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        model._entities = entities
        model._configurations = configurations
        model.link()
        _CDModelRegistry.register(model, named: name)
        return model
    }

    open var description: String { "NSManagedObjectModel(\(entities.compactMap(\.name).joined(separator: ", ")))" }
}

/// What the CoreDataModel plugin generates for each data model: the model's description, made
/// once.
public protocol _GeneratedCoreDataModel {
    static var model: NSManagedObjectModel { get }
}

/// A top-level type of a module by name: its mangled name first (`4Main4ItemC` for a class,
/// `O` for an enum), then the dotted name.
func _cdType(named name: String, in module: String, kind: String) -> Any.Type? {
    func mangled(_ identifier: String) -> String { "\(identifier.utf8.count)\(identifier)" }
    if module.allSatisfy({ $0.isASCII }), name.allSatisfy({ $0.isASCII }),
       let type = _typeByName(mangled(module) + mangled(name) + kind) {
        return type
    }
    return _typeByName("\(module).\(name)")
}

/// The module a `#fileID` names (`Module/File.swift`).
func _cdModule(_ fileID: String) -> String? {
    fileID.split(separator: "/").first.map(String.init)
}

/// The generated models, by name: each registers when made; one not made yet is found by its
/// generated type's name in the module that asks for it.
enum _CDModelRegistry {
    nonisolated(unsafe) private static var models: [String: NSManagedObjectModel] = [:]
    nonisolated(unsafe) private static var order: [String] = []

    static func register(_ model: NSManagedObjectModel, named name: String) {
        if models[name] == nil { order.append(name) }
        models[name] = model
    }

    static var all: [NSManagedObjectModel] { order.compactMap { models[$0] } }

    /// The generated type's name for a model (the plugin writes the same).
    static func typeName(for model: String) -> String {
        "_SwiftUIWebCoreDataModel_" + String(model.map { $0.isLetter || $0.isNumber || $0 == "_" ? $0 : "_" })
    }

    static func model(named name: String, module: String?) -> NSManagedObjectModel? {
        if let model = models[name] { return model }
        if let module, let type = _cdType(named: typeName(for: name), in: module, kind: "O") as? _GeneratedCoreDataModel.Type {
            return type.model
        }
        return nil
    }

    /// Registers the models generated in a module that are known by name (the module's own
    /// `_SwiftUIWebCoreDataModels` index, which the plugin writes).
    static func registerGenerated(module: String?) {
        guard let module, let index = _cdType(named: "_SwiftUIWebCoreDataModels", in: module, kind: "O") as? _GeneratedCoreDataModelIndex.Type else { return }
        for type in index.models { _ = type.model }
    }

    static func entity(named name: String) -> NSEntityDescription? {
        for model in all { if let entity = model.entitiesByName[name] { return entity } }
        return nil
    }

    static func entity(for type: AnyClass) -> NSEntityDescription? {
        for model in all {
            if let entity = model.entities.first(where: { $0._class == type || ($0._class == nil && $0.managedObjectClass == type) }) { return entity }
        }
        return nil
    }

    static func key(for keyPath: AnyKeyPath) -> String? {
        for model in all { for entity in model.entities { if let key = entity._keyPaths[keyPath] { return key } } }
        return nil
    }
}

/// The index of a module's generated models (the CoreDataModel plugin).
public protocol _GeneratedCoreDataModelIndex {
    static var models: [any _GeneratedCoreDataModel.Type] { get }
}
