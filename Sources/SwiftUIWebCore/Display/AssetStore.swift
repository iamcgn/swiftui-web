// The asset store the environment carries and the colour-scheme environment (the catalog
// types are in WebGraphics/Display/AssetCatalog.swift).

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
