// UIButton (Docs/elements/UIKit/UIButton.md): system buttons sized to fit, the iOS 15
// configurations, a disabled button.
#if canImport(UIKit)
import UIKit
import UIKitFixtureKit

public enum ButtonFixtures {
    public static let all = [basic]

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
