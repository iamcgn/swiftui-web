// The IntentDefinitions build plugin: for a target whose directory holds intent definition
// files (`.intentdefinition`, often in a `Base.lproj` folder), it runs IntentDefinitionsGen to
// write the intent, response, handling protocol, custom type and enum declarations Xcode would
// generate. The definitions should be excluded from the target's sources; the plugin reads
// them anyway.
import Foundation
import PackagePlugin

@main
struct IntentDefinitions: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        guard let target = target as? SourceModuleTarget else { return [] }
        let definitions = Self.definitions(in: target.directoryURL)
        guard !definitions.isEmpty else { return [] }
        let output = context.pluginWorkDirectoryURL.appending(path: "IntentDefinitions.swift")
        return [
            .buildCommand(
                displayName: "Generating intent classes for \(target.name)",
                executable: try context.tool(named: "IntentDefinitionsGen").url,
                arguments: [output.path] + definitions.map(\.path),
                inputFiles: definitions,
                outputFiles: [output]
            ),
        ]
    }

    /// The definition files under the directory, in a stable order.
    static func definitions(in directory: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return [] }
        var found: [URL] = []
        for case let url as URL in enumerator {
            switch url.pathExtension {
            case "intentdefinition": found.append(url)
            case "build", "xcodeproj", "xcassets", "xcdatamodeld": enumerator.skipDescendants()
            default: continue
            }
        }
        return found.sorted { $0.path < $1.path }
    }
}
