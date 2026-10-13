import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct SwiftDataMacrosPlugin: CompilerPlugin {
    let providingMacros: [any Macro.Type] = [ModelMacro.self, ModelPropertyMacro.self, AttributeMacro.self, RelationshipMacro.self, TransientMacro.self, PredicateMacro.self, ModelActorMacro.self, QueryMacro.self]
}
