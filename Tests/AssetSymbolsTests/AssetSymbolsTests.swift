// The symbols the AssetSymbols plugin writes for Media.xcassets, as Xcode names them: lower camel
// case, the kind's suffix dropped (`AccentColor` is `accent`, with `accentColor` kept too), a
// leading digit behind an underscore, keywords escaped, namespace folders as nested enums and
// other folders flattened, symbol sets as images, and no symbols for app icons or data sets.
//
// What the tests prove: each symbol names its set's catalog name in the main bundle, and
// `Image`, `Color`, `UIImage` and `UIColor` take them. Not proven here: drawing the sets (the
// asset catalog tests in CoreRuntimeTests do that by name).
import Testing
import SwiftUI
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif

@Suite struct AssetSymbolsTests {
    @Test func imageSymbolsNameTheirSets() {
        #expect(ImageResource.building1 == ImageResource(name: "Building 1", bundle: .main))
        #expect(ImageResource._3DBadge._name == "3D Badge")
        #expect(ImageResource.urlIcon._name == "URLIcon")
        #expect(ImageResource.`default`._name == "default")
        #expect(ImageResource.fountainFill._name == "fountain.fill")
    }

    @Test func namespaceFoldersNestAndOtherFoldersFlatten() {
        #expect(ImageResource.Fountain.terracotta._name == "Fountain/Terracotta")
        #expect(ImageResource.Fountain.stone._name == "Fountain/Stone")
        #expect(ImageResource.Fountain.Basin.rim._name == "Fountain/Basin/Rim")
        #expect(ImageResource.stone._name == "Stone")
        #expect(ImageResource.stoneImage._name == "Stone Image")
        #expect(ImageResource.stone != ImageResource.Fountain.stone)
    }

    @Test func colorSymbolsDropTheSuffix() {
        #expect(ColorResource.accent._name == "AccentColor")
        #expect(ColorResource.accentColor == ColorResource.accent)
        #expect(ColorResource.premiumBirdFood._name == "Premium Bird Food")
        #expect(ColorResource.Fountain.water._name == "Fountain/Water Color")
    }

    @MainActor
    @Test func viewsAndUIKitTakeTheSymbols() {
        let image = Image(.building1)
        let namespaced = Image(ImageResource.Fountain.terracotta)
        let color = Color(.premiumBirdFood)
        #expect(image == Image("Building 1"))
        #expect(namespaced == Image("Fountain/Terracotta"))
        #expect(color == Color("Premium Bird Food"))
        _ = UIImage(resource: .urlIcon)
        _ = UIColor(resource: .accent)
    }
}
