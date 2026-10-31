// CoreDataModelGen: the CoreDataModel build plugin's tool. It reads a target's Core Data models
// (`.xcdatamodeld` bundles, or bare `.xcdatamodel` directories) and writes the Swift Xcode would
// generate for them (the entity classes and their `@NSManaged` properties, here accessors over
// the object's values), plus a description of each model that `NSPersistentContainer(name:)`
// finds by the model's name.
//
//   CoreDataModelGen <output.swift> <module> <model>...

#if os(WASI)
print("CoreDataModelGen runs on the build host")
#else
import Foundation

// MARK: - Reading the model's XML

struct XMLElement {
    var name: String
    var attributes: [String: String]
    var children: [XMLElement] = []
    func attribute(_ key: String) -> String? { attributes[key] }
    func flag(_ key: String) -> Bool { attributes[key] == "YES" }
    func all(_ name: String) -> [XMLElement] { children.filter { $0.name == name } }
}

/// A small XML reader for the model's `contents` file: elements and attributes (no text nodes
/// are needed, except the current-version plist's strings, read separately).
func parseXML(_ text: String) -> XMLElement {
    var stack: [XMLElement] = [XMLElement(name: "#document", attributes: [:])]
    let scalars = Array(text.unicodeScalars)
    var i = 0
    func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&#10;", with: "\n").replacingOccurrences(of: "&amp;", with: "&")
    }
    while i < scalars.count {
        guard scalars[i] == "<" else { i += 1; continue }
        var j = i + 1
        // Declarations, comments and processing instructions.
        if j < scalars.count, scalars[j] == "?" || scalars[j] == "!" {
            if j + 2 < scalars.count, scalars[j] == "!", scalars[j + 1] == "-", scalars[j + 2] == "-" {
                while j + 2 < scalars.count, !(scalars[j] == "-" && scalars[j + 1] == "-" && scalars[j + 2] == ">") { j += 1 }
                i = j + 3
            } else {
                while j < scalars.count, scalars[j] != ">" { j += 1 }
                i = j + 1
            }
            continue
        }
        let closing = j < scalars.count && scalars[j] == "/"
        if closing { j += 1 }
        var name = ""
        while j < scalars.count, !" \t\r\n/>".unicodeScalars.contains(scalars[j]) { name.unicodeScalars.append(scalars[j]); j += 1 }
        var attributes: [String: String] = [:]
        var selfClosing = false
        while j < scalars.count, scalars[j] != ">" {
            if scalars[j] == "/" { selfClosing = true; j += 1; continue }
            if " \t\r\n".unicodeScalars.contains(scalars[j]) { j += 1; continue }
            var key = ""
            while j < scalars.count, !"= \t\r\n/>".unicodeScalars.contains(scalars[j]) { key.unicodeScalars.append(scalars[j]); j += 1 }
            while j < scalars.count, " \t\r\n".unicodeScalars.contains(scalars[j]) { j += 1 }
            guard j < scalars.count, scalars[j] == "=" else { continue }
            j += 1
            while j < scalars.count, " \t\r\n".unicodeScalars.contains(scalars[j]) { j += 1 }
            guard j < scalars.count else { break }
            let quote = scalars[j]
            j += 1
            var value = ""
            while j < scalars.count, scalars[j] != quote { value.unicodeScalars.append(scalars[j]); j += 1 }
            j += 1
            attributes[key] = unescape(value)
        }
        i = j + 1
        if closing {
            if stack.count > 1 {
                let element = stack.removeLast()
                stack[stack.count - 1].children.append(element)
            }
        } else if selfClosing {
            stack[stack.count - 1].children.append(XMLElement(name: name, attributes: attributes))
        } else {
            stack.append(XMLElement(name: name, attributes: attributes))
        }
    }
    while stack.count > 1 {
        let element = stack.removeLast()
        stack[stack.count - 1].children.append(element)
    }
    return stack[0]
}

// MARK: - The model

struct Attribute {
    var name: String
    var type: String
    var optional: Bool
    var transient: Bool
    var scalar: Bool
    var defaultValue: String?
    var customClassName: String?
}

struct Relationship {
    var name: String
    var destination: String
    var inverse: String?
    var toMany: Bool
    var ordered: Bool
    var optional: Bool
    var deleteRule: String
    var minCount: Int
    var maxCount: Int
}

