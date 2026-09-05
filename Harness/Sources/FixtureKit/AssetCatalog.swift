// Fixture asset catalog for real SwiftUI. Without Xcode there is no `actool`, so the fixtures'
// `Assets.xcassets` cannot be compiled into the `.car` file SwiftUI's named-image lookup needs
// (decision 0011: `Image("name")` never resolved loose files, registered `NSImage` names or a
// `Bundle(path:)` in a CLI process). These initialisers shadow SwiftUI's `Image(_:bundle:)` and
// `Color(_:bundle:)` for fixture sources (an overload without the defaulted parameter wins) and
// resolve the name from the catalog on disk the way the runtime does: the mac idiom over
// universal, the light appearance, the 2× scale the goldens are rendered at, template intent
// from the set's properties.
#if targetEnvironment(macCatalyst)
import UIKit
#else
import AppKit
#endif
import SwiftUI

public enum FixtureAssets {
    struct ImageVariant {
        let url: URL
        let scale: CGFloat
        let idiom: String
        let appearance: String
    }

    struct ImageSet {
        var variants: [ImageVariant] = []
        var template = false
    }

    struct ColorVariant {
        let idiom: String
        let appearance: String
        let colorSpace: String
        let components: [CGFloat]   // r g b a
    }

    static let root: URL = {
        var url = URL(fileURLWithPath: #filePath)
        while url.lastPathComponent != "Harness" { url.deleteLastPathComponent() }
        url.deleteLastPathComponent()
        return url.appendingPathComponent("Fixtures/Assets.xcassets")
    }()

    nonisolated(unsafe) static var images: [String: ImageSet] = [:]
    nonisolated(unsafe) static var colors: [String: [ColorVariant]] = [:]
    nonisolated(unsafe) private static var loaded = false

    private static func contents(_ directory: URL) -> [String: Any] {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("Contents.json")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return json
    }

    private static func appearance(_ entry: [String: Any]) -> String {
        for item in entry["appearances"] as? [[String: Any]] ?? [] where item["appearance"] as? String == "luminosity" {
            return item["value"] as? String ?? "any"
        }
        return "any"
    }

    private static func load() {
        guard !loaded else { return }
        loaded = true
        walk(root, prefix: "")
    }

    private static func walk(_ directory: URL, prefix: String) {
        let children = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let name = prefix + child.deletingPathExtension().lastPathComponent
            switch child.pathExtension {
            case "imageset":
                let doc = contents(child)
                var set = ImageSet()
                for entry in doc["images"] as? [[String: Any]] ?? [] {
                    guard let filename = entry["filename"] as? String else { continue }
                    let scaleText = (entry["scale"] as? String ?? "1x").dropLast()
                    set.variants.append(ImageVariant(url: child.appendingPathComponent(filename), scale: CGFloat(Double(scaleText) ?? 1),
                                                     idiom: entry["idiom"] as? String ?? "universal", appearance: appearance(entry)))
                }
                let properties = doc["properties"] as? [String: Any] ?? [:]
                set.template = properties["template-rendering-intent"] as? String == "template"
                images[name] = set
            case "colorset":
                var variants: [ColorVariant] = []
                for entry in contents(child)["colors"] as? [[String: Any]] ?? [] {
                    guard let color = entry["color"] as? [String: Any], let components = color["components"] as? [String: Any] else { continue }
                    func component(_ key: String, default value: CGFloat) -> CGFloat {
                        guard let text = components[key].map({ "\($0)" }) else { return value }
                        if text.lowercased().hasPrefix("0x") { return CGFloat(Int(text.dropFirst(2), radix: 16) ?? 0) / 255 }
                        if text.contains(".") { return CGFloat(Double(text) ?? 0) }
                        return CGFloat(Double(text) ?? 0) / 255
                    }
                    variants.append(ColorVariant(idiom: entry["idiom"] as? String ?? "universal", appearance: appearance(entry),
                                                 colorSpace: color["color-space"] as? String ?? "srgb",
                                                 components: [component("red", default: 0), component("green", default: 0),
                                                              component("blue", default: 0), component("alpha", default: 1)]))
                }
                colors[name] = variants
            case "":
                let namespace = (contents(child)["properties"] as? [String: Any])?["provides-namespace"] as? Bool ?? false
                walk(child, prefix: namespace ? name + "/" : prefix)
            default:
                break
            }
        }
    }

