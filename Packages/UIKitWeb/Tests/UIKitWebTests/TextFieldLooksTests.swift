// UITextField looks (uk-textfield): the line and bezel borders' sizes and text insets, the
// clear button, left and right views, attributed placeholders and the keyboard attributes the
// host's input element gets. Sizes against the simulator are in UIKitGoldenFrameTests
// (uikit/textfield/looks).
import Testing
import UIKit
@testable import UIKitWebCore

@Suite @MainActor struct TextFieldLooksTests {
    private func scene() -> UIKitScene {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        scene.configureScreen(size: CGSize(width: 320, height: 400), scale: 2)
        scene.textEngine = try! Goldens.textEngine()
        return scene
    }

    private func field(_ text: String, style: UITextField.BorderStyle) -> UITextField {
        let field = UITextField()
        field.text = text
        field.borderStyle = style
        field.sizeToFit()
        return field
    }

    @Test func bordersSizeAndInsetTheirText() {
        _ = scene()
        let line = field("Line border", style: .line)
        #expect(line.frame.size == CGSize(width: 95, height: 30))
        #expect(line.textRect(forBounds: line.bounds) == CGRect(x: 2, y: 4.75, width: 91, height: 20.5))
        let bezel = field("Bezel border", style: .bezel)
        #expect(bezel.frame.size == CGSize(width: 125, height: 32))
        #expect(bezel.textRect(forBounds: bezel.bounds).minX == 7)
        #expect(abs(bezel.textRect(forBounds: bezel.bounds).minY - 7.25) < 0.001)
        let rounded = field("Rounded text", style: .roundedRect)
        #expect(rounded.frame.size == CGSize(width: 130, height: 34))
        #expect(rounded.textRect(forBounds: rounded.bounds) == CGRect(x: 7, y: 6.75, width: 116, height: 20.5))
        let plain = field("Plain text", style: .none)
        #expect(plain.frame.size == CGSize(width: 70, height: 22))
        #expect(plain.textRect(forBounds: plain.bounds).origin == CGPoint(x: 0, y: 0.75))
    }

    @Test func sideViewsSitFlushAndFollowTheirModes() {
        _ = scene()
        let field = UITextField(frame: CGRect(x: 0, y: 0, width: 200, height: 34))
        field.borderStyle = .roundedRect
        field.text = "Views"
        let left = UIView(frame: CGRect(x: 0, y: 0, width: 20, height: 20))
        let right = UIView(frame: CGRect(x: 0, y: 0, width: 24, height: 12))
        field.leftView = left
        field.rightView = right
        field.layoutSubviews()
        #expect(left.superview === field && right.superview === field)
        #expect(left.isHidden && right.isHidden)
        #expect(field.textRect(forBounds: field.bounds).minX == 7)
        field.leftViewMode = .always
        field.rightViewMode = .unlessEditing
        field.layoutSubviews()
        #expect(!left.isHidden && !right.isHidden)
        #expect(left.frame == CGRect(x: 0, y: 7, width: 20, height: 20))
        #expect(right.frame == CGRect(x: 176, y: 11, width: 24, height: 12))
        #expect(field.textRect(forBounds: field.bounds) == CGRect(x: 27, y: 6.75, width: 142, height: 20.5))
        field.leftView = nil
        #expect(left.superview == nil)
        #expect(field.textRect(forBounds: field.bounds).minX == 7)
    }

    @Test func clearButtonShowsInItsModeAndClearsOnTap() {
        let scene = scene()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        let root = UIViewController()
        window.rootViewController = root
        window.makeKeyAndVisible()
        let field = UITextField(frame: CGRect(x: 16, y: 104, width: 160, height: 34))
        field.borderStyle = .roundedRect
        field.text = "Clear"
        field.clearButtonMode = .whileEditing
        root.view.addSubview(field)
        scene.layout(in: CGSize(width: 320, height: 400))
        #expect(!field.showsClearButton)
        #expect(field.textRect(forBounds: field.bounds).width == 146)
        field.becomeFirstResponder()
        #expect(field.showsClearButton)
        #expect(field.clearButtonRect(forBounds: field.bounds) == CGRect(x: 136.5, y: 9, width: 17, height: 17))
        #expect(field.textRect(forBounds: field.bounds).maxX == 125.5)
        let list = scene.render(scale: 2)
        #expect(list.commands.contains { if case .fillPath(let path, _, _) = $0 { return path.boundingRect == CGRect(x: 152.5, y: 113, width: 17, height: 17) } else { return false } })
        var changed = 0
        field.addAction(UIAction { _ in changed += 1 }, for: .editingChanged)
        let p = CGPoint(x: 161, y: 121.5)
        scene.pointerDown(at: p, type: .touch, time: 0)
        scene.pointerUp(at: p, time: 0.05)
        #expect(field.text == "" && changed == 1)
        #expect(!field.showsClearButton)
        let always = UITextField(frame: CGRect(x: 184, y: 104, width: 120, height: 34))
        always.text = "Center"
        always.textAlignment = .center
        always.clearButtonMode = .always
        #expect(always.showsClearButton)
        always.text = ""
        #expect(!always.showsClearButton)
        always.clearButtonMode = .unlessEditing
        always.text = "x"
        #expect(always.showsClearButton)
    }

    @Test func attributedPlaceholderUsesItsFontAndColour() {
        let scene = scene()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        let root = UIViewController()
        window.rootViewController = root
        window.makeKeyAndVisible()
        let field = UITextField(frame: CGRect(x: 16, y: 192, width: 160, height: 34))
        field.borderStyle = .roundedRect
        field.attributedPlaceholder = NSAttributedString(string: "Attributed", attributes: [.foregroundColor: UIColor.systemRed, .font: UIFont.systemFont(ofSize: 15)])
        #expect(field.placeholder == "Attributed")
        root.view.addSubview(field)
        let list = scene.render(scale: 2)
        let texts = list.commands.compactMap { command -> (String, CGPoint, RGBA, CGFloat)? in
            if case .drawText(let text, let font, let origin, let color) = command { return (text, origin, color, font.size) } else { return nil }
        }
        #expect(texts.count == 1)
        #expect(texts.first?.0 == "Attributed")
        #expect(texts.first?.3 == 15)
        #expect(texts.first?.2 == UIColor.systemRed.rgba(for: .light))
        // 15 pt text centred in the 34 pt field: baseline 192 + 8 + 14.28 on the pixel grid.
        #expect(texts.first?.1 == CGPoint(x: 23, y: 214.5))
    }

    @Test func keyboardAttributesReachTheHostInput() {
        let scene = scene()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        let root = UIViewController()
        window.rootViewController = root
        window.makeKeyAndVisible()
        let field = UITextField(frame: CGRect(x: 16, y: 16, width: 200, height: 34))
        field.keyboardType = .emailAddress
        field.returnKeyType = .go
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.textContentType = .emailAddress
        root.view.addSubview(field)
        scene.layout(in: CGSize(width: 320, height: 400))
        guard let node = scene.semanticsTree().first(where: { $0.textInput != nil }), let info = node.textInput else { Issue.record("no text input"); return }
        #expect(info.inputMode == "email" && info.inputType == "email")
        #expect(info.enterKeyHint == "go" && info.autocapitalize == "off" && info.autocorrect == false)
        #expect(info.autocomplete == "email")
        field.isSecureTextEntry = true
        field.keyboardType = .default
        #expect(scene.semanticsTree().first(where: { $0.textInput != nil })?.textInput?.inputType == "password")
    }
}
