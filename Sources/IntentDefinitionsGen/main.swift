// IntentDefinitionsGen: the IntentDefinitions build plugin's tool. It reads a target's intent
// definition files (`.intentdefinition`, the property lists Xcode's intent editor writes) and
// writes the Swift Xcode would generate for them: each intent's `INIntent` subclass with its
// parameters, its response and its handling protocol (the handler methods Siri calls are
// optional in Objective-C; here they have default implementations), each custom type's
// `INObject` subclass and each enum.
//
//   IntentDefinitionsGen <output.swift> <definition>...

#if os(WASI)
print("IntentDefinitionsGen runs on the build host")
#else
import Foundation

struct Parameter {
    var name: String
    var type: String
    var multiple: Bool
    var dynamicOptions: Bool
}

struct Intent {
    var name: String
    var parameters: [Parameter]
    var responseCodes: [String]
}

struct EnumDefinition {
    var name: String
    var values: [(name: String, index: Int)]
}

struct TypeDefinition {
    var name: String
    var properties: [Parameter]
}

struct Definitions {
    var intents: [Intent] = []
    var enums: [EnumDefinition] = []
    var types: [TypeDefinition] = []
}

/// The Swift type of a parameter or property, as Xcode's generated interface names it.
func swiftType(kind: String?, enumType: String?, objectType: String?) -> String {
    if let enumType { return enumType }
    switch kind ?? "" {
    case "Integer", "Boolean", "Decimal", "Number": return "NSNumber"
    case "String": return "String"
    case "Object": return objectType ?? "INObject"
    case "DateComponents", "Date": return "DateComponents"
    case "URL": return "URL"
    case "SpeakableString": return "INSpeakableString"
    default: return objectType ?? "Any"
    }
}

func readParameter(_ p: [String: Any], prefix: String) -> Parameter? {
    guard let name = p["\(prefix)Name"] as? String, !name.isEmpty else { return nil }
    let type = swiftType(kind: p["\(prefix)Type"] as? String, enumType: p["\(prefix)EnumType"] as? String,
                         objectType: p["\(prefix)ObjectType"] as? String)
    return Parameter(name: name, type: type,
                     multiple: p["\(prefix)SupportsMultipleValues"] as? Bool ?? false,
                     dynamicOptions: p["\(prefix)SupportsDynamicEnumeration"] as? Bool ?? false)
}

func read(_ path: String, into definitions: inout Definitions) throws {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return }
    for i in plist["INIntents"] as? [[String: Any]] ?? [] {
        guard let name = i["INIntentName"] as? String, !name.isEmpty else { continue }
        let parameters = (i["INIntentParameters"] as? [[String: Any]] ?? []).compactMap { readParameter($0, prefix: "INIntentParameter") }
        let response = i["INIntentResponse"] as? [String: Any]
        let codes = (response?["INIntentResponseCodes"] as? [[String: Any]] ?? []).compactMap { $0["INIntentResponseCodeName"] as? String }
        definitions.intents.append(Intent(name: name, parameters: parameters, responseCodes: codes))
    }
    for e in plist["INEnums"] as? [[String: Any]] ?? [] {
        guard let name = e["INEnumName"] as? String, !name.isEmpty else { continue }
        var values: [(String, Int)] = []
        for (n, v) in (e["INEnumValues"] as? [[String: Any]] ?? []).enumerated() {
            guard let valueName = v["INEnumValueName"] as? String, !valueName.isEmpty else { continue }
            values.append((valueName, v["INEnumValueIndex"] as? Int ?? n))
        }
        if !values.contains(where: { $0.1 == 0 }) { values.insert(("unknown", 0), at: 0) }
        definitions.enums.append(EnumDefinition(name: name, values: values))
    }
    for t in plist["INTypes"] as? [[String: Any]] ?? [] {
        guard let name = t["INTypeName"] as? String, !name.isEmpty else { continue }
        // `identifier`, `displayString`, `pronunciationHint` and `alternativeSpeakableMatches`
        // are `INObject`'s own.
        let builtIn: Set<String> = ["identifier", "displayString", "pronunciationHint", "alternativeSpeakableMatches"]
        let properties = (t["INTypeProperties"] as? [[String: Any]] ?? [])
            .compactMap { readParameter($0, prefix: "INTypeProperty") }
            .filter { !builtIn.contains($0.name) }
        definitions.types.append(TypeDefinition(name: name, properties: properties))
    }
}

func capitalized(_ name: String) -> String { name.prefix(1).uppercased() + name.dropFirst() }

/// A property's declaration: an enum is never optional (its `unknown` case is the unset value).
func declaration(_ p: Parameter, enums: Set<String>) -> String {
    if enums.contains(p.type) && !p.multiple { return "    public var `\(p.name)`: \(p.type) = .\("unknown")\n" }
    let type = p.multiple ? "[\(p.type)]" : p.type
    return "    public var `\(p.name)`: \(type)?\n"
}