    /// The variant macOS would use in the light appearance at the given scale: mac idiom before
    /// universal, light or any appearance, the exact scale or else the largest one.
    /// The appearance variants are selected for: GoldenGen sets it from the fixture's colour scheme.
    public static var appearance = "light"

    private static func select<T>(_ variants: [T], idiom: (T) -> String, appearance: (T) -> String, scale: (T) -> CGFloat, wanted: CGFloat) -> T? {
        let byIdiom = variants.filter { idiom($0) == "mac" }.isEmpty ? variants.filter { idiom($0) == "universal" } : variants.filter { idiom($0) == "mac" }
        let wantedAppearance = Self.appearance
        let byAppearance = byIdiom.filter { appearance($0) == wantedAppearance }.isEmpty ? byIdiom.filter { appearance($0) == "any" } : byIdiom.filter { appearance($0) == wantedAppearance }
        return byAppearance.first { scale($0) == wanted } ?? byAppearance.max { scale($0) < scale($1) }
    }

    static func image(named name: String) -> Image {
        load()
        guard let set = images[name],
              let variant = select(set.variants, idiom: \.idiom, appearance: \.appearance, scale: \.scale, wanted: 2),
              let source = CGImageSourceCreateWithURL(variant.url as CFURL, nil),
              let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let cgImage = withAlpha(decoded)
        else {
            FileHandle.standardError.write("FixtureKit: no image named \(name) in Fixtures/Assets.xcassets\n".data(using: .utf8)!)
            #if targetEnvironment(macCatalyst)
            return Image(uiImage: UIImage())
            #else
            return Image(nsImage: NSImage())   // SwiftUI lays a missing named image out at 0 × 0
            #endif
        }
        let image = Image(decorative: cgImage, scale: variant.scale)
        return set.template ? image.renderingMode(.template) : image
    }

    /// SwiftUI draws nothing for a `CGImage` without an alpha channel (a JPEG decodes to
    /// `noneSkipLast`); redraw those into a premultiplied sRGB bitmap. Images with alpha are left
    /// untouched so their pixels reach SwiftUI as decoded.
    private static func withAlpha(_ image: CGImage) -> CGImage? {
        switch image.alphaInfo {
        case .none, .noneSkipLast, .noneSkipFirst:
            guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return nil }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return context.makeImage()
        default:
            return image
        }
    }

    static func color(named name: String) -> Color {
        load()
        guard let variants = colors[name],
              let variant = select(variants, idiom: \.idiom, appearance: \.appearance, scale: { _ in 1 }, wanted: 1)
        else {
            FileHandle.standardError.write("FixtureKit: no colour named \(name) in Fixtures/Assets.xcassets\n".data(using: .utf8)!)
            return .clear
        }
        let c = variant.components
        let space: Color.RGBColorSpace = variant.colorSpace == "display-p3" ? .displayP3 : variant.colorSpace == "extended-srgb" ? .sRGBLinear : .sRGB
        return Color(space, red: c[0], green: c[1], blue: c[2], opacity: c[3])
    }
}

extension Image {
    /// A named image from the fixtures' asset catalog (see the file comment).
    public init(_ name: String) {
        self = FixtureAssets.image(named: name)
    }
}

extension Color {
    /// A named colour from the fixtures' asset catalog (see the file comment).
    public init(_ name: String) {
        self = FixtureAssets.color(named: name)
    }
}

extension Label where Title == Text, Icon == Image {
    /// A label whose icon comes from the fixtures' asset catalog: SwiftUI's own `Label(_:image:)`
    /// resolves the name through the bundle (0 × 0 without a compiled catalog), so the shim
    /// builds the `Image` through the shadowed initialiser above.
    public init(_ title: String, image name: String) {
        self.init(title: { Text(title) }, icon: { Image(name) })
    }
}
