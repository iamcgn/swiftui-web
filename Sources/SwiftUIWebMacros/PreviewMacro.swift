// The `#Preview` macro plugin: previews are an editor feature, so the macro expands to nothing
// and preview blocks in app sources compile without effect (Docs/elements/Preview.md).
import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxMacros

public struct PreviewMacro: DeclarationMacro {
    public static func expansion(of node: some FreestandingMacroExpansionSyntax, in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        []
    }
}

@main
struct SwiftUIWebMacrosPlugin: CompilerPlugin {
    let providingMacros: [any Macro.Type] = [PreviewMacro.self]
}
