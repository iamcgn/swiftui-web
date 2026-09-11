// UITextView (Controls/UITextView.swift): sizing from the font's label heights and the insets,
// lines limited to the container when not scrolling, editing through the host's multi-line
// input with the delegate hearing, and the semantics node carrying a multi-line input.
import Testing
import UIKit
import WebGraphics
#if canImport(AppKit)
import WebGraphicsNative
#endif

@Suite @MainActor struct TextViewTests {
    private func window() -> (UIWindow, UIViewController) {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        #if canImport(AppKit)
        scene.textEngine = CoreTextEngine()   // real line breaking; the goldens hold the placement
        #else
        scene.textEngine = try! Goldens.textEngine()
        #endif
        scene.configureScreen(size: CGSize(width: 320, height: 500), scale: 2)
        let root = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 500))
        window.rootViewController = root
        window.makeKeyAndVisible()
        scene.layout(in: CGSize(width: 320, height: 500))
        return (window, root)
    }

    @Test func sizingUsesTheInsetsAndLabelHeights() {
        let (_, root) = window()
        let view = UITextView(frame: CGRect(x: 0, y: 0, width: 200, height: 10))
        view.isScrollEnabled = false
        view.font = .systemFont(ofSize: 17)
        view.text = "Centred"
        root.view.addSubview(view)
        let fitted = view.sizeThatFits(CGSize(width: 200, height: CGFloat.greatestFiniteMagnitude))
        let expectedHeight: CGFloat = 16 + 20.5   // the insets plus the 17 pt label height
        #expect(fitted.height == expectedHeight)
        #expect(fitted.width > 40 && fitted.width < 80)
        view.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        let padded = view.sizeThatFits(CGSize(width: 200, height: CGFloat.greatestFiniteMagnitude))
        #expect(padded.height == expectedHeight + 8)
        #expect(padded.width == fitted.width + 24)
        #expect(view.intrinsicContentSize.width == UIView.noIntrinsicMetric)
        #expect(view.intrinsicContentSize.height == padded.height)
        view.isScrollEnabled = true
        #expect(view.intrinsicContentSize.height == UIView.noIntrinsicMetric)
    }

    @Test func editingGoesThroughTheHostAndTheDelegateHears() {
        let (_, root) = window()
        let scene = UIKitScene.shared
        let view = UITextView(frame: CGRect(x: 16, y: 16, width: 288, height: 100))
        view.font = .systemFont(ofSize: 17)
        view.text = "Hello"
        let listener = Listener()
        view.delegate = listener
        root.view.addSubview(view)
        scene.layout(in: CGSize(width: 320, height: 500))
        guard let node = scene.semanticsTree().first(where: { $0.textInput != nil }) else { Issue.record("no text input"); return }
        #expect(node.role == .textField)
        #expect(node.textInput?.isMultiline == true)
        #expect(node.textInput?.text == "Hello")
        #expect(node.textInput?.lineHeight == 20.5)
        #expect(node.textInput?.firstBaseline == 16.5)
        #expect(node.textInput?.textRect.minX == 21)
        #expect(node.textInput?.textRect.minY == 24)
        scene.pointerDown(at: CGPoint(x: 100, y: 50), type: .touch, time: 1)
        scene.pointerUp(at: CGPoint(x: 100, y: 50), time: 1.1)
        #expect(view.isFirstResponder)
        #expect(listener.began == 1)
        #expect(scene.focusedTextFieldIdentifier == node.identifier)
        scene.textField(node.identifier, didChange: "Hello\nworld")
        #expect(view.text == "Hello\nworld")
        #expect(listener.changed == 1)
        scene.textField(node.identifier, focused: false)
        #expect(!view.isFirstResponder)
        #expect(listener.ended == 1)
        view.isEditable = false
        _ = view.becomeFirstResponder()
        #expect(!view.isFirstResponder)
    }

    @Test func aNonScrollingViewShowsTheLinesThatFit() {
        let (_, root) = window()
        let scene = UIKitScene.shared
        let view = UITextView(frame: CGRect(x: 16, y: 16, width: 120, height: 57))
        view.isScrollEnabled = false
        view.font = .systemFont(ofSize: 17)
        view.text = "One\nTwo\nThree"
        root.view.addSubview(view)
        scene.layout(in: CGSize(width: 320, height: 500))
        let drawn = scene.render(scale: 2, background: false).commands.compactMap { command -> String? in
            if case .drawText(let text, _, _, _) = command { return text }
            return nil
        }
        #expect(drawn.contains("One") && drawn.contains("Two"))
        #expect(!drawn.contains("Three"))
        view.isScrollEnabled = true
        scene.layout(in: CGSize(width: 320, height: 500))
        let scrolling = scene.render(scale: 2, background: false).commands.compactMap { command -> String? in
            if case .drawText(let text, _, _, _) = command { return text }
            return nil
        }
        #expect(scrolling.contains("Three"))
        let threeLines: CGFloat = 16 + 61   // the insets plus three 17 pt lines (60.86 rounded up)
        #expect(view.contentSize.height == threeLines)
    }
}

@MainActor
private final class Listener: UITextViewDelegate {
    var began = 0, changed = 0, ended = 0
    func textViewDidBeginEditing(_ textView: UITextView) { began += 1 }
    func textViewDidChange(_ textView: UITextView) { changed += 1 }
    func textViewDidEndEditing(_ textView: UITextView) { ended += 1 }
}
