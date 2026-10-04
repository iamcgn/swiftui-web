// The runtime's view of an asset catalog: what `scripts/assets.py` extracts from `*.xcassets`
// (decision 0011). Hosts fill it (the canvas host from `window.__swiftuiwebAssets`, the headless
// renderer from the manifest JSON); nodes select variants through it.

/// One file of an image set.
public struct ImageVariant: Hashable, Sendable {
    /// Path relative to the manifest's base (the copied catalog layout).
    public var file: String
    public var scale: CGFloat
    public var pixelWidth: Int
    public var pixelHeight: Int
    /// `universal`, `mac`, `iphone`, …
    public var idiom: String
    /// `any`, `light` or `dark`.
    public var appearance: String

    public init(file: String, scale: CGFloat, pixelWidth: Int, pixelHeight: Int, idiom: String = "universal", appearance: String = "any") {
        self.file = file
        self.scale = scale
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.idiom = idiom
        self.appearance = appearance
    }

    public var pointSize: CGSize { CGSize(width: CGFloat(pixelWidth) / scale, height: CGFloat(pixelHeight) / scale) }
}

/// An image set: its variants and whether the catalog marks it as a template.
public struct ImageResource: Hashable, Sendable {
    public var name: String
    public var isTemplate: Bool
    public var variants: [ImageVariant]

    public init(name: String, isTemplate: Bool = false, variants: [ImageVariant]) {
        self.name = name
        self.isTemplate = isTemplate
        self.variants = variants
    }

    /// The variants for a platform and colour scheme: the platform's idiom before `universal`,
    /// the scheme's appearance before `any`.
    public func candidates(scheme: ColorScheme, idiom platformIdiom: String) -> [ImageVariant] {
        let native = variants.filter { $0.idiom == platformIdiom }
        let byIdiom = native.isEmpty ? variants.filter { $0.idiom == "universal" } : native
        let wanted = scheme == .dark ? "dark" : "light"
        let matching = byIdiom.filter { $0.appearance == wanted }
        return matching.isEmpty ? byIdiom.filter { $0.appearance == "any" } : matching
    }

    /// The variant to draw at `scale`: the exact scale, else the largest available.
    public func variant(scale: CGFloat, scheme: ColorScheme, idiom: String) -> ImageVariant? {
        let candidates = candidates(scheme: scheme, idiom: idiom)
        return candidates.first { $0.scale == scale } ?? candidates.max { $0.scale < $1.scale }
    }

    /// The size the image lays out at: pixels ÷ scale of the largest-scale variant.
    public func pointSize(scheme: ColorScheme, idiom: String) -> CGSize? {
        candidates(scheme: scheme, idiom: idiom).max { $0.scale < $1.scale }?.pointSize
    }
}

/// One entry of a colour set.
public struct ColorVariant: Hashable, Sendable {
    public var idiom: String
    public var appearance: String
    public var colorSpace: String
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(idiom: String = "universal", appearance: String = "any", colorSpace: String = "srgb",
                red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.idiom = idiom
        self.appearance = appearance
        self.colorSpace = colorSpace
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public var rgba: RGBA { RGBA(red: red, green: green, blue: blue, alpha: alpha) }
}

/// A font file the app bundles (`Font.custom`): its names, where its file sits under the asset
/// base, and the vertical metrics `scripts/assets.py` read from its tables, in font units.
public struct FontResource: Hashable, Sendable {
    public var postScriptName: String
    public var family: String
    public var file: String
    public var unitsPerEm: Double
    public var ascender: Double
    public var descender: Double
    public var lineGap: Double
    public var capHeight: Double
    public var xHeight: Double
    public var underlinePosition: Double
    public var underlineThickness: Double

    public init(postScriptName: String, family: String, file: String, unitsPerEm: Double, ascender: Double, descender: Double, lineGap: Double,
                capHeight: Double = 0, xHeight: Double = 0, underlinePosition: Double = 0, underlineThickness: Double = 0) {
        self.postScriptName = postScriptName
        self.family = family
        self.file = file
        self.unitsPerEm = unitsPerEm
        self.ascender = ascender
        self.descender = descender
        self.lineGap = lineGap
        self.capHeight = capHeight
        self.xHeight = xHeight
        self.underlinePosition = underlinePosition
        self.underlineThickness = underlineThickness
    }
}

/// Every image and colour set of an app's catalogs, keyed by name (`Folder/name` for
/// namespaced folders), and the font files it bundles, keyed by PostScript name.
public struct AssetCatalog: Sendable, Equatable {
    public var images: [String: ImageResource]
    public var colors: [String: [ColorVariant]]
    public var fonts: [String: FontResource]

    public init(images: [String: ImageResource] = [:], colors: [String: [ColorVariant]] = [:], fonts: [String: FontResource] = [:]) {
        self.images = images
        self.colors = colors
        self.fonts = fonts
    }

    /// The font named by `Font.custom` (its PostScript name, full name or family).
    public func font(named name: String) -> FontResource? {
        fonts[name] ?? fonts.values.first { $0.family == name }
    }

    public static let empty = AssetCatalog()

    public func image(named name: String) -> ImageResource? { images[name] }

    /// The colour set's value for a colour scheme, with the same idiom and appearance rules as
    /// images; `nil` when the name is unknown.
    public func color(named name: String, scheme: ColorScheme, idiom: String = "mac") -> RGBA? {
        guard let variants = colors[name] else { return nil }
        let native = variants.filter { $0.idiom == idiom }
        let byIdiom = native.isEmpty ? variants.filter { $0.idiom == "universal" } : native
        let wanted = scheme == .dark ? "dark" : "light"
        let chosen = byIdiom.first { $0.appearance == wanted } ?? byIdiom.first { $0.appearance == "any" } ?? byIdiom.first
        return chosen?.rgba
    }
}

/// The possible color schemes, corresponding to the light and dark appearances.
public enum ColorScheme: Hashable, CaseIterable, Sendable {
    case light
    case dark
}
