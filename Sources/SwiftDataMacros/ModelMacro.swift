// `@Model` (decision 0021, pf-swiftdata): on a final class, it adds the store's bookkeeping
// (`_storage`), the property table (`_persistedProperties`: every stored `var` with its kind
// from `@Attribute`/`@Relationship`, unique flag and inverse), a `_make(from:in:)` that rebuilds
// an instance from stored values, observation (`@Observable`'s shape over `_$observationRegistrar`)
// and the `PersistentModel` conformance. Setters report changes to the storage so the context
// autosaves. `@Attribute` and `@Relationship` themselves expand to nothing: `@Model` reads them.
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

public struct ModelMacro: MemberMacro, MemberAttributeMacro, ExtensionMacro {
    struct Property {
        let name: String
        let type: String
        let isOptional: Bool
        let isArray: Bool
        let elementType: String
        let isUnique: Bool
        let isRelationship: Bool
        let inverse: String?
        let initializer: String?
    }

    static func properties(of declaration: some DeclGroupSyntax, in context: some MacroExpansionContext) throws -> [Property] {
        var result: [Property] = []
        for member in declaration.memberBlock.members {
            guard let variable = member.decl.as(VariableDeclSyntax.self), variable.bindingSpecifier.text == "var",
                  let binding = variable.bindings.first, let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else { continue }
            if variable.modifiers.contains(where: { $0.name.text == "static" }) { continue }
            if let accessors = binding.accessorBlock, case .getter = accessors.accessors { continue }   // a computed property
            if let accessors = binding.accessorBlock, case .accessors(let list) = accessors.accessors, list.contains(where: { $0.accessorSpecifier.text == "get" }) { continue }
            let attributes = variable.attributes.compactMap { $0.as(AttributeSyntax.self) }
            if attributes.contains(where: { $0.attributeName.trimmedDescription == "Transient" }) { continue }
            guard let typeSyntax = binding.typeAnnotation?.type else {
                context.diagnose(Diagnostic(node: Syntax(variable), message: ModelMessage("'@Model' needs an explicit type on '\(name)'")))
                continue
            }
            let type = typeSyntax.trimmedDescription
            var isOptional = false, isArray = false, element = type
            var inner = typeSyntax
            if let optional = inner.as(OptionalTypeSyntax.self) { isOptional = true; inner = optional.wrappedType; element = inner.trimmedDescription }
            if let array = inner.as(ArrayTypeSyntax.self) { isArray = true; element = array.element.trimmedDescription }
            let attribute = attributes.first { $0.attributeName.trimmedDescription == "Attribute" }
            let relationship = attributes.first { $0.attributeName.trimmedDescription == "Relationship" }
            let unique = attribute?.arguments?.description.contains(".unique") ?? false
            var inverse: String?
            if let relationship, let arguments = relationship.arguments?.as(LabeledExprListSyntax.self) {
                for argument in arguments where argument.label?.text == "inverse" {
                    // `\CountryDetails.neighbors` → "neighbors"
                    inverse = argument.expression.trimmedDescription.split(separator: ".").last.map(String.init)
                }
            }
            // A relationship: declared so, or typed as another model (an array or optional of a capitalised type that is not a value type we know).
            let valueTypes: Set<String> = ["String", "Int", "Double", "Float", "Bool", "Data", "Date", "URL", "UUID", "Int64", "Int32", "Decimal"]
            let elementIsValue = valueTypes.contains(element) || element.hasPrefix("[") || element.hasPrefix("Dictionary") || element.hasPrefix("Set<")
            let isRelationship = relationship != nil || (!elementIsValue && element.first?.isUppercase == true && !element.contains("<"))
            result.append(Property(name: name, type: type, isOptional: isOptional, isArray: isArray, elementType: element, isUnique: unique,
                                   isRelationship: isRelationship, inverse: inverse, initializer: binding.initializer?.value.trimmedDescription))
        }
        return result
    }

