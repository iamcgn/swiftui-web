// The generated asset symbols' types: `ImageResource` and `ColorResource` name one image or
// colour set of an asset catalog in a bundle. Xcode writes a static member for each set
// (`ImageResource.floor1`, `ColorResource.accent`); the `AssetSymbols` build plugin does the
// same from an app's `.xcassets` here, and `Image(_:)`, `Color(_:)`, `UIImage(resource:)` and
// `UIColor(resource:)` look the set up by its catalog name.

#if os(WASI)
import WebFoundation   // never full Foundation on wasm: it links ICU (decisions 0006, 0017)
#else
import Foundation
#endif

/// An image set of an asset catalog, by name and bundle.
public struct ImageResource: Hashable, @unchecked Sendable {
    /// The set's name in the catalog, with any namespace folders (`Fountain/Terracotta`).
    public let _name: String
    public let _bundle: Bundle

    public init(name: String, bundle: Bundle) {
        _name = name
        _bundle = bundle
    }

    public static func == (lhs: ImageResource, rhs: ImageResource) -> Bool {
        lhs._name == rhs._name && lhs._bundle === rhs._bundle
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(_name)
        hasher.combine(ObjectIdentifier(_bundle))
    }
}

/// A colour set of an asset catalog, by name and bundle.
public struct ColorResource: Hashable, @unchecked Sendable {
    /// The set's name in the catalog, with any namespace folders.
    public let _name: String
    public let _bundle: Bundle

    public init(name: String, bundle: Bundle) {
        _name = name
        _bundle = bundle
    }

    public static func == (lhs: ColorResource, rhs: ColorResource) -> Bool {
        lhs._name == rhs._name && lhs._bundle === rhs._bundle
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(_name)
        hasher.combine(ObjectIdentifier(_bundle))
    }
}
