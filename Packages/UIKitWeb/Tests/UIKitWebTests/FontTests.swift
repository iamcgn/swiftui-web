// Fonts (uk-fonts): italic, monospaced and bundled fonts, text styles at other content size
// categories, UIFontMetrics scaling, and labels following the scene's category. Sizes against
// the simulator: UIKitGoldenFrameTests (uikit/label/fonts).
import Testing
import UIKit
@testable import UIKitWebCore

@Suite @MainActor struct FontTests {
    private func scene() -> UIKitScene {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        scene.configureScreen(size: CGSize(width: 320, height: 400), scale: 2)
        scene.preferredContentSizeCategory = .large
        scene.textEngine = try! Goldens.textEngine()
        return scene
    }

    @Test func italicMonospacedAndBundledFonts() {
        _ = scene()
        let italic = UIFont.italicSystemFont(ofSize: 17)
        #expect(italic.resolved.italic && abs(italic.ascender - 16.187) < 0.01 && abs(italic.lineHeight - 20.287) < 0.01)
        let mono = UIFont.monospacedSystemFont(ofSize: 15, weight: .regular)
        #expect(mono.resolved.designName == "monospaced" && abs(mono.ascender - 14.282) < 0.01 && abs(mono.descender + 3.618) < 0.01)
        // A bundled font's metrics come from its tables through the asset catalog.
        let catalog = AssetCatalog(fonts: ["Abel-Regular": FontResource(postScriptName: "Abel-Regular", family: "Abel", file: "Fonts/Abel-Regular.ttf",
                                                                        unitsPerEm: 1000, ascender: 979.5, descender: -294.9, lineGap: 0, capHeight: 700.2)])
        UIKitScene.shared.assetCatalog = catalog
        let abel = UIFont(name: "Abel-Regular", size: 20)
        #expect(abel?.resolved.family == "Abel-Regular" && abs((abel?.ascender ?? 0) - 19.59) < 0.01 && abs((abel?.lineHeight ?? 0) - 25.488) < 0.01)
        #expect(UIFont(name: "Abel", size: 13)?.resolved.family == "Abel-Regular")
        #expect(UIFont.familyNames.contains("Abel") && UIFont.fontNames(forFamilyName: "Abel") == ["Abel-Regular"])
        UIKitScene.shared.assetCatalog = .empty
    }

    @Test func textStylesScaleWithTheCategory() {
        _ = scene()
        let large = UIFont.preferredFont(forTextStyle: .body, compatibleWith: UITraitCollection(preferredContentSizeCategory: .large))
        #expect(large == UIFont.preferredFont(forTextStyle: .body) && large.pointSize == 17)
        let xxxl = UIFont.preferredFont(forTextStyle: .body, compatibleWith: UITraitCollection(preferredContentSizeCategory: .extraExtraExtraLarge))
        #expect(xxxl.pointSize == 23 && xxxl.textStyle == .body && xxxl.resolved.key == "style:body:XXXL")
        // Its own metrics (measured): ascender 24.73, line 32.72, a 33 pt label.
        #expect(abs(xxxl.ascender - 24.732) < 0.01 && abs(xxxl.lineHeight - 32.72) < 0.01 && xxxl.labelHeight(lines: 1, scale: 2) == 33)
        let axm = UIFont.preferredFont(forTextStyle: .footnote, compatibleWith: UITraitCollection(preferredContentSizeCategory: .accessibilityMedium))
        #expect(axm.pointSize == 23 && abs(axm.ascender - 24.4) < 0.01)
        #expect(UIFont.preferredFont(forTextStyle: .headline, compatibleWith: UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)).pointSize == 53)
        #expect(UIFont.preferredFont(forTextStyle: .title1, compatibleWith: UITraitCollection(preferredContentSizeCategory: .small)).pointSize == 26)
        // UIFontMetrics scales a plain font by the style's growth (16 at XXL body: 19) and values.
        let metrics = UIFontMetrics(forTextStyle: .body)
        let xxl = UITraitCollection(preferredContentSizeCategory: .extraExtraLarge)
        #expect(metrics.scaledFont(for: .systemFont(ofSize: 16), compatibleWith: xxl).pointSize == 19)
        #expect(metrics.scaledFont(for: .systemFont(ofSize: 16), maximumPointSize: 18, compatibleWith: xxl).pointSize == 18)
        #expect(abs(metrics.scaledValue(for: 10, compatibleWith: xxl) - 10 * 21 / 17) < 0.001)
        #expect(UIFontMetrics.default.scaledFont(for: .systemFont(ofSize: 16)).pointSize == 16)
    }

    @Test func labelsFollowTheScenesCategory() {
        let scene = scene()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        let root = UIViewController()
        let label = UILabel()
        label.text = "Body"
        label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        let fixed = UILabel()
        fixed.text = "Fixed"
        fixed.font = .preferredFont(forTextStyle: .body)
        root.view.addSubview(label)
        root.view.addSubview(fixed)
        window.rootViewController = root
        window.makeKeyAndVisible()
        scene.layout(in: CGSize(width: 320, height: 400))
        #expect(label.font.pointSize == 17)
        scene.preferredContentSizeCategory = .extraExtraExtraLarge
        #expect(label.font.pointSize == 23 && label.font.textStyle == .body && fixed.font.pointSize == 17)
        #expect(root.view.traitCollection.preferredContentSizeCategory == .extraExtraExtraLarge)
        scene.preferredContentSizeCategory = .large
        #expect(label.font.pointSize == 17 && label.font == UIFont.preferredFont(forTextStyle: .body))
    }
}