struct Entity {
    var name: String
    var className: String?
    var parent: String?
    var isAbstract: Bool
    var codegen: String?
    var attributes: [Attribute]
    var relationships: [Relationship]
    /// Properties in the model's order (attributes and relationships interleaved).
    var order: [String]

    /// The Swift class name: the represented class without a module prefix.
    var swiftClass: String? {
        guard let className, !className.isEmpty, className != "NSManagedObject" else { return nil }
        return className.split(separator: ".").last.map(String.init)
    }
    /// Whether this tool writes the class (Xcode's "Class Definition") or only its
    /// properties (Xcode's "Category/Extension").
    var generatesClass: Bool { codegen == "class" && swiftClass != nil }
    var generatesProperties: Bool { (codegen == "class" || codegen == "category") && swiftClass != nil }
}

struct Model {
    var name: String
    var entities: [Entity]
    var configurations: [(String, [String])]
}

func readModel(at path: String) throws -> Model {
    let url = URL(fileURLWithPath: path)
    let name = url.deletingPathExtension().lastPathComponent
    var versionURL = url
    if url.pathExtension == "xcdatamodeld" {
        let fm = FileManager.default
        var current: String?
        let plist = url.appendingPathComponent(".xccurrentversion")
        if let text = try? String(contentsOf: plist, encoding: .utf8),
           let range = text.range(of: "_XCCurrentVersionName") {
            let rest = text[range.upperBound...]
            if let open = rest.range(of: "<string>"), let close = rest.range(of: "</string>", range: open.upperBound..<rest.endIndex) {
                current = String(rest[open.upperBound..<close.lowerBound])
            }
        }
        if let current, fm.fileExists(atPath: url.appendingPathComponent(current).path) {
            versionURL = url.appendingPathComponent(current)
        } else {
            let versions = ((try? fm.contentsOfDirectory(atPath: url.path)) ?? []).filter { $0.hasSuffix(".xcdatamodel") }.sorted()
            guard let last = versions.last else { throw GenError("no .xcdatamodel in \(path)") }
            versionURL = url.appendingPathComponent(last)
        }
    }
    let contents = versionURL.appendingPathComponent("contents")
    let text = try String(contentsOf: contents, encoding: .utf8)
    let document = parseXML(text)
    guard let root = document.children.first(where: { $0.name == "model" }) else { throw GenError("no <model> in \(contents.path)") }
    var entities: [Entity] = []
    for element in root.all("entity") {
        guard let entityName = element.attribute("name") else { continue }
        var entity = Entity(name: entityName, className: element.attribute("representedClassName"), parent: element.attribute("parentEntity"),
                            isAbstract: element.flag("isAbstract"), codegen: element.attribute("codeGenerationType"),
                            attributes: [], relationships: [], order: [])
        for child in element.children {
            guard let propertyName = child.attribute("name") else { continue }
            switch child.name {
            case "attribute":
                let type = child.attribute("attributeType") ?? "Undefined"
                let scalar = child.attribute("usesScalarValueType").map { $0 == "YES" } ?? true
                entity.attributes.append(Attribute(name: propertyName, type: type, optional: child.flag("optional"), transient: child.flag("transient"),
                                                   scalar: scalar, defaultValue: child.attribute("defaultValueString"),
                                                   customClassName: child.attribute("customClassName")))
                entity.order.append(propertyName)
            case "relationship":
                guard let destination = child.attribute("destinationEntity") else { continue }
                entity.relationships.append(Relationship(name: propertyName, destination: destination, inverse: child.attribute("inverseName"),
                                                         toMany: child.flag("toMany"), ordered: child.flag("ordered"), optional: child.flag("optional"),
                                                         deleteRule: child.attribute("deletionRule") ?? "Nullify",
                                                         minCount: Int(child.attribute("minCount") ?? "") ?? 0, maxCount: Int(child.attribute("maxCount") ?? "") ?? 0))
                entity.order.append(propertyName)
            default:
                continue
            }
        }
        entities.append(entity)
    }
    var configurations: [(String, [String])] = []
    for element in root.all("configuration") {
        guard let configurationName = element.attribute("name") else { continue }
        configurations.append((configurationName, element.all("memberEntity").compactMap { $0.attribute("name") }))
    }
    return Model(name: name, entities: entities, configurations: configurations)
}

struct GenError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

// MARK: - Writing Swift

