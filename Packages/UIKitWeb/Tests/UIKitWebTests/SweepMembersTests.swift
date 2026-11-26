// UIKit members the sweep's apps call (Mlem, GistHub, OscarWeather, Clendar, swift-navigation):
// font traits, a scroll view's tracking, keyboard input modes, repeated animations inside a
// block, the navigation bar's shadow and background images, a window scene's geometry, and a
// shake handled up the responder chain (Harbour's window).
import Testing
import UIKit
@testable import UIKitWebCore

@Suite @MainActor struct SweepMembersTests {
    @Test func fontDescriptorsReadAndSetBoldAndItalic() throws {
        let body = UIFont.systemFont(ofSize: 17)
        #expect(body.fontDescriptor.symbolicTraits.isEmpty)
        #expect(UIFont.boldSystemFont(ofSize: 17).fontDescriptor.symbolicTraits.contains(.traitBold))
        #expect(UIFont.italicSystemFont(ofSize: 17).fontDescriptor.symbolicTraits == .traitItalic)
        #expect(UIFont.monospacedSystemFont(ofSize: 12, weight: .regular).fontDescriptor.symbolicTraits.contains(.traitMonoSpace))

        let boldItalic = try #require(body.fontDescriptor.withSymbolicTraits([.traitBold, .traitItalic]))
        let font = UIFont(descriptor: boldItalic, size: 0)
        #expect(font.weight == .bold && font.resolved.italic && font.pointSize == 17)
        #expect(boldItalic.symbolicTraits == [.traitBold, .traitItalic])

        let plain = try #require(boldItalic.withSymbolicTraits([]))
        #expect(UIFont(descriptor: plain, size: 0).weight == .regular && !UIFont(descriptor: plain, size: 0).resolved.italic)
    }

    /// Highlightr's theme fonts: a family and a face make a descriptor, and the face picks the
    /// weight and slant; the system font's family name stands for the system font.
    @Test func fontDescriptorsFromAttributes() {
        let code = UIFont(name: "Courier", size: 14)!
        let bold = UIFontDescriptor(fontAttributes: [UIFontDescriptor.AttributeName.family: code.familyName, UIFontDescriptor.AttributeName.face: "Bold"])
        let boldFont = UIFont(descriptor: bold, size: code.pointSize)
        #expect(boldFont.familyName == "Courier" && boldFont.weight == .bold && boldFont.pointSize == 14)
        let italic = UIFont(descriptor: UIFontDescriptor(fontAttributes: [.family: code.familyName, .face: "Italic"]), size: 14)
        #expect(italic.resolved.italic && italic.weight == .regular)
        #expect(bold.fontAttributes[.face] as? String == "Bold")

        let system = UIFontDescriptor(fontAttributes: [.family: UIFont.systemFont(ofSize: 17).familyName, .size: 17])
        #expect(system.pointSize == 17 && system.symbolicTraits.isEmpty)
        #expect(UIFontDescriptor(fontAttributes: [:]).pointSize == 12)
        #expect(UIFontDescriptor(name: "Courier", size: 9).withFamily("Menlo").fontAttributes[.family] as? String == "Menlo")
        #expect(UIFontDescriptor.AttributeName.family.rawValue == "NSFontFamilyAttribute")
    }

    /// `addingAttributes(_:)` keeps what the descriptor had except what it is given (#393): a
    /// new size keeps a bold system font bold, and a new family with no face keeps bold.
    @Test func addingAttributesKeepsTheRest() {
        let original = UIFont.systemFont(ofSize: 14, weight: .bold).fontDescriptor
        let resized = original.addingAttributes([.size: CGFloat(18)])
        #expect(resized.pointSize == 18 && resized.symbolicTraits.contains(.traitBold))
        #expect(UIFont(descriptor: resized, size: 0).weight == .bold)
        #expect(resized.fontAttributes[.size] as? CGFloat == 18)

        let italic = UIFont.italicSystemFont(ofSize: 12).fontDescriptor.addingAttributes([.featureSettings: [[String: Any]]()])
        #expect(italic.pointSize == 12 && italic.symbolicTraits.contains(.traitItalic))

        let courier = original.withFamily("Courier")
        #expect(UIFont(descriptor: courier, size: 0).familyName == "Courier" && courier.symbolicTraits.contains(.traitBold))
        let face = original.addingAttributes([.family: "Courier", .face: "Regular"])
        #expect(!face.symbolicTraits.contains(.traitBold))
    }

    /// Kingfisher's flip transitions are options `transition(with:)` takes; the change applies.
    @Test func flipTransitionsApplyTheirChanges() {
        let view = UIView()
        var finished = false
        UIView.transition(with: view, duration: 0, options: [.transitionFlipFromLeft, .curveEaseOut], animations: { view.alpha = 0.5 }) { finished = $0 }
        #expect(view.alpha == 0.5 && finished)
        #expect(UIView.AnimationOptions.transitionFlipFromBottom.rawValue == 7 << 20 && UIView.AnimationOptions.transitionFlipFromTop != .transitionFlipFromRight)
    }

