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
    package func candidates(scheme: ColorScheme, idiom platformIdiom: String) -> [ImageVariant] {
        let native = variants.filter { $0.idiom == platformIdiom }
        let byIdiom = native.isEmpty ? variants.filter { $0.idiom == "universal" } : native
        let wanted = scheme == .dark ? "dark" : "light"
        let matching = byIdiom.filter { $0.appearance == wanted }
        return matching.isEmpty ? byIdiom.filter { $0.appearance == "any" } : matching
    }

    /// The variant to draw at `scale`: the exact scale, else the largest available.
    package func variant(scale: CGFloat, scheme: ColorScheme, idiom: String) -> ImageVariant? {
        let candidates = candidates(scheme: scheme, idiom: idiom)
        return candidates.first { $0.scale == scale } ?? candidates.max { $0.scale < $1.scale }
    }

    /// The size the image lays out at: pixels ÷ scale of the largest-scale variant.
    package func pointSize(scheme: ColorScheme, idiom: String) -> CGSize? {
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

/// Every image and colour set of an app's catalogs, keyed by name (`Folder/name` for
/// namespaced folders).
public struct AssetCatalog: Sendable, Equatable {
    public var images: [String: ImageResource]
    public var colors: [String: [ColorVariant]]

    public init(images: [String: ImageResource] = [:], colors: [String: [ColorVariant]] = [:]) {
        self.images = images
        self.colors = colors
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

/// The catalog a runtime's nodes read, shared by reference so replacing it after mount is seen
/// everywhere on the next update.
package final class _AssetStore: @unchecked Sendable {
    /// Written by the runtime on the main actor, read by nodes there too.
    nonisolated(unsafe) package var catalog: AssetCatalog

    package init(catalog: AssetCatalog = .empty) {
        self.catalog = catalog
    }

    /// For environments that no runtime created (defaults, tests).
    package static let shared = _AssetStore()
}

package struct AssetStoreKey: EnvironmentKey {
    package static let defaultValue = _AssetStore.shared
}

extension EnvironmentValues {
    package var assetCatalog: AssetCatalog {
        self[AssetStoreKey.self].catalog
    }

    /// The idiom this platform prefers in a catalog.
    package var assetIdiom: String { "mac" }
}

/// The possible color schemes, corresponding to the light and dark appearances.
public enum ColorScheme: Hashable, CaseIterable, Sendable {
    case light
    case dark
}

package struct ColorSchemeKey: EnvironmentKey {
    package static let defaultValue = ColorScheme.light
}

extension EnvironmentValues {
    /// The color scheme of this environment: system colours, control inks and asset variants
    /// follow it. The root's comes from the host (the system appearance) unless a
    /// `preferredColorScheme` in the tree overrides it.
    public var colorScheme: ColorScheme {
        get { self[ColorSchemeKey.self] }
        set { self[ColorSchemeKey.self] = newValue }
    }
}

/// `preferredColorScheme`: records the preference on the runtime, which applies it to the root
/// environment (the whole window, as on macOS).
public struct _PreferredColorSchemeModifier: Equatable {
    package let scheme: ColorScheme?
    package init(scheme: ColorScheme?) { self.scheme = scheme }
}

extension _PreferredColorSchemeModifier: ViewModifier {
    public typealias Body = Never
    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        PreferredColorSchemeNode(context)
    }
}

@MainActor
package final class PreferredColorSchemeNode<Content: View>: UnaryLayoutModifierNode<Content, _PreferredColorSchemeModifier> {
    override package init(_ context: _NodeContext<ModifiedContent<Content, _PreferredColorSchemeModifier>>) {
        super.init(context)
        runtime.preferredColorScheme = modifier.scheme
    }

    override package func update(view: ModifiedContent<Content, _PreferredColorSchemeModifier>, environment: EnvironmentValues, force: Bool) {
        super.update(view: view, environment: environment, force: force)
        runtime.preferredColorScheme = modifier.scheme
    }

    override package func unmount() {
        if runtime.preferredColorScheme == modifier.scheme { runtime.preferredColorScheme = nil }
        super.unmount()
    }
}

extension View {
    /// Sets the preferred color scheme for this presentation: the whole window follows it;
    /// `nil` returns to the system appearance.
    nonisolated public func preferredColorScheme(_ colorScheme: ColorScheme?) -> some View {
        modifier(_PreferredColorSchemeModifier(scheme: colorScheme))
    }
}
