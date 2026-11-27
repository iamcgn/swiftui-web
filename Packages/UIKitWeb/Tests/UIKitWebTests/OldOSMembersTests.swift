// UIKit members OldOS calls: a bundled font's family and PostScript names, a colour's grey
// level, the spell checker, a text input's selection rectangles, resizable images and the
// layer properties a 3D flip sets.
import Testing
import UIKit
@testable import UIKitWebCore

@Suite @MainActor struct OldOSMembersTests {
    @Test func bundledFontNames() {
        UIKitScene.shared.assetCatalog = AssetCatalog(fonts: ["Abel-Regular": FontResource(postScriptName: "Abel-Regular", family: "Abel", file: "Fonts/Abel-Regular.ttf",
                                                                                           unitsPerEm: 1000, ascender: 979.5, descender: -294.9, lineGap: 0, capHeight: 700.2)])
        let abel = UIFont(name: "Abel", size: 13)
        #expect(abel?.familyName == "Abel" && abel?.fontName == "Abel-Regular")
        UIKitScene.shared.assetCatalog = .empty
        #expect(UIFont(name: "Courier", size: 12)?.familyName == "Courier" && UIFont(name: "Courier", size: 12)?.fontName == "Courier")
        #expect(UIFont.systemFont(ofSize: 12).familyName == ".AppleSystemUIFont")
    }

    @Test func greyLevel() {
        var white: CGFloat = -1, alpha: CGFloat = -1
        #expect(UIColor(red: 1, green: 1, blue: 1, alpha: 0.5).getWhite(&white, alpha: &alpha))
        #expect(abs(white - 1) < 0.0001 && alpha == 0.5)
        #expect(UIColor.black.getWhite(&white, alpha: nil) && white == 0)
    }

    @Test func spellCheckerFindsNothing() {
        let checker = UITextChecker()
        let range = checker.rangeOfMisspelledWord(in: "helo wrld", range: NSRange(location: 0, length: 9), startingAt: 0, wrap: false, language: "en_US")
        #expect(range.location == NSNotFound)
        #expect(checker.guesses(forWordRange: NSRange(location: 0, length: 4), in: "helo", language: "en_US") == [])
        UITextChecker.learnWord("OldOS")
        #expect(UITextChecker.hasLearnedWord("OldOS"))
        UITextChecker.unlearnWord("OldOS")
        #expect(!UITextChecker.hasLearnedWord("OldOS"))
    }

    @Test func resizableImagesAndFlipLayers() {
        let image = UIImage(drawing: UIImageDrawing(commands: [], size: CGSize(width: 10, height: 4), scale: 2))
        #expect(image.resizableImage(withCapInsets: UIEdgeInsets(top: 0, left: 4, bottom: 0, right: 4), resizingMode: .stretch) === image)
        let layer = CALayer()
        #expect(layer.isDoubleSided)
        layer.isDoubleSided = false
        var perspective = CATransform3DIdentity
        perspective.m34 = -1 / 500
        layer.sublayerTransform = perspective
        #expect(!layer.isDoubleSided && layer.sublayerTransform.m34 == -1 / 500)
        // A new screen reads as the main screen does now, whatever scale the host gave it.
        let screen = UIScreen()
        #expect(screen.scale == UIScreen.main.scale && screen.bounds == UIScreen.main.bounds && screen !== UIScreen.main)
    }
}