    public static func expansion(of node: AttributeSyntax, providingMembersOf declaration: some DeclGroupSyntax, conformingTo protocols: [TypeSyntax],
                                 in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        guard let classDecl = declaration.as(ClassDeclSyntax.self) else {
            context.diagnose(Diagnostic(node: Syntax(node), message: ModelMessage("'@Model' can only be applied to a class")))
            return []
        }
        let name = classDecl.name.text
        let properties = try properties(of: declaration, in: context)
        var entries: [String] = []
        for property in properties {
            if property.isRelationship {
                let kind = property.isArray ? ".toMany" : ".toOne"
                let readModels: String
                let setModels: String
                let read: String
                let write: String
                if property.isArray {
                    let unwrap = property.isOptional ? " ?? []" : ""
                    readModels = "{ model in ((model as! \(name)).\(property.name)\(unwrap)).map { $0 as any PersistentModel } }"
                    setModels = "{ model, related in (model as! \(name))._\(property.name) = related.compactMap { $0 as? \(property.elementType) } }"
                    read = "{ model in .references(((model as! \(name)).\(property.name)\(unwrap)).map { $0.persistentModelID }) }"
                    write = """
                    { model, value, context in
                        guard case .references(let ids) = value else { return }
                        (model as! \(name))._\(property.name) = ids.compactMap { context?._resolve($0) as? \(property.elementType) }
                    }
                    """
                } else {
                    readModels = "{ model in ((model as! \(name)).\(property.name)).map { [$0 as any PersistentModel] } ?? [] }"
                    setModels = "{ model, related in (model as! \(name))._\(property.name) = related.first as? \(property.elementType) }"
                    read = "{ model in (model as! \(name)).\(property.name).map { .reference($0.persistentModelID) } ?? .null }"
                    write = """
                    { model, value, context in
                        if case .reference(let id) = value { (model as! \(name))._\(property.name) = context?._resolve(id) as? \(property.elementType) }
                        else { (model as! \(name))._\(property.name) = nil }
                    }
                    """
                }
                let inverse = property.inverse.map { "\"\($0)\"" } ?? "nil"
                entries.append("""
                _PersistedProperty(name: "\(property.name)", kind: \(kind), isUnique: false, relatedEntity: "\(property.elementType.split(separator: ".").last!)", inverse: \(inverse),
                                   read: \(read), write: \(write), related: \(readModels), setRelated: \(setModels))
                """)
            } else {
                entries.append("""
                _PersistedProperty(name: "\(property.name)", kind: .attribute, isUnique: \(property.isUnique),
                                   read: { model in (model as! \(name)).\(property.name)._storedValue },
                                   write: { model, value, _ in if let decoded = \(property.type)._fromStoredValue(value) { (model as! \(name))._\(property.name) = decoded } })
                """)
            }
        }
        // `_make`: a bare instance (no initializer runs), attributes written from the stored values.
        let makeBody = properties.filter { !$0.isRelationship }.map { property in
            "if let value = values[\"\(property.name)\"], let decoded = \(property.type)._fromStoredValue(value) { model._\(property.name) = decoded }"
        }.joined(separator: "\n        ")
        let storedDefaults = properties.map { property -> String in
            if let initializer = property.initializer { return "model._\(property.name) = \(initializer)" }
            if property.isOptional { return "model._\(property.name) = nil" }
            if property.isArray { return "model._\(property.name) = []" }
            return ""
        }.filter { !$0.isEmpty }.joined(separator: "\n        ")
        return [
            """
            public let _storage = _ModelStorage(entityName: "\(raw: name)")
            """,
            """
            nonisolated public static var _entityName: String { "\(raw: name)" }
            """,
            """
            nonisolated public static var _persistedProperties: [_PersistedProperty] { [
                \(raw: entries.joined(separator: ",\n    "))
            ] }
            """,
            """
            /// An instance without the app's initializer: the backing properties start empty and the
            /// stored values fill them (`_make`).
            internal init(_uninitialized: Void) {}
            """,
            """
            public static func _make(from values: [String: _StoredValue], in context: ModelContext) -> \(raw: name) {
                let model = \(raw: name)(_uninitialized: ())
                \(raw: storedDefaults)
                \(raw: makeBody)
                return model
            }
            """,
            """
            private let _$observationRegistrar = ObservationRegistrar()
            """,
            """
            nonisolated internal func access<Member>(keyPath: KeyPath<\(raw: name), Member>) { _$observationRegistrar.access(self, keyPath: keyPath) }
            """,
            """
            nonisolated internal func withMutation<Member, MutationResult>(keyPath: KeyPath<\(raw: name), Member>, _ mutation: () throws -> MutationResult) rethrows -> MutationResult {
                try _$observationRegistrar.withMutation(of: self, keyPath: keyPath, mutation)
            }
            """,
        ]
    }

