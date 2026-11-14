// Input views (Controls/UIInputView.swift): a toolbar made as KeyboardToolbar makes its
// accessory (a `UIInputView` subclass with the keyboard style that adopts
// `UIInputViewAudioFeedback`) shows along the bottom of the window while its text view edits,
// moves above the keyboard when the host reports one, takes presses without ending the
// editing, and goes when the editing ends.
import Testing
import UIKit
@testable import UIKitWebCore
#if canImport(AppKit)
import WebGraphicsNative
#endif
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif

@Suite @MainActor struct InputViewTests {
    private func scene() -> UIKitScene {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        scene.keyboardFrame = nil
        #if canImport(AppKit)
        scene.textEngine = CoreTextEngine()
        #else
        scene.textEngine = SyntheticTextEngine()
        #endif
        scene.configureScreen(size: CGSize(width: 320, height: 480), scale: 2)
        return scene
    }

    /// KeyboardToolbar's toolbar, reduced to what reaches UIKit: the keyboard style, a fixed
    /// height and a button.
    final class Toolbar: UIInputView, UIInputViewAudioFeedback {
        let button = UIButton(type: .system)
        var presses = 0
        var enableInputClicksWhenVisible: Bool { true }

        init() {
            super.init(frame: CGRect(x: 0, y: 0, width: 0, height: 46), inputViewStyle: .keyboard)
            autoresizingMask = .flexibleWidth
            button.setTitle("Tab", for: .normal)
            button.frame = CGRect(x: 8, y: 4, width: 60, height: 38)
            button.addAction(UIAction { [weak self] _ in self?.presses += 1 }, for: .touchUpInside)
            addSubview(button)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    }

    @Test func aStyleAndItsDefaults() {
        let plain = UIInputView(frame: .zero)
        #expect(plain.inputViewStyle == .default)
        #expect(plain.backgroundColor == nil)
        #expect(!plain.allowsSelfSizing)
        let keyboard = UIInputView(frame: .zero, inputViewStyle: .keyboard)
        #expect(keyboard.inputViewStyle == .keyboard)
        #expect(keyboard.backgroundColor != nil)
        #expect(Toolbar().enableInputClicksWhenVisible)
        #expect(UIResponder().inputView == nil && UIResponder().inputAccessoryView == nil)
    }

    @Test func theAccessoryShowsWhileEditing() {
        let scene = scene()
        let root = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        window.rootViewController = root
        window.makeKeyAndVisible()
        let editor = UITextView(frame: CGRect(x: 0, y: 0, width: 320, height: 200))
        let toolbar = Toolbar()
        editor.inputAccessoryView = toolbar
        #expect(editor.inputAccessoryView === toolbar)
        let input = UIView()
        editor.inputView = input
        #expect(editor.inputView === input)
        editor.inputView = nil
        root.view.addSubview(editor)
        scene.layout(in: CGSize(width: 320, height: 480))
        #expect(toolbar.superview == nil)

        #expect(editor.becomeFirstResponder())
        #expect(toolbar.superview === window)
        let bottom = 480 - window.safeAreaInsets.bottom
        #expect(toolbar.frame == CGRect(x: 0, y: bottom - 46, width: 320, height: 46))

        // The keyboard comes up: the toolbar sits on it.
        scene.keyboardFrame = CGRect(x: 0, y: 480 - 216, width: 320, height: 216)
        #expect(toolbar.frame == CGRect(x: 0, y: 480 - 216 - 46, width: 320, height: 46))

        // A press on the toolbar's button reaches it and leaves the text view editing.
        scene.layout(in: CGSize(width: 320, height: 480))
        let point = toolbar.convert(CGPoint(x: 38, y: 23), to: window)
        scene.pointerDown(at: point, type: .touch, time: 0)
        scene.pointerUp(at: point, time: 0.05)
        #expect(toolbar.presses == 1)
        #expect(editor.isFirstResponder)

        // A press elsewhere ends the editing, and the toolbar goes.
        scene.keyboardFrame = nil
        let outside = CGPoint(x: 160, y: 300)
        scene.pointerDown(at: outside, type: .touch, time: 1)
        scene.pointerUp(at: outside, time: 1.05)
        #expect(!editor.isFirstResponder)
        #expect(toolbar.superview == nil)
    }

    @Test func aFieldAndASearchBarTakeAccessoriesToo() {
        let scene = scene()
        let root = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        window.rootViewController = root
        window.makeKeyAndVisible()
        let field = UITextField(frame: CGRect(x: 20, y: 20, width: 280, height: 34))
        let search = UISearchBar(frame: CGRect(x: 0, y: 80, width: 320, height: 56))
        let accessory = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 30))
        let other = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 40))
        field.inputAccessoryView = accessory
        search.inputAccessoryView = other
        #expect(search.searchTextField.inputAccessoryView === other)
        root.view.addSubview(field)
        root.view.addSubview(search)
        scene.layout(in: CGSize(width: 320, height: 480))

        #expect(field.becomeFirstResponder())
        #expect(accessory.superview === window && accessory.frame.height == 30)
        // Editing moves to the search field: its accessory replaces the field's.
        #expect(search.becomeFirstResponder())
        #expect(accessory.superview == nil)
        #expect(other.superview === window && other.frame.height == 40)
        // A changed accessory shows on `reloadInputViews()`.
        let replacement = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 50))
        search.searchTextField.inputAccessoryView = replacement
        search.searchTextField.reloadInputViews()
        #expect(other.superview == nil)
        #expect(replacement.superview === window && replacement.frame.height == 50)
        #expect(search.resignFirstResponder())
        #expect(replacement.superview == nil)
    }
}
