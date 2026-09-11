// UIToolbar and UISearchBar (Docs/elements/UIKit/Bars.md): a toolbar sized to fit with title,
// system and space items at the bottom and one with Cancel / Done at the top; search bars with
// a placeholder, with text and a Cancel button, and in the minimal style. Measured on the
// iPhone SE simulator.
#if canImport(UIKit)
import UIKit
import UIKitFixtureKit

public enum BarFixtures {
    public static let all = [toolbar, search]

    public static let toolbar = UIKitFixture("uikit/toolbar/basic", size: CGSize(width: 320, height: 400)) {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        root.backgroundColor = .white

        let top = UIToolbar()
        top.items = [
            UIBarButtonItem(title: "Cancel", style: .plain, target: nil, action: nil),
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
            UIBarButtonItem(title: "Done", style: .done, target: nil, action: nil),
        ]
        top.sizeToFit()
        top.frame = CGRect(x: 0, y: 16, width: 320, height: top.frame.height)
        root.addSubview(top.probe("top"))

        let bottom = UIToolbar()
        bottom.items = [
            UIBarButtonItem(title: "Edit", style: .plain, target: nil, action: nil),
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
            UIBarButtonItem(barButtonSystemItem: .add, target: nil, action: nil),
            UIBarButtonItem(barButtonSystemItem: .fixedSpace, target: nil, action: nil),
            UIBarButtonItem(barButtonSystemItem: .trash, target: nil, action: nil),
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
            UIBarButtonItem(barButtonSystemItem: .action, target: nil, action: nil),
        ]
        bottom.items?[3].width = 24
        bottom.sizeToFit()
        bottom.frame = CGRect(x: 0, y: 400 - bottom.frame.height, width: 320, height: bottom.frame.height)
        root.addSubview(bottom.probe("bottom"))

        let compact = UIToolbar()
        compact.items = [UIBarButtonItem(barButtonSystemItem: .add, target: nil, action: nil)]
        compact.sizeToFit()
        compact.frame = CGRect(x: 16, y: 120, width: compact.frame.width, height: compact.frame.height)
        root.addSubview(compact.probe("compact"))
        return root
    }

    public static let search = UIKitFixture("uikit/search/basic", size: CGSize(width: 320, height: 300)) {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 300))
        root.backgroundColor = .white

        let plain = UISearchBar()
        plain.placeholder = "Search"
        plain.sizeToFit()
        plain.frame = CGRect(x: 0, y: 16, width: 320, height: plain.frame.height)
        root.addSubview(plain.probe("plain"))
        plain.searchTextField.probe("plainField")

        let typed = UISearchBar()
        typed.text = "Swift"
        typed.showsCancelButton = true
        typed.sizeToFit()
        typed.frame = CGRect(x: 0, y: 96, width: 320, height: typed.frame.height)
        root.addSubview(typed.probe("typed"))
        typed.searchTextField.probe("typedField")

        let minimal = UISearchBar()
        minimal.searchBarStyle = .minimal
        minimal.placeholder = "Minimal"
        minimal.sizeToFit()
        minimal.frame = CGRect(x: 0, y: 176, width: 320, height: minimal.frame.height)
        root.addSubview(minimal.probe("minimal"))
        minimal.searchTextField.probe("minimalField")
        return root
    }
}
#endif
