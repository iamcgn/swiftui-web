// The `#Preview` macro plugin: a preview block expands to an enum with a compiler-unique name
// (a declaration macro at global scope may introduce no other kind of name, nor an extension)
// conforming to `_PreviewRegistration`, whose `preview` keeps the name, the traits and the
// body. Natively the registrations are found by scanning the binary's protocol conformance
// records (`_PreviewRegistry.all`); the wasm gallery lists them from a generated index
// (Docs/elements/Preview.md).
import SwiftCompilerPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

public struct PreviewMacro: DeclarationMacro {
    public static func expansion(of node: some FreestandingMacroExpansionSyntax, in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        var name: ExprSyntax = "nil"
        var traits: [ExprSyntax] = []
        var body: ExprSyntax?
        var sawTraits = false
        for argument in node.arguments {
            switch argument.label?.text {
            case nil where !sawTraits && argument.expression.is(StringLiteralExprSyntax.self): name = argument.expression
            case "traits": sawTraits = true; traits.append(argument.expression)
            case nil where sawTraits: traits.append(argument.expression)
            case "body": body = argument.expression
            default: break
            }
        }
        if let trailing = node.trailingClosure { body = ExprSyntax(trailing) }
        guard let body else {
            context.diagnose(Diagnostic(node: Syntax(node), message: PreviewMessage("#Preview needs a body")))
            return []
        }
        let location = context.location(of: node, at: .afterLeadingTrivia, filePathMode: .fileID)
        let fileLiteral = location?.file.description ?? "\"Unknown\""
        let lineLiteral = location?.line.description ?? "0"
        let enumName = context.makeUniqueName("preview")
        let traitList = traits.map(\.description).joined(separator: ", ")
        if let closure = body.as(ClosureExprSyntax.self), let host = previewableHost(closure) {
            return ["""
            enum \(enumName): _PreviewRegistration {
                \(raw: host)
                @MainActor static var preview: _Preview {
                    _Preview(name: \(name), traits: [\(raw: traitList)], file: \(raw: fileLiteral), line: \(raw: lineLiteral), body: { _PreviewHost() })
                }
            }
            """]
        }
        return ["""
        enum \(enumName): _PreviewRegistration {
            @MainActor static var preview: _Preview {
                _Preview(name: \(name), traits: [\(raw: traitList)], file: \(raw: fileLiteral), line: \(raw: lineLiteral), body: \(body))
            }
        }
        """]
    }

    /// A body that declares `@Previewable` variables becomes a view of its own, as Apple's
    /// macro makes it: those variables are its stored properties (so `@State` keeps its value
    /// across updates) and the rest of the statements its `body`. Nil when there are none.
    static func previewableHost(_ closure: ClosureExprSyntax) -> String? {
        var properties: [String] = []
        var statements: [String] = []
        for item in closure.statements {
            if let variable = item.item.as(VariableDeclSyntax.self), variable.attributes.contains(where: isPreviewable) {
                var stripped = variable
                stripped.attributes = variable.attributes.filter { !isPreviewable($0) }
                properties.append(stripped.trimmedDescription)
            } else {
                statements.append(item.trimmedDescription)
            }
        }
        guard !properties.isEmpty else { return nil }
        return """
        struct _PreviewHost: View {
            \(properties.joined(separator: "\n    "))
            var body: some View {
                \(statements.joined(separator: "\n        "))
            }
        }
        """
    }

    private static func isPreviewable(_ element: AttributeListSyntax.Element) -> Bool {
        guard case .attribute(let attribute) = element else { return false }
        let name = attribute.attributeName.trimmedDescription
        return name == "Previewable" || name == "SwiftUI.Previewable"
    }
}

/// `@Previewable` marks a variable in a `#Preview` body as the preview's own state; the
/// `#Preview` expansion moves it into a view (PreviewMacro.previewableHost), so the attribute
/// itself adds nothing.
public struct PreviewableMacro: PeerMacro {
    public static func expansion(of node: AttributeSyntax, providingPeersOf declaration: some DeclSyntaxProtocol, in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        []
    }
}

struct PreviewMessage: DiagnosticMessage {
    let message: String
    init(_ message: String) { self.message = message }
    var diagnosticID: MessageID { MessageID(domain: "SwiftUIWebMacros", id: "preview") }
    var severity: DiagnosticSeverity { .error }
}

@main
struct SwiftUIWebMacrosPlugin: CompilerPlugin {
    let providingMacros: [any Macro.Type] = [PreviewMacro.self, PreviewableMacro.self, EntryMacro.self]
}
