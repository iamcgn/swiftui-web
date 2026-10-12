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
        return ["""
        enum \(enumName): _PreviewRegistration {
            @MainActor static var preview: _Preview {
                _Preview(name: \(name), traits: [\(raw: traitList)], file: \(raw: fileLiteral), line: \(raw: lineLiteral), body: \(body))
            }
        }
        """]
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
    let providingMacros: [any Macro.Type] = [PreviewMacro.self, EntryMacro.self]
}
