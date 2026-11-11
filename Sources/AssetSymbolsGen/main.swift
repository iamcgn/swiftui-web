// AssetSymbolsGen: the AssetSymbols build plugin's tool. It reads a target's asset catalogs
// (`.xcassets`) and writes the symbols Xcode generates for them: a static `ImageResource` for
// each image and symbol set and a static `ColorResource` for each colour set, named in lower
// camel case (`Building 1` is `building1`, `AccentColor` is `accent`). A folder that provides a
// namespace becomes a nested enum (`ImageResource.Fountain.terracotta` for the catalog name
// `Fountain/Terracotta`); other folders only group.
//
//   AssetSymbolsGen <output.swift> <catalog.xcassets>...

#if os(WASI)
print("AssetSymbolsGen runs on the build host")
#else
import Foundation

/// The symbols of one scope: the catalog root or a namespace folder.
final class Scope {
    var images: [(identifier: String, name: String)] = []
    var colors: [(identifier: String, name: String)] = []
    var namespaces: [(identifier: String, scope: Scope)] = []

    var hasImages: Bool { !images.isEmpty || namespaces.contains { $0.scope.hasImages } }
    var hasColors: Bool { !colors.isEmpty || namespaces.contains { $0.scope.hasColors } }

    func namespace(_ identifier: String) -> Scope {
        if let existing = namespaces.first(where: { $0.identifier == identifier }) { return existing.scope }
        let scope = Scope()
        namespaces.append((identifier, scope))
        return scope
    }
}

let keywords: Set<String> = [
    "associatedtype", "class", "deinit", "enum", "extension", "fileprivate", "func", "import", "init",
    "inout", "internal", "let", "open", "operator", "private", "precedencegroup", "protocol", "public",
    "rethrows", "static", "struct", "subscript", "typealias", "var", "break", "case", "catch", "continue",
    "default", "defer", "do", "else", "fallthrough", "for", "guard", "if", "in", "repeat", "return",
    "throw", "switch", "where", "while", "Any", "as", "await", "false", "is", "nil", "self", "Self",
    "super", "throws", "true", "try", "Type", "Protocol",
]

/// The folder extensions that are asset kinds of their own, with no generated symbol. A folder
/// with any other extension is a group whose name has a dot in it.
let assetKinds: Set<String> = [
    "appiconset", "arimageset", "arresourcegroup", "brandassets", "complicationset", "cubetextureset",
    "dataset", "gcdashboardimage", "gcleaderboard", "gcleaderboardset", "iconset", "imagestack",
    "imagestacklayer", "launchimage", "mipmapset", "solidimagestack", "solidimagestacklayer",
    "spriteatlas", "sticker", "stickerpack", "stickersequence", "textureset",
]

/// The words of a catalog name: runs of letters and digits.
func words(_ name: String) -> [String] {
    var result: [String] = []
    var current = ""
    for character in name {
        if character.isLetter || character.isNumber {
            current.append(character)
        } else if !current.isEmpty {
            result.append(current)
            current = ""
        }
    }
    if !current.isEmpty { result.append(current) }
    return result
}

/// A word with its leading capitals lowered: `Building` → `building`, `URLIcon` → `urlIcon`,
/// `ABC` → `abc`.
func lowerLeading(_ word: String) -> String {
    let characters = Array(word)
    var run = 0
    while run < characters.count, characters[run].isUppercase { run += 1 }
    if run == 0 { return word }
    let lowered = run == characters.count || run == 1 ? run : run - 1
    return String(characters[..<lowered]).lowercased() + String(characters[lowered...])
}

func upperFirst(_ word: String) -> String {
    guard let first = word.first else { return word }
    return first.uppercased() + word.dropFirst()
}

/// The lower camel case identifier for a name (without escaping).
func camel(_ name: String) -> String {
    let parts = words(name)
    guard let first = parts.first else { return "_" }
    var identifier = lowerLeading(first) + parts.dropFirst().map(upperFirst).joined()
    if identifier.first?.isNumber == true { identifier = "_" + identifier }
    return identifier
}

func escaped(_ identifier: String) -> String {
    keywords.contains(identifier) ? "`\(identifier)`" : identifier
}

/// The identifiers for a set: the name without the kind's suffix (`AccentColor` → `accent`), as
/// Xcode names it, and the whole name too.
func identifiers(for name: String, droppingSuffix suffix: String) -> [String] {
    let full = camel(name)
    if full.hasSuffix(suffix), full.count > suffix.count {
        let stripped = String(full.dropLast(suffix.count))
        if stripped != "_", stripped.last != "_" { return [stripped, full] }
    }
    return [full]
}

