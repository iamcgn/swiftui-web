// Accessibility (uk-accessibility, Docs/elements/Accessibility.md): the elements, traits and
// custom actions a UIKit screen exposes, an explicit element order, a modal panel hiding its
// siblings, and a notification posted by a button. The pixels are plain controls; the probe
// (Playwright/uikit-accessibility-probe.mjs) reads the overlay and the browser's accessible
// tree.
#if canImport(UIKit)
import UIKit
import UIKitFixtureKit

public enum AccessibilityFixtures {
    public static let all = [basic]

    @MainActor public final class Model {
        var archived = 0
        var modal: UIView?
        var status: UILabel?
        public init() {}
    }

    public static let basic = UIKitFixture("uikit/accessibility/basic", size: CGSize(width: 320, height: 300),
                                           model: { Model() },
                                           steps: [UIKitFixtureStep("modal") { $0.modal?.isHidden = false }]) { model in
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 300))
        root.backgroundColor = .white

        let title = UILabel(frame: CGRect(x: 16, y: 12, width: 288, height: 28))
        title.text = "Inbox"
        title.font = .systemFont(ofSize: 22, weight: .bold)
        title.accessibilityTraits = .header
        root.addSubview(title.probe("title"))

        let row = UILabel(frame: CGRect(x: 16, y: 48, width: 200, height: 22))
        row.text = "Archived: 0"
        row.isAccessibilityElement = true
        row.accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "Archive") { [weak model, weak row] _ in
                guard let model, let row else { return false }
                model.archived += 1
                row.text = "Archived: \(model.archived)"
                return true
            },
            UIAccessibilityCustomAction(name: "Flag") { _ in true },
        ]
        root.addSubview(row.probe("row"))

        let image = UIImageView(image: UIKitFixtureImage.named("badge"))
        image.frame = CGRect(x: 240, y: 44, width: 30, height: 30)
        image.isAccessibilityElement = true
        image.accessibilityLabel = "Badge"
        root.addSubview(image.probe("image"))

        // Three buttons laid out A, B, C but exposed C, A, B through accessibilityElements.
        let order = UIView(frame: CGRect(x: 16, y: 80, width: 288, height: 36))
        var buttons: [UIButton] = []
        for (index, name) in ["A", "B", "C"].enumerated() {
            let button = UIButton(type: .system)
            button.setTitle(name, for: .normal)
            button.frame = CGRect(x: index * 60, y: 0, width: 50, height: 36)
            order.addSubview(button.probe("button\(name)"))
            buttons.append(button)
        }
        order.accessibilityElements = [buttons[2], buttons[0], buttons[1]]
        root.addSubview(order.probe("order"))

        let disabled = UIButton(type: .system)
        disabled.setTitle("Disabled", for: .normal)
        disabled.isEnabled = false
        disabled.frame = CGRect(x: 16, y: 124, width: 90, height: 36)
        root.addSubview(disabled.probe("disabled"))

        let selected = UIButton(type: .system)
        selected.setTitle("Selected", for: .normal)
        selected.isSelected = true
        selected.frame = CGRect(x: 116, y: 124, width: 90, height: 36)
        root.addSubview(selected.probe("selected"))

        let link = UILabel(frame: CGRect(x: 216, y: 124, width: 90, height: 36))
        link.text = "Terms"
        link.textColor = .systemBlue
        link.accessibilityTraits = .link
        root.addSubview(link.probe("link"))

        let toggle = UISwitch(frame: CGRect(x: 16, y: 170, width: 68, height: 30))
        toggle.isOn = true
        toggle.accessibilityLabel = "Notifications"
        root.addSubview(toggle.probe("switch"))

        let slider = UISlider(frame: CGRect(x: 100, y: 170, width: 120, height: 30))
        slider.value = 0.25
        slider.accessibilityLabel = "Volume"
        root.addSubview(slider.probe("slider"))

        let hidden = UILabel(frame: CGRect(x: 230, y: 174, width: 80, height: 22))
        hidden.text = "Secret"
        hidden.accessibilityElementsHidden = true
        root.addSubview(hidden.probe("hidden"))

        let status = UILabel(frame: CGRect(x: 16, y: 210, width: 288, height: 22))
        status.text = "Ready"
        status.accessibilityTraits = [.staticText, .updatesFrequently]
        root.addSubview(status.probe("status"))
        model.status = status

        let announce = UIButton(type: .system)
        announce.setTitle("Announce", for: .normal)
        announce.frame = CGRect(x: 16, y: 240, width: 100, height: 36)
        announce.addAction(UIAction { [weak status] _ in
            status?.text = "Announced"
            UIAccessibility.post(notification: .announcement, argument: "Saved")
        }, for: .touchUpInside)
        root.addSubview(announce.probe("announce"))

        // A modal panel (hidden until the step) hides its siblings from assistive technology.
        let modal = UIView(frame: CGRect(x: 40, y: 100, width: 240, height: 120))
        modal.backgroundColor = .systemGray6
        modal.layer.cornerRadius = 12
        modal.accessibilityViewIsModal = true
        modal.isHidden = true
        let modalTitle = UILabel(frame: CGRect(x: 16, y: 16, width: 208, height: 24))
        modalTitle.text = "Modal"
        modalTitle.accessibilityTraits = .header
        modal.addSubview(modalTitle.probe("modalTitle"))
        let close = UIButton(type: .system)
        close.setTitle("Close", for: .normal)
        close.frame = CGRect(x: 16, y: 60, width: 80, height: 36)
        modal.addSubview(close.probe("close"))
        root.addSubview(modal.probe("modal"))
        model.modal = modal
        return root
    }
}
#endif
