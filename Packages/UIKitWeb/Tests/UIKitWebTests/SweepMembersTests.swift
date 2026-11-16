// UIKit members the sweep's apps call (Mlem, GistHub, OscarWeather, Clendar, swift-navigation):
// font traits, a scroll view's tracking, keyboard input modes, repeated animations inside a
// block, the navigation bar's shadow and background images, a window scene's geometry.
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

    @Test func aScrollViewTracksWhileAFingerIsDown() {
        let scroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        #expect(!scroll.isTracking)
        let touch = UITouch(at: CGPoint(x: 50, y: 50), in: nil, view: scroll, type: .direct, timestamp: 0)
        scroll.touchesBegan([touch], with: nil)
        #expect(scroll.isTracking && !scroll.isDragging)
        scroll.touchesEnded([touch], with: nil)
        #expect(!scroll.isTracking)
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
}
