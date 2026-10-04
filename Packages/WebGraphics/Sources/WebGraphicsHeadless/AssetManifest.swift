import WebGraphics
#if !os(WASI)
#if os(WASI)
import WebFoundation   // never full Foundation on wasm: it links ICU (decisions 0006, 0017)
#else
import Foundation
#endif

/// Loads the manifest `scripts/assets.py --json` writes into an `AssetCatalog` (native tests and
/// the headless renderer; the canvas host reads the same document from `window.__swiftuiwebAssets`).
extension AssetCatalog {
    private struct Document: Decodable {
        struct Variant: Decodable {
            let file: String
            let scale: Double
            let width: Int
            let height: Int
            let idiom: String?
            let appearance: String?
        }
        struct ImageSet: Decodable {
            let template: Bool?
            let variants: [Variant]
        }
        struct ColorEntry: Decodable {
            let idiom: String?
            let appearance: String?
            let colorSpace: String?
            let red: Double
            let green: Double
            let blue: Double
            let alpha: Double
        }
        struct ColorSet: Decodable {
            let variants: [ColorEntry]
        }
        struct FontEntry: Decodable {
            let file: String
            let family: String
            let postScriptName: String
            let unitsPerEm: Double
            let ascender: Double
            let descender: Double
            let lineGap: Double
            let capHeight: Double?
            let xHeight: Double?
            let underlinePosition: Double?
            let underlineThickness: Double?
        }
        let images: [String: ImageSet]
        let colors: [String: ColorSet]
        let fonts: [String: FontEntry]?
    }

    public init(manifestData data: Data) throws {
        let document = try JSONDecoder().decode(Document.self, from: data)
        var images: [String: ImageResource] = [:]
        for (name, set) in document.images {
            images[name] = ImageResource(name: name, isTemplate: set.template ?? false, variants: set.variants.map {
                ImageVariant(file: $0.file, scale: CGFloat($0.scale), pixelWidth: $0.width, pixelHeight: $0.height,
                             idiom: $0.idiom ?? "universal", appearance: $0.appearance ?? "any")
            })
        }
        var colors: [String: [ColorVariant]] = [:]
        for (name, set) in document.colors {
            colors[name] = set.variants.map {
                ColorVariant(idiom: $0.idiom ?? "universal", appearance: $0.appearance ?? "any", colorSpace: $0.colorSpace ?? "srgb",
                             red: $0.red, green: $0.green, blue: $0.blue, alpha: $0.alpha)
            }
        }
        var fonts: [String: FontResource] = [:]
        for (name, entry) in document.fonts ?? [:] {
            fonts[name] = FontResource(postScriptName: entry.postScriptName, family: entry.family, file: entry.file, unitsPerEm: entry.unitsPerEm,
                                       ascender: entry.ascender, descender: entry.descender, lineGap: entry.lineGap,
                                       capHeight: entry.capHeight ?? 0, xHeight: entry.xHeight ?? 0,
                                       underlinePosition: entry.underlinePosition ?? 0, underlineThickness: entry.underlineThickness ?? 0)
        }
        self.init(images: images, colors: colors, fonts: fonts)
    }

    public init(contentsOf url: URL) throws {
        try self.init(manifestData: Data(contentsOf: url))
    }
}
#endif