let keywords: Set<String> = [
    "associatedtype", "class", "deinit", "enum", "extension", "fileprivate", "func", "import", "init", "inout", "internal", "let", "open",
    "operator", "private", "precedencegroup", "protocol", "public", "rethrows", "static", "struct", "subscript", "typealias", "var",
    "break", "case", "catch", "continue", "default", "defer", "do", "else", "fallthrough", "for", "guard", "if", "in", "repeat", "return",
    "throw", "switch", "where", "while", "Any", "as", "false", "is", "nil", "self", "Self", "super", "throws", "true", "try",
]

func identifier(_ name: String) -> String { keywords.contains(name) ? "`\(name)`" : name }

func literal(_ string: String) -> String {
    var out = "\""
    for scalar in string.unicodeScalars {
        switch scalar {
        case "\\": out += "\\\\"
        case "\"": out += "\\\""
        case "\n": out += "\\n"
        case "\r": out += "\\r"
        case "\t": out += "\\t"
        default: out.unicodeScalars.append(scalar)
        }
    }
    return out + "\""
}

func capitalized(_ name: String) -> String { name.prefix(1).uppercased() + name.dropFirst() }

/// The attribute's `NSAttributeType` case.
func attributeType(_ type: String) -> String {
    switch type {
    case "Integer 16": return ".integer16AttributeType"
    case "Integer 32": return ".integer32AttributeType"
    case "Integer 64": return ".integer64AttributeType"
    case "Decimal": return ".decimalAttributeType"
    case "Double": return ".doubleAttributeType"
    case "Float": return ".floatAttributeType"
    case "String": return ".stringAttributeType"
    case "Boolean": return ".booleanAttributeType"
    case "Date": return ".dateAttributeType"
    case "Binary": return ".binaryDataAttributeType"
    case "UUID": return ".UUIDAttributeType"
    case "URI": return ".URIAttributeType"
    case "Transformable": return ".transformableAttributeType"
    case "Object ID": return ".objectIDAttributeType"
    case "Composite": return ".compositeAttributeType"
    default: return ".undefinedAttributeType"
    }
}

/// The attribute's default value as a Swift expression, or `nil`.
func defaultValue(_ attribute: Attribute) -> String {
    guard let text = attribute.defaultValue else { return "nil" }
    switch attribute.type {
    case "Integer 16", "Integer 32", "Integer 64":
        return Int64(text).map { "Int64(\($0))" } ?? Double(text).map { "Int64(\(Int64($0)))" } ?? "nil"
    case "Double", "Float", "Decimal":
        return Double(text).map { "Double(\($0))" } ?? "nil"
    case "Boolean":
        return ["YES", "TRUE", "1"].contains(text.uppercased()) ? "true" : "false"
    case "String":
        return literal(text)
    case "Date":
        return Double(text).map { "Date(timeIntervalSinceReferenceDate: \($0))" } ?? "nil"
    case "UUID":
        return "UUID(uuidString: \(literal(text)))"
    case "URI":
        return "URL(string: \(literal(text)))"
    default:
        return "nil"
    }
}

/// The Swift type and accessor body Xcode's generated property has, for an attribute.
func property(_ attribute: Attribute) -> (type: String, get: String)? {
    let key = literal(attribute.name)
    switch attribute.type {
    case "Integer 16": return attribute.scalar ? ("Int16", "_genInteger(\(key))") : ("NSNumber?", "_genNumber(\(key))")
    case "Integer 32": return attribute.scalar ? ("Int32", "_genInteger(\(key))") : ("NSNumber?", "_genNumber(\(key))")
    case "Integer 64": return attribute.scalar ? ("Int64", "_genInteger(\(key))") : ("NSNumber?", "_genNumber(\(key))")
    case "Double": return attribute.scalar ? ("Double", "_genDouble(\(key))") : ("NSNumber?", "_genNumber(\(key))")
    case "Float": return attribute.scalar ? ("Float", "_genFloat(\(key))") : ("NSNumber?", "_genNumber(\(key))")
    case "Boolean": return attribute.scalar ? ("Bool", "_genBool(\(key))") : ("NSNumber?", "_genNumber(\(key))")
    case "Decimal": return ("Decimal?", "_genValue(\(key))")
    case "String": return ("String?", "_genValue(\(key))")
    case "Date": return ("Date?", "_genValue(\(key))")
    case "Binary": return ("Data?", "_genValue(\(key))")
    case "UUID": return ("UUID?", "_genValue(\(key))")
    case "URI": return ("URL?", "_genValue(\(key))")
    case "Object ID": return ("NSManagedObjectID?", "_genValue(\(key))")
    case "Transformable":
        let className = attribute.customClassName.flatMap { $0.isEmpty ? nil : $0 } ?? "NSObject"
        let bridged = ["NSArray": "[Any]", "NSMutableArray": "[Any]", "NSDictionary": "[AnyHashable: Any]", "NSMutableDictionary": "[AnyHashable: Any]",
                       "NSString": "String", "NSData": "Data", "NSDate": "Date", "NSURL": "URL", "NSUUID": "UUID"]
        let bare = className.hasPrefix("[") ? className : (className.split(separator: ".").last.map(String.init) ?? className)
        return ("\(bridged[bare] ?? bare)?", "_genValue(\(key))")
    default:
        return nil
    }
}

