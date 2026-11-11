// The AssetSymbols build plugin: for a target whose directory holds asset catalogs
// (`.xcassets`), it runs AssetSymbolsGen to write the symbols Xcode generates for them, so
// `Image(.logo)`, `Color(.accent)` and `ImageResource.Fountain.terracotta` compile. The
// catalogs stay the target's resources; the plugin only reads their folders and `Contents.json`.
import Foundation
import PackagePlugin

@main
struct AssetSymbols: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        guard let target = target as? SourceModuleTarget else { return [] }
        let catalogs = Self.catalogs(in: target.directoryURL)
        guard !catalogs.isEmpty else { return [] }
        let output = context.pluginWorkDirectoryURL.appending(path: "AssetSymbols.swift")
        var inputs: [URL] = []
        for catalog in catalogs { inputs += Self.contents(of: catalog) }
        return [
            .buildCommand(
                displayName: "Generating asset symbols for \(target.name)",
                executable: try context.tool(named: "AssetSymbolsGen").url,
                arguments: [output.path] + catalogs.map(\.path),
                inputFiles: inputs,
                outputFiles: [output]
            ),
        ]
    }

    /// The catalogs under the directory, in a stable order.
    static func catalogs(in directory: URL) -> [URL] {
        let manager = FileManager.default
        guard let enumerator = manager.enumerator(at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return [] }
        var found: [URL] = []
        for case let url as URL in enumerator {
            switch url.pathExtension {
            case "xcassets":
                found.append(url)
                enumerator.skipDescendants()
            case "build", "xcodeproj", "xcdatamodeld", "bundle":
                enumerator.skipDescendants()
            default:
                continue
            }
        }
        return found.sorted { $0.path < $1.path }
    }

    /// The `Contents.json` files of a catalog (so adding or renaming a set regenerates the code).
    static func contents(of catalog: URL) -> [URL] {
        let manager = FileManager.default
        guard let enumerator = manager.enumerator(at: catalog, includingPropertiesForKeys: nil) else { return [] }
        var files: [URL] = []
        for case let url as URL in enumerator where url.lastPathComponent == "Contents.json" {
            files.append(url)
        }
        return files
    }
}
