// UIButton (Docs/elements/UIKit/UIButton.md): system buttons sized to fit, the iOS 15
// configurations, a disabled button.
#if canImport(UIKit)
import UIKit
import UIKitFixtureKit

public enum ButtonFixtures {
    public static let all = [basic, looks]

    /// A custom-type button's title, images beside and above titles, a subtitle, the button
    /// sizes, and the highlighted and disabled looks of a filled button (uk-button).
    public static let looks = UIKitFixture("uikit/button/looks", size: CGSize(width: 320, height: 420)) {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 420))
        @MainActor func place(_ button: UIButton, x: CGFloat, y: CGFloat, id: String) {
            button.sizeToFit()
            button.frame.origin = CGPoint(x: x, y: y)
            root.addSubview(button.probe(id))
        }
        let custom = UIButton(type: .custom)
        custom.setTitle("Custom", for: .normal)
        custom.setTitleColor(.black, for: .normal)
        place(custom, x: 16, y: 16, id: "custom")
        var leading = UIButton.Configuration.gray()
        leading.title = "Star"
        leading.image = UIImage(systemName: "star")
        leading.imagePadding = 6
        place(UIButton(configuration: leading), x: 16, y: 60, id: "leading")
        var trailing = UIButton.Configuration.gray()
        trailing.title = "Star"
        trailing.image = UIImage(systemName: "star")
        trailing.imagePlacement = .trailing
        trailing.imagePadding = 6
        place(UIButton(configuration: trailing), x: 120, y: 60, id: "trailing")
        var top = UIButton.Configuration.gray()
        top.title = "Star"
        top.image = UIImage(systemName: "star")
        top.imagePlacement = .top
        top.imagePadding = 6
        place(UIButton(configuration: top), x: 224, y: 60, id: "top")
        var subtitled = UIButton.Configuration.filled()
        subtitled.title = "Title"
        subtitled.subtitle = "Subtitle"
        place(UIButton(configuration: subtitled), x: 16, y: 130, id: "subtitled")
        var mini = UIButton.Configuration.gray()
        mini.title = "Mini"
        mini.buttonSize = .mini
        place(UIButton(configuration: mini), x: 16, y: 200, id: "mini")
        var small = UIButton.Configuration.gray()
        small.title = "Small"
        small.buttonSize = .small
        place(UIButton(configuration: small), x: 90, y: 200, id: "small")
        var large = UIButton.Configuration.gray()
        large.title = "Large"
        large.buttonSize = .large
        place(UIButton(configuration: large), x: 170, y: 200, id: "large")
        var highlighted = UIButton.Configuration.filled()
        highlighted.title = "Pressed"
        let pressed = UIButton(configuration: highlighted)
        pressed.isHighlighted = true
        place(pressed, x: 16, y: 270, id: "pressed")
        var disabledConfiguration = UIButton.Configuration.filled()
        disabledConfiguration.title = "Disabled"
        let disabled = UIButton(configuration: disabledConfiguration)
        disabled.isEnabled = false
        place(disabled, x: 120, y: 270, id: "disabled")
        var disabledGray = UIButton.Configuration.gray()
        disabledGray.title = "Off"
        let off = UIButton(configuration: disabledGray)
        off.isEnabled = false
        place(off, x: 230, y: 270, id: "off")
        let image = UIButton(type: .system)
        image.setImage(UIImage(systemName: "heart"), for: .normal)
        image.setTitle("Heart", for: .normal)
        place(image, x: 16, y: 340, id: "systemImage")
        return root
    }

    public static let basic = UIKitFixture("uikit/button/basic", size: CGSize(width: 320, height: 300)) {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 300))
        @MainActor func place(_ button: UIButton, y: CGFloat, id: String) {
            button.sizeToFit()
            button.frame.origin = CGPoint(x: 16, y: y)
            root.addSubview(button.probe(id))
        }
        let system = UIButton(type: .system)
        system.setTitle("Tap", for: .normal)
        place(system, y: 16, id: "system")
        let disabled = UIButton(type: .system)
        disabled.setTitle("Disabled", for: .normal)
        disabled.isEnabled = false
        place(disabled, y: 56, id: "disabled")
        var plain = UIButton.Configuration.plain()
        plain.title = "Plain"
        place(UIButton(configuration: plain), y: 96, id: "plain")
        var gray = UIButton.Configuration.gray()
        gray.title = "Gray"
        place(UIButton(configuration: gray), y: 140, id: "gray")
        var tinted = UIButton.Configuration.tinted()
        tinted.title = "Tinted"
        place(UIButton(configuration: tinted), y: 184, id: "tinted")
        var filled = UIButton.Configuration.filled()
        filled.title = "Filled"
        place(UIButton(configuration: filled), y: 228, id: "filled")
        return root
    }
}
#endif