func readJSON(_ url: URL) -> [String: Any] {
    guard let data = try? Data(contentsOf: url),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
    return object
}

/// Adds the sets under a catalog folder to a scope; `prefix` is the namespace path of the
/// catalog name (`Fountain/`).
func walk(_ directory: URL, prefix: String, into scope: Scope) {
    let manager = FileManager.default
    guard let children = try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return }
    for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
        guard (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
        let base = child.deletingPathExtension().lastPathComponent
        switch child.pathExtension {
        case "imageset", "symbolset":
            scope.images.append(contentsOf: identifiers(for: base, droppingSuffix: "Image").map { ($0, prefix + base) })
        case "colorset":
            scope.colors.append(contentsOf: identifiers(for: base, droppingSuffix: "Color").map { ($0, prefix + base) })
        case let kind where assetKinds.contains(kind):
            continue   // app icons, data sets, sprite atlases and the rest have no symbols
        default:
            // A folder: any other name is a group, a dot in it included (`Tiles.v2` is a group
            // named `Tiles.v2`, not a set of kind `v2`).
            let name = child.lastPathComponent
            let properties = readJSON(child.appending(path: "Contents.json"))["properties"] as? [String: Any]
            if properties?["provides-namespace"] as? Bool == true {
                walk(child, prefix: prefix + name + "/", into: scope.namespace(upperFirst(camel(name))))
            } else {
                walk(child, prefix: prefix, into: scope)
            }
        }
    }
}

func literal(_ string: String) -> String {
    var result = "\""
    for scalar in string.unicodeScalars {
        switch scalar {
        case "\"": result += "\\\""
        case "\\": result += "\\\\"
        case "\n": result += "\\n"
        default: result.unicodeScalars.append(scalar)
        }
    }
    return result + "\""
}

/// The declarations of one kind in a scope, indented.
func emit(_ scope: Scope, images: Bool, type: String, indent: String, into lines: inout [String]) {
    var used: Set<String> = []
    for namespace in scope.namespaces where images ? namespace.scope.hasImages : namespace.scope.hasColors {
        guard used.insert(namespace.identifier).inserted else { continue }
        lines.append("\(indent)enum \(escaped(namespace.identifier)) {")
        emit(namespace.scope, images: images, type: type, indent: indent + "    ", into: &lines)
        lines.append("\(indent)}")
    }
    // A set's whole name first, so `Stone` keeps `stone` when `Stone Image` would shorten to it.
    let entries = images ? scope.images : scope.colors
    func isWhole(_ entry: (identifier: String, name: String)) -> Bool {
        camel(entry.name.split(separator: "/").last.map(String.init) ?? entry.name) == entry.identifier
    }
    var owner: [String: String] = [:]
    for entry in entries.filter(isWhole) + entries.filter({ !isWhole($0) }) where !used.contains(entry.identifier) && owner[entry.identifier] == nil {
        owner[entry.identifier] = entry.name
    }
    for (identifier, name) in entries where owner[identifier] == name {
        owner[identifier] = nil
        lines.append("\(indent)static let \(escaped(identifier)) = \(type)(name: \(literal(name)), bundle: .main)")
    }
}

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: AssetSymbolsGen <output.swift> <catalog.xcassets>...\n".utf8))
    exit(2)
}
let root = Scope()
for path in arguments.dropFirst(2) {
    walk(URL(fileURLWithPath: path), prefix: "", into: root)
}

var lines = ["// Generated by AssetSymbolsGen from the target's asset catalogs. Do not edit."]
if root.hasImages || root.hasColors {
    lines += ["#if os(WASI) && canImport(WebFoundation)", "import WebFoundation", "#else", "import Foundation", "#endif", ""]
    // The types by their module's name, as Xcode writes them, so a type of the app's own with
    // the same name is not the one extended.
    for (condition, module) in [("#if canImport(WebGraphics)", "WebGraphics"), ("#else", "DeveloperToolsSupport")] {
        lines += [condition, "import \(module)"]
        if root.hasImages {
            lines += ["", "extension \(module).ImageResource {"]
            emit(root, images: true, type: "\(module).ImageResource", indent: "    ", into: &lines)
            lines += ["}", ""]
        }
        if root.hasColors {
            lines += ["", "extension \(module).ColorResource {"]
            emit(root, images: false, type: "\(module).ColorResource", indent: "    ", into: &lines)
            lines += ["}", ""]
        }
    }
    lines.append("#endif")
}
let text = lines.joined(separator: "\n") + "\n"
let output = URL(fileURLWithPath: arguments[1])
if (try? String(contentsOf: output, encoding: .utf8)) != text {
    try text.write(to: output, atomically: true, encoding: .utf8)
}
#endif