    /// Every stored `var` becomes a computed property over a backing `_name`, observed and
    /// reporting changes to the storage; the backing stored property is added as a peer by the
    /// member-attribute route (the `@_ModelProperty` accessor macro below does the rewrite).
    public static func expansion(of node: AttributeSyntax, attachedTo declaration: some DeclGroupSyntax, providingAttributesFor member: some DeclSyntaxProtocol,
                                 in context: some MacroExpansionContext) throws -> [AttributeSyntax] {
        guard let variable = member.as(VariableDeclSyntax.self), variable.bindingSpecifier.text == "var",
              let binding = variable.bindings.first, binding.pattern.is(IdentifierPatternSyntax.self),
              !variable.modifiers.contains(where: { $0.name.text == "static" }) else { return [] }
        if let accessors = binding.accessorBlock {
            if case .getter = accessors.accessors { return [] }
            if case .accessors(let list) = accessors.accessors, list.contains(where: { $0.accessorSpecifier.text == "get" }) { return [] }
        }
        if variable.attributes.contains(where: { $0.as(AttributeSyntax.self)?.attributeName.trimmedDescription == "Transient" }) { return [] }
        return ["@_ModelProperty"]
    }

    public static func expansion(of node: AttributeSyntax, attachedTo declaration: some DeclGroupSyntax, providingExtensionsOf type: some TypeSyntaxProtocol,
                                 conformingTo protocols: [TypeSyntax], in context: some MacroExpansionContext) throws -> [ExtensionDeclSyntax] {
        guard declaration.is(ClassDeclSyntax.self) else { return [] }
        let qualified = type.trimmedDescription   // `DBModel.Country` for a class declared in an extension
        let extensionDecl: DeclSyntax = """
        extension \(raw: qualified): PersistentModel {}
        """
        return [extensionDecl.cast(ExtensionDeclSyntax.self)]
    }
}

/// The accessor macro `@Model` attaches to each stored property: the property becomes computed
/// over `_name`, reads register with the observation registrar, writes go through a mutation
/// and tell the storage. The backing `_name` is a peer.
public struct ModelPropertyMacro: AccessorMacro, PeerMacro {
    public static func expansion(of node: AttributeSyntax, providingAccessorsOf declaration: some DeclSyntaxProtocol,
                                 in context: some MacroExpansionContext) throws -> [AccessorDeclSyntax] {
        guard let variable = declaration.as(VariableDeclSyntax.self), let binding = variable.bindings.first,
              let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else { return [] }
        return [
            """
            get { access(keyPath: \\.\(raw: name)); return _\(raw: name) }
            """,
            """
            set { withMutation(keyPath: \\.\(raw: name)) { _\(raw: name) = newValue }; _storage.didChange(); modelContext?._relationshipDidChange(self, "\(raw: name)") }
            """,
        ]
    }

    public static func expansion(of node: AttributeSyntax, providingPeersOf declaration: some DeclSyntaxProtocol,
                                 in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        guard let variable = declaration.as(VariableDeclSyntax.self), let binding = variable.bindings.first,
              let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text, let type = binding.typeAnnotation?.type.trimmedDescription else { return [] }
        // The backing property: the declared initializer, nil for an optional, else an
        // implicitly unwrapped optional so `init(_uninitialized:)` can leave it for `_make` (the
        // app's own initializer always assigns it before a read).
        if let initializer = binding.initializer { return ["internal var _\(raw: name): \(raw: type) = \(raw: initializer.value.trimmedDescription)"] }
        if type.hasSuffix("?") { return ["internal var _\(raw: name): \(raw: type) = nil"] }
        return ["internal var _\(raw: name): \(raw: type)!"]
    }
}

/// `@Attribute(...)` and `@Relationship(...)`: markers `@Model` reads; nothing of their own.
public struct AttributeMacro: PeerMacro {
    public static func expansion(of node: AttributeSyntax, providingPeersOf declaration: some DeclSyntaxProtocol, in context: some MacroExpansionContext) throws -> [DeclSyntax] { [] }
}
public struct RelationshipMacro: PeerMacro {
    public static func expansion(of node: AttributeSyntax, providingPeersOf declaration: some DeclSyntaxProtocol, in context: some MacroExpansionContext) throws -> [DeclSyntax] { [] }
}
public struct TransientMacro: PeerMacro {
    public static func expansion(of node: AttributeSyntax, providingPeersOf declaration: some DeclSyntaxProtocol, in context: some MacroExpansionContext) throws -> [DeclSyntax] { [] }
}

