// The CoreDataModel build plugin: for a target whose directory holds Core Data models
// (`.xcdatamodeld` bundles, or bare `.xcdatamodel` directories), it runs CoreDataModelGen to
// write the entity classes Xcode would generate and the model's description, so
// `NSPersistentContainer(name:)` finds the model by name. The models should be excluded from
// the target's sources (`exclude: ["Model.xcdatamodeld"]`); the plugin reads them anyway.
import Foundation
import PackagePlugin

@main
struct CoreDataModel: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        guard let target = target as? SourceModuleTarget else { return [] }
        let models = Self.models(in: target.directoryURL)
        guard !models.isEmpty else { return [] }
        let output = context.pluginWorkDirectoryURL.appending(path: "CoreDataModel.swift")
        var inputs: [URL] = []
        for model in models { inputs += Self.files(in: model) }
        return [
            .buildCommand(
                displayName: "Generating Core Data classes for \(target.name)",
                executable: try context.tool(named: "CoreDataModelGen").url,
                arguments: [output.path, target.moduleName] + models.map(\.path),
                inputFiles: inputs,
                outputFiles: [output]
            ),
        ]
    }

    /// The models under the directory, in a stable order (a bundle's versions are its own).
    static func models(in directory: URL) -> [URL] {
        let manager = FileManager.default
        guard let enumerator = manager.enumerator(at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return [] }
        var found: [URL] = []
        for case let url as URL in enumerator {
            switch url.pathExtension {
            case "xcdatamodeld":
                found.append(url)
                enumerator.skipDescendants()
            case "xcdatamodel":
                found.append(url)
                enumerator.skipDescendants()
            case "build", "xcodeproj", "xcassets":
                enumerator.skipDescendants()
            default:
                continue
            }
        }
        return found.sorted { $0.path < $1.path }
    }

    /// The files a model is read from (so editing one regenerates the code).
    static func files(in model: URL) -> [URL] {
        let manager = FileManager.default
        guard let enumerator = manager.enumerator(at: model, includingPropertiesForKeys: nil) else { return [] }
        var files: [URL] = []
        for case let url as URL in enumerator where url.lastPathComponent == "contents" || url.lastPathComponent == ".xccurrentversion" {
            files.append(url)
        }
        return files
    }
}