    @Test func aScrollViewTracksWhileAFingerIsDown() {
        let scroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        #expect(!scroll.isTracking)
        let touch = UITouch(at: CGPoint(x: 50, y: 50), in: nil, view: scroll, type: .direct, timestamp: 0)
        scroll.touchesBegan([touch], with: nil)
        #expect(scroll.isTracking && !scroll.isDragging)
        scroll.touchesEnded([touch], with: nil)
        #expect(!scroll.isTracking)
    }

    @Test func aScrollViewTracksATouchOnAControlInside() {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        scene.configureScreen(size: CGSize(width: 200, height: 200), scale: 2)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        let scroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        scroll.contentSize = CGSize(width: 200, height: 600)
        let button = UIButton(frame: CGRect(x: 20, y: 20, width: 100, height: 44))
        scroll.addSubview(button)
        window.addSubview(scroll)
        window.makeKeyAndVisible()
        scene.layout(in: CGSize(width: 200, height: 200))
        let point = CGPoint(x: 50, y: 40)
        scene.pointerDown(at: point, type: .touch, time: 0)
        #expect(button.isTracking && scroll.isTracking && !scroll.isDragging)
        scene.pointerUp(at: point, time: 0.05)
        #expect(!scroll.isTracking && !button.isTracking)
        scene.removeAllWindows()
    }

    @Test func textInputModesAreTheBrowsersLanguage() {
        final class EmojiField: UITextField {
            override var textInputContextIdentifier: String? { "" }
            override var textInputMode: UITextInputMode? {
                UITextInputMode.activeInputModes.first { $0.primaryLanguage == "emoji" } ?? super.textInputMode
            }
        }
        #expect(UITextInputMode.activeInputModes.count == 1)
        #expect(UITextInputMode.activeInputModes.first?.primaryLanguage == Locale.preferredLanguages.first)
        let field = EmojiField()
        #expect(field.textInputMode == nil && field.textInputContextIdentifier == "")
    }

    @Test func modifiedAnimationsRepeat() {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        var repeats: Double?
        var reverses: Bool?
        UIView.animate(withDuration: 0.3) {
            UIView.modifyAnimations(withRepeatCount: 3, autoreverses: true) {
                view.alpha = 0.5
            }
            repeats = UIViewAnimationContext.current?.repeatCount
            reverses = UIViewAnimationContext.current?.autoreverses
        }
        #expect(repeats == 3 && reverses == true)
        var ran = false
        UIView.modifyAnimations(withRepeatCount: 2, autoreverses: false) { ran = true }
        #expect(ran)
    }

    @Test func navigationBarsKeepTheirImagesAndScenesTheirGeometry() {
        let bar = UINavigationBar(frame: .zero)
        let empty = UIImage()
        bar.setBackgroundImage(empty, for: .default)
        bar.shadowImage = empty
        #expect(bar.backgroundImage(for: .default) === empty && bar.backgroundImage(for: .compact) == nil)
        #expect(bar.shadowImage === empty)

        let scene = UIWindowScene(session: UISceneSession())
        #expect(scene.effectiveGeometry.interfaceOrientation == scene.interfaceOrientation)
        #expect(!scene.effectiveGeometry.isInteractivelyResizing)
    }

    final class ShakeListener: UIViewController {
        var heard: [UIEvent.EventSubtype] = []
        override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
            heard.append(motion)
            super.motionEnded(motion, with: event)
        }
    }

    @Test func aShakeTravelsUpTheResponderChain() {
        let listener = ShakeListener()
        let child = UIView()
        listener.view.addSubview(child)
        child.motionEnded(.motionShake, with: nil)
        child.motionBegan(.remoteControlPlay, with: nil)
        #expect(listener.heard == [.motionShake])
        #expect(UIEvent.EventSubtype.motionShake.rawValue == 1 && UIEvent.EventSubtype.remoteControlEndSeekingForward.rawValue == 109)
    }

    #if canImport(ObjectiveC)
    @Test func anOverrideFromAnExtensionHearsTheShake() {
        let view = ExtensionShakeView()
        let responder: UIResponder = view
        responder.motionEnded(.motionShake, with: nil)
        #expect(view.heardInExtension == [.motionShake])
    }
    #endif
}

#if canImport(ObjectiveC)
/// Harbour overrides `motionEnded(_:with:)` in an extension of `UIWindow`, which Swift allows
/// only for `@objc` methods; called through `UIResponder`, the override still runs.
final class ExtensionShakeView: UIView {
    var heardInExtension: [UIEvent.EventSubtype] = []
}

extension ExtensionShakeView {
    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        heardInExtension.append(motion)
    }
}
#endif