func deleteRule(_ rule: String) -> String {
    switch rule {
    case "Cascade": return ".cascadeDeleteRule"
    case "Deny": return ".denyDeleteRule"
    case "No Action": return ".noActionDeleteRule"
    default: return ".nullifyDeleteRule"
    }
}

func modelTypeName(_ model: String) -> String {
    "_SwiftUIWebCoreDataModel_" + String(model.map { $0.isLetter || $0.isNumber || $0 == "_" ? $0 : "_" })
}

func generate(models: [Model], module: String) -> String {
    var out = """
    // Generated by the CoreDataModel plugin from \(models.map { $0.name + ".xcdatamodeld" }.joined(separator: ", ")). Do not edit.
    import WebCoreData
    #if canImport(UIKit)
    import UIKit   // transformable attributes of UIKit classes (UIColor, UIImage)
    #endif

    """
    var classOwners: [String: String] = [:]   // class name -> the model that writes it
    for model in models {
        let modelType = modelTypeName(model.name)
        let byName = Dictionary(model.entities.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        func className(of entityName: String) -> String {
            byName[entityName]?.swiftClass ?? "NSManagedObject"
        }

        for entity in model.entities where entity.generatesProperties {
            guard let swiftClass = entity.swiftClass, classOwners[swiftClass] == nil else { continue }
            classOwners[swiftClass] = model.name
            if entity.generatesClass {
                let superclass = entity.parent.map(className(of:)) ?? "NSManagedObject"
                out += """

                public class \(swiftClass): \(superclass), @unchecked Sendable {
                    public override class func entity() -> NSEntityDescription {
                        \(modelType).model.entitiesByName[\(literal(entity.name))]!
                    }
                }

                """
            }
            out += """

            extension \(swiftClass) {
                public class func fetchRequest() -> NSFetchRequest<\(swiftClass)> {
                    let request = NSFetchRequest<\(swiftClass)>(entityName: \(literal(entity.name)))
                    request.entity = \(modelType).model.entitiesByName[\(literal(entity.name))]
                    return request
                }

            """
            for attribute in entity.attributes {
                guard let (type, get) = property(attribute) else { continue }
                out += """
                    public var \(identifier(attribute.name)): \(type) {
                        get { \(get) }
                        set { _genSetValue(newValue, \(literal(attribute.name))) }
                    }

                """
            }
            for relationship in entity.relationships {
                let destination = className(of: relationship.destination)
                let type = relationship.toMany ? (relationship.ordered ? "NSOrderedSet?" : "NSSet?") : "\(destination)?"
                let get = relationship.toMany ? (relationship.ordered ? "_genOrdered" : "_genSet") : "_genObject"
                out += """
                    public var \(identifier(relationship.name)): \(type) {
                        get { \(get)(\(literal(relationship.name))) }
                        set { _genSetValue(newValue, \(literal(relationship.name))) }
                    }

                """
            }
            out += "}\n"
            for relationship in entity.relationships where relationship.toMany {
                let destination = className(of: relationship.destination)
                let name = capitalized(relationship.name)
                let key = literal(relationship.name)
                out += """

                // MARK: Generated accessors for \(relationship.name)
                extension \(swiftClass) {
                    public func addTo\(name)(_ value: \(destination)) { _genAdd(value, \(key)) }
                    public func removeFrom\(name)(_ value: \(destination)) { _genRemove(value, \(key)) }

                """
                if relationship.ordered {
                    out += """
                        public func insertInto\(name)(_ value: \(destination), at idx: Int) { _genInsert(value, at: idx, \(key)) }
                        public func removeFrom\(name)(at idx: Int) { _genRemove(at: idx, \(key)) }
                        public func insertInto\(name)(_ values: [\(destination)], at indexes: IndexSet) { _genInsert(values, at: indexes, \(key)) }
                        public func removeFrom\(name)(at indexes: IndexSet) { _genRemove(at: indexes, \(key)) }
                        public func replace\(name)(at idx: Int, with value: \(destination)) { _genReplace(at: idx, with: value, \(key)) }
                        public func addTo\(name)(_ values: NSOrderedSet) { _genAdd(values, \(key)) }
                        public func removeFrom\(name)(_ values: NSOrderedSet) { _genRemove(values, \(key)) }

                    """
                } else {
                    out += """
                        public func addTo\(name)(_ values: NSSet) { _genAdd(values, \(key)) }
                        public func removeFrom\(name)(_ values: NSSet) { _genRemove(values, \(key)) }

                    """
                }
                out += "}\n"
            }
            // `Identifiable` is NSManagedObject's own (WebCoreData), as on Apple platforms.
        }

        // The model's description.
        out += """

        public enum \(modelType): _GeneratedCoreDataModel {
            public static let model: NSManagedObjectModel = NSManagedObjectModel._generated(name: \(literal(model.name)), entities: [

        """
        for entity in model.entities {
            let generated = entity.generatesProperties && classOwners[entity.swiftClass ?? ""] == model.name
            let classExpression = generated ? "\(entity.swiftClass!).self" : "nil"
            out += """
                    NSEntityDescription._generated(\(literal(entity.name)), className: \(literal(entity.className ?? "NSManagedObject")), class: \(classExpression), module: \(literal(module)),
                                                   parent: \(entity.parent.map(literal) ?? "nil"), isAbstract: \(entity.isAbstract), properties: [

            """
            for name in entity.order {
                if let attribute = entity.attributes.first(where: { $0.name == name }) {
                    out += "                NSAttributeDescription._generated(\(literal(name)), \(attributeType(attribute.type)), optional: \(attribute.optional), transient: \(attribute.transient), defaultValue: \(defaultValue(attribute))),\n"
                } else if let relationship = entity.relationships.first(where: { $0.name == name }) {
                    out += "                NSRelationshipDescription._generated(\(literal(name)), destination: \(literal(relationship.destination)), inverse: \(relationship.inverse.map(literal) ?? "nil"), toMany: \(relationship.toMany), ordered: \(relationship.ordered), optional: \(relationship.optional), deleteRule: \(deleteRule(relationship.deleteRule)), minCount: \(relationship.minCount), maxCount: \(relationship.maxCount)),\n"
                }
            }
            out += "            ]"
            if generated, let swiftClass = entity.swiftClass {
                let names = entity.attributes.filter { property($0) != nil }.map(\.name) + entity.relationships.map(\.name)
                if names.isEmpty {
                    out += ", keyPaths: [:]"
                } else {
                    out += ", keyPaths: [\n"
                    for name in names { out += "                \\\(swiftClass).\(identifier(name)): \(literal(name)),\n" }
                    out += "            ]"
                }
            }
            out += "),\n"
        }
        out += "        ]"
        if !model.configurations.isEmpty {
            out += ", configurations: [\n"
            for (name, members) in model.configurations {
                out += "            \(literal(name)): [\(members.map(literal).joined(separator: ", "))],\n"
            }
            out += "        ]"
        }
        out += ")\n}\n"
    }
    out += """

    public enum _SwiftUIWebCoreDataModels: _GeneratedCoreDataModelIndex {
        public static var models: [any _GeneratedCoreDataModel.Type] { [\(models.map { modelTypeName($0.name) + ".self" }.joined(separator: ", "))] }
    }

    """
    return out
}

// MARK: - Main

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    FileHandle.standardError.write(Data("usage: CoreDataModelGen <output.swift> <module> <model>...\n".utf8))
    exit(2)
}
do {
    let models = try arguments.dropFirst(3).map(readModel(at:))
    let source = generate(models: models, module: arguments[2])
    try source.write(to: URL(fileURLWithPath: arguments[1]), atomically: true, encoding: .utf8)
} catch {
    FileHandle.standardError.write(Data("CoreDataModelGen: \(error)\n".utf8))
    exit(1)
}
#endif