func generate(_ d: Definitions) -> String {
    let enumNames = Set(d.enums.map(\.name))
    var out = """
    // Generated by IntentDefinitionsGen from the target's intent definitions. Do not edit.
    // Nonisolated, as Xcode's are, in a module whose default isolation is the main actor too.
    import Intents   // which re-exports Foundation (WebFoundation on the web), as Apple's does


    """
    for e in d.enums {
        // An enum whose `unknown` case is not 0 still starts there for the unset value.
        let hasUnknown = e.values.contains { $0.name == "unknown" }
        out += "nonisolated public enum \(e.name): Int, CaseIterable, Sendable {\n"
        for v in e.values { out += "    case `\(v.name)` = \(v.index)\n" }
        if !hasUnknown { out += "    public static var unknown: \(e.name) { \(e.name)(rawValue: 0) ?? .allCases[0] }\n" }
        out += "}\n\n"
    }
    for t in d.types {
        out += "nonisolated public class \(t.name): INObject {\n"
        for p in t.properties { out += declaration(p, enums: enumNames) }
        out += "}\n\n"
    }
    for i in d.intents {
        let intent = "\(i.name)Intent"
        out += "nonisolated public class \(intent): INIntent {\n"
        for p in i.parameters { out += declaration(p, enums: enumNames) }
        out += "}\n\n"
        // The response: Siri's codes, then the definition's own after 100, as Xcode numbers them.
        let system = ["unspecified", "ready", "continueInApp", "inProgress", "success", "failure", "failureRequiringAppLaunch"]
        let custom = i.responseCodes.filter { !system.contains($0) }
        out += "nonisolated public class \(intent)Response: INIntentResponse {\n"
        out += "    public enum Code: Int, Sendable {\n"
        for (n, c) in system.enumerated() { out += "        case `\(c)` = \(n)\n" }
        for (n, c) in custom.enumerated() { out += "        case `\(c)` = \(100 + n)\n" }
        out += "    }\n"
        out += "    public private(set) var code: Code = .unspecified\n"
        out += "    public convenience init(code: Code, userActivity: NSUserActivity?) {\n"
        out += "        self.init()\n        self.code = code\n        self.userActivity = userActivity\n    }\n"
        out += "}\n\n"
        // The handling protocol, with the option providers of the parameters whose options
        // the app lists (the Objective-C protocol's optional methods have defaults here).
        out += "nonisolated public protocol \(intent)Handling: AnyObject {\n"
        var defaults = ""
        for p in i.parameters where p.dynamicOptions {
            let element = enumNames.contains(p.type) ? "NSNumber" : p.type
            let method = "provide\(capitalized(p.name))OptionsCollection"
            out += "    func \(method)(for intent: \(intent), with completion: @escaping (INObjectCollection<\(element)>?, (any Error)?) -> Void)\n"
            out += "    func \(method)(for intent: \(intent)) async throws -> INObjectCollection<\(element)>\n"
            defaults += "    public func \(method)(for intent: \(intent), with completion: @escaping (INObjectCollection<\(element)>?, (any Error)?) -> Void) { completion(nil, nil) }\n"
            defaults += "    public func \(method)(for intent: \(intent)) async throws -> INObjectCollection<\(element)> { INObjectCollection(items: []) }\n"
        }
        out += "    func handle(intent: \(intent), completion: @escaping (\(intent)Response) -> Void)\n"
        out += "    func confirm(intent: \(intent), completion: @escaping (\(intent)Response) -> Void)\n"
        out += "}\n\n"
        out += "nonisolated extension \(intent)Handling {\n" + defaults
        out += "    public func handle(intent: \(intent), completion: @escaping (\(intent)Response) -> Void) { completion(\(intent)Response(code: .success, userActivity: nil)) }\n"
        out += "    public func confirm(intent: \(intent), completion: @escaping (\(intent)Response) -> Void) { completion(\(intent)Response(code: .ready, userActivity: nil)) }\n"
        out += "}\n\n"
    }
    return out
}

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: IntentDefinitionsGen <output.swift> <definition>...\n".utf8))
    exit(2)
}
do {
    var definitions = Definitions()
    for path in arguments.dropFirst(2) { try read(path, into: &definitions) }
    // A definition localised into several `.lproj` folders defines each intent once.
    var seen = Set<String>()
    definitions.intents = definitions.intents.filter { seen.insert("i." + $0.name).inserted }
    definitions.enums = definitions.enums.filter { seen.insert("e." + $0.name).inserted }
    definitions.types = definitions.types.filter { seen.insert("t." + $0.name).inserted }
    try generate(definitions).write(to: URL(fileURLWithPath: arguments[1]), atomically: true, encoding: .utf8)
} catch {
    FileHandle.standardError.write(Data("IntentDefinitionsGen: \(error)\n".utf8))
    exit(1)
}
#endif
