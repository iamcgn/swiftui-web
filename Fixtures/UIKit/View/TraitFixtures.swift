// Trait overrides (uk-traits, Docs/elements/UIKit/Dark.md): dark islands on a light page by a
// view's overrideUserInterfaceStyle and by traitOverrides, a light island inside a dark one,
// each holding system colours and controls that resolve per appearance.
#if canImport(UIKit)
import UIKit
import UIKitFixtureKit

public enum TraitFixtures {
    public static let all = [overrides]

    @MainActor static func island(_ probe: String) -> UIView {
        let view = UIView()
        view.backgroundColor = .systemBackground
        let label = UILabel()
        label.text = "Label"
        label.font = .systemFont(ofSize: 17)
        label.sizeToFit()
        label.frame.origin = CGPoint(x: 12, y: 12)
        view.addSubview(label.probe(probe + "Label"))
        let secondary = UILabel()
        secondary.text = "Secondary"
        secondary.font = .systemFont(ofSize: 13)
        secondary.textColor = .secondaryLabel
        secondary.sizeToFit()
        secondary.frame.origin = CGPoint(x: 12, y: 40)
        view.addSubview(secondary.probe(probe + "Secondary"))
        let card = UIView(frame: CGRect(x: 120, y: 12, width: 60, height: 44))
        card.backgroundColor = .secondarySystemBackground
        card.layer.cornerRadius = 8
        view.addSubview(card.probe(probe + "Card"))
        let fill = UIView(frame: CGRect(x: 190, y: 12, width: 44, height: 44))
        fill.backgroundColor = .systemGray5
        view.addSubview(fill.probe(probe + "Fill"))
        let toggle = UISwitch()
        toggle.isOn = true
        toggle.frame.origin = CGPoint(x: 240, y: 19)
        view.addSubview(toggle.probe(probe + "Switch"))
        return view
    }

    public static let overrides = UIKitFixture("uikit/view/traits", size: CGSize(width: 320, height: 320)) {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 320))
        root.backgroundColor = .systemBackground

        let plain = island("plain")
        plain.frame = CGRect(x: 0, y: 8, width: 320, height: 68)
        root.addSubview(plain.probe("plain"))

        let dark = island("dark")
        dark.overrideUserInterfaceStyle = .dark
        dark.frame = CGRect(x: 0, y: 84, width: 320, height: 68)
        root.addSubview(dark.probe("dark"))

        let overridden = island("overridden")
        overridden.traitOverrides.userInterfaceStyle = .dark
        overridden.frame = CGRect(x: 0, y: 160, width: 320, height: 68)
        root.addSubview(overridden.probe("overridden"))

        // A light island inside a dark one: the nearest override wins.
        let outer = UIView(frame: CGRect(x: 0, y: 236, width: 320, height: 76))
        outer.overrideUserInterfaceStyle = .dark
        outer.backgroundColor = .systemBackground
        let inner = island("inner")
        inner.overrideUserInterfaceStyle = .light
        inner.frame = CGRect(x: 8, y: 4, width: 304, height: 68)
        inner.layer.cornerRadius = 10
        outer.addSubview(inner.probe("inner"))
        root.addSubview(outer.probe("outer"))
        return root
    }
}
#endif