/// `#Predicate<T> { closure }` → `Predicate<T>(closure)`: the closure runs as written against
/// each model in memory (there is no SQL to translate it into here).
public struct PredicateMacro: ExpressionMacro {
    public static func expansion(of node: some FreestandingMacroExpansionSyntax, in context: some MacroExpansionContext) throws -> ExprSyntax {
        let generics = node.genericArgumentClause?.trimmedDescription ?? ""
        guard let closure = node.trailingClosure ?? node.arguments.first?.expression.as(ClosureExprSyntax.self) else {
            context.diagnose(Diagnostic(node: Syntax(node), message: ModelMessage("'#Predicate' takes a closure")))
            return "Predicate { _ in true }"
        }
        return "Predicate\(raw: generics)(\(closure))"
    }
}

/// `@ModelActor` on an actor: the executor, the container, `init(modelContainer:)` and the
/// `ModelActor` conformance.
public struct ModelActorMacro: MemberMacro, ExtensionMacro {
    public static func expansion(of node: AttributeSyntax, providingMembersOf declaration: some DeclGroupSyntax, conformingTo protocols: [TypeSyntax],
                                 in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        guard declaration.is(ActorDeclSyntax.self) else {
            context.diagnose(Diagnostic(node: Syntax(node), message: ModelMessage("'@ModelActor' can only be applied to an actor")))
            return []
        }
        return [
            "nonisolated public let modelExecutor: any ModelExecutor",
            "nonisolated public let modelContainer: ModelContainer",
            """
            public init(modelContainer: ModelContainer) {
                self.modelExecutor = DefaultSerialModelExecutor(modelContext: ModelContext(modelContainer))
                self.modelContainer = modelContainer
            }
            """,
        ]
    }

    public static func expansion(of node: AttributeSyntax, attachedTo declaration: some DeclGroupSyntax, providingExtensionsOf type: some TypeSyntaxProtocol,
                                 conformingTo protocols: [TypeSyntax], in context: some MacroExpansionContext) throws -> [ExtensionDeclSyntax] {
        guard let actorDecl = declaration.as(ActorDeclSyntax.self) else { return [] }
        let decl: DeclSyntax = "extension \(raw: actorDecl.name.text): ModelActor {}"
        return [decl.cast(ExtensionDeclSyntax.self)]
    }
}

struct ModelMessage: DiagnosticMessage {
    let message: String
    init(_ message: String) { self.message = message }
    var diagnosticID: MessageID { MessageID(domain: "SwiftDataMacros", id: "model") }
    var severity: DiagnosticSeverity { .error }
}

/// `@Query var items: [Item]` → a backing `_items: Query<Item, [Item]>` made with the
/// attribute's arguments (the element type read from the declared `[Element]`), and accessors
/// over it — the element type is spelled out, which a property-wrapper application could not
/// infer. `$items` is not provided (Apple's isn't either).
public struct QueryMacro: AccessorMacro, PeerMacro {
    private static func parts(_ declaration: some DeclSyntaxProtocol, in context: some MacroExpansionContext) -> (name: String, element: String, result: String)? {
        guard let variable = declaration.as(VariableDeclSyntax.self), let binding = variable.bindings.first,
              let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text, let type = binding.typeAnnotation?.type else {
            context.diagnose(Diagnostic(node: Syntax(declaration), message: ModelMessage("'@Query' needs a 'var' with an explicit array type")))
            return nil
        }
        if let array = type.as(ArrayTypeSyntax.self) { return (name, array.element.trimmedDescription, type.trimmedDescription) }
        if let generic = type.as(IdentifierTypeSyntax.self), generic.name.text == "Array", let element = generic.genericArgumentClause?.arguments.first?.argument.trimmedDescription {
            return (name, element, type.trimmedDescription)
        }
        context.diagnose(Diagnostic(node: Syntax(type), message: ModelMessage("'@Query' needs an array of a model type")))
        return nil
    }

    public static func expansion(of node: AttributeSyntax, providingAccessorsOf declaration: some DeclSyntaxProtocol,
                                 in context: some MacroExpansionContext) throws -> [AccessorDeclSyntax] {
        guard let parts = parts(declaration, in: context) else { return [] }
        return ["get { _\(raw: parts.name).wrappedValue }"]
    }

    public static func expansion(of node: AttributeSyntax, providingPeersOf declaration: some DeclSyntaxProtocol,
                                 in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        guard let parts = parts(declaration, in: context) else { return [] }
        let arguments = node.arguments?.as(LabeledExprListSyntax.self)?.trimmedDescription ?? ""
        return ["private var _\(raw: parts.name): Query<\(raw: parts.element), \(raw: parts.result)> = Query<\(raw: parts.element), \(raw: parts.result)>(\(raw: arguments))"]
    }
}
