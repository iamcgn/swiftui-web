// TipKit's macros: `#Rule` builds a rule from a parameter or an event and a closure, and
// `@Parameter` keeps a tip's static property in TipKit, adding `$name` for the rules.
import SwiftCompilerPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

/// `#Rule(Self.$isLoggedIn) { $0 == true }` → `TipKit.Tips.Rule(Self.$isLoggedIn) { $0 == true }`.
public struct RuleMacro: ExpressionMacro {
    public static func expansion(of node: some FreestandingMacroExpansionSyntax, in context: some MacroExpansionContext) throws -> ExprSyntax {
        var arguments = node.arguments.map { $0.expression.trimmedDescription }
        if let closure = node.trailingClosure { arguments.append(closure.trimmedDescription) }
        guard arguments.count == 2 else {
            context.diagnose(Diagnostic(node: Syntax(node), message: TipKitMessage("'#Rule' takes a parameter or an event and a closure")))
            return "TipKit.Tips.Rule(TipKit.Tips.Parameter(id: \"\", true)) { $0 }"
        }
        return "TipKit.Tips.Rule(\(raw: arguments[0]), \(raw: arguments[1]))"
    }
}

/// `@Parameter static var isLoggedIn: Bool = false`: reads and writes go to `$isLoggedIn`, a
/// `Tips.Parameter<Bool>` with the default `false`.
public struct ParameterMacro: AccessorMacro, PeerMacro {
    public static func expansion(of node: AttributeSyntax, providingAccessorsOf declaration: some DeclSyntaxProtocol,
                                 in context: some MacroExpansionContext) throws -> [AccessorDeclSyntax] {
        guard let name = propertyName(declaration) else { return [] }
        return [
            "get { $\(raw: name).wrappedValue }",
            "set { $\(raw: name).wrappedValue = newValue }",
        ]
    }

    public static func expansion(of node: AttributeSyntax, providingPeersOf declaration: some DeclSyntaxProtocol,
                                 in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        guard let variable = declaration.as(VariableDeclSyntax.self), let binding = variable.bindings.first,
              let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.trimmedDescription else {
            context.diagnose(Diagnostic(node: Syntax(node), message: TipKitMessage("'@Parameter' applies to a static property")))
            return []
        }
        guard let type = binding.typeAnnotation?.type.trimmedDescription else {
            context.diagnose(Diagnostic(node: Syntax(node), message: TipKitMessage("'@Parameter' needs the property's type written out")))
            return []
        }
        let initial: String
        if let value = binding.initializer?.value.trimmedDescription {
            initial = value
        } else if type.hasSuffix("?") || type.hasPrefix("Optional<") {
            initial = "nil"
        } else {
            context.diagnose(Diagnostic(node: Syntax(node), message: TipKitMessage("'@Parameter' needs a default value")))
            return []
        }
        var options = ""
        if case .argumentList(let list) = node.arguments, !list.isEmpty {
            options = ", " + list.map { $0.expression.trimmedDescription }.joined(separator: ", ")
        }
        let isStatic = variable.modifiers.contains { $0.name.tokenKind == .keyword(.static) || $0.name.tokenKind == .keyword(.class) }
        let access = variable.modifiers.first { ["public", "internal", "fileprivate", "private", "package"].contains($0.name.text) }
            .map { $0.name.text + " " } ?? ""
        let staticWord = isStatic ? "static " : ""
        return ["\(raw: access)\(raw: staticWord)let $\(raw: name): TipKit.Tips.Parameter<\(raw: type)> = TipKit.Tips.Parameter(Self.self, \"\(raw: name)\", \(raw: initial)\(raw: options))"]
    }

    private static func propertyName(_ declaration: some DeclSyntaxProtocol) -> String? {
        declaration.as(VariableDeclSyntax.self)?.bindings.first?.pattern.as(IdentifierPatternSyntax.self)?.identifier.trimmedDescription
    }
}

struct TipKitMessage: DiagnosticMessage {
    let message: String
    init(_ message: String) { self.message = message }
    var diagnosticID: MessageID { MessageID(domain: "TipKitMacros", id: message) }
    var severity: DiagnosticSeverity { .error }
}

@main
struct TipKitMacrosPlugin: CompilerPlugin {
    let providingMacros: [any Macro.Type] = [RuleMacro.self, ParameterMacro.self]
}
