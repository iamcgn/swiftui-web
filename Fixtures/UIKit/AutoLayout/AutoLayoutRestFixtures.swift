// Auto Layout, the rest (uk-autolayout-rest, Docs/elements/UIKit/AutoLayout.md,
// Docs/elements/UIKit/UIStackView.md): layout guides the app makes (spacers, a centred guide,
// one owned by a container), the content hugging and compression resistance defaults of the
// controls reported as probe widths, and the stack distributions UIKit was not yet measured
// on: fill proportionally, overflow under fill and equal spacing, spacing after hidden views.
#if canImport(UIKit)
import UIKit
import UIKitFixtureKit

public enum AutoLayoutRestFixtures {
    public static let all = [layoutGuides, hugging, distribution]

    /// Spacer guides sharing the room between three boxes, a guide centred in the root with a
    /// view inset in it, and a guide owned by a container holding a box at its centre; the
    /// `reveal` views pin to the guides' edges so the goldens carry their frames.
    public static let layoutGuides = UIKitFixture("uikit/autolayout/layoutguides", size: CGSize(width: 320, height: 300)) {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 300))
        let a = AutoLayoutFixtures.box(.systemBlue, "a")
        let b = AutoLayoutFixtures.box(.systemGreen, "b")
        let c = AutoLayoutFixtures.box(.systemOrange, "c")
        let spacer1 = UILayoutGuide()
        let spacer2 = UILayoutGuide()
        let reveal1 = AutoLayoutFixtures.box(.systemGray5, "spacer1")
        let reveal2 = AutoLayoutFixtures.box(.systemGray5, "spacer2")
        for view in [a, b, c, reveal1, reveal2] { root.addSubview(view) }
        root.addLayoutGuide(spacer1)
        root.addLayoutGuide(spacer2)
        let centred = UILayoutGuide()
        centred.identifier = "centred"
        root.addLayoutGuide(centred)
        let revealCentred = AutoLayoutFixtures.box(.systemGray5, "centred")
        let inset = AutoLayoutFixtures.box(.systemPurple, "inset")
        root.addSubview(revealCentred)
        root.addSubview(inset)
        let container = UIView(frame: CGRect(x: 16, y: 200, width: 200, height: 84))
        container.backgroundColor = .systemGray6
        root.addSubview(container.probe("container"))
        let owned = UILayoutGuide()
        container.addLayoutGuide(owned)
        let revealOwned = AutoLayoutFixtures.box(.systemGray4, "owned")
        let dot = AutoLayoutFixtures.box(.systemPink, "dot")
        container.addSubview(revealOwned)
        container.addSubview(dot)
        NSLayoutConstraint.activate([
            a.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            a.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            a.widthAnchor.constraint(equalToConstant: 60),
            a.heightAnchor.constraint(equalToConstant: 40),
            spacer1.leadingAnchor.constraint(equalTo: a.trailingAnchor),
            b.leadingAnchor.constraint(equalTo: spacer1.trailingAnchor),
            b.topAnchor.constraint(equalTo: a.topAnchor),
            b.widthAnchor.constraint(equalToConstant: 80),
            b.heightAnchor.constraint(equalTo: a.heightAnchor),
            spacer2.leadingAnchor.constraint(equalTo: b.trailingAnchor),
            c.leadingAnchor.constraint(equalTo: spacer2.trailingAnchor),
            c.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            c.topAnchor.constraint(equalTo: a.topAnchor),
            c.widthAnchor.constraint(equalToConstant: 50),
            c.heightAnchor.constraint(equalTo: a.heightAnchor),
            spacer2.widthAnchor.constraint(equalTo: spacer1.widthAnchor),
            spacer1.topAnchor.constraint(equalTo: a.topAnchor),
            spacer1.heightAnchor.constraint(equalToConstant: 10),
            spacer2.topAnchor.constraint(equalTo: a.bottomAnchor, constant: -10),
            spacer2.bottomAnchor.constraint(equalTo: a.bottomAnchor),
            reveal1.leadingAnchor.constraint(equalTo: spacer1.leadingAnchor),
            reveal1.trailingAnchor.constraint(equalTo: spacer1.trailingAnchor),
            reveal1.topAnchor.constraint(equalTo: spacer1.topAnchor),
            reveal1.bottomAnchor.constraint(equalTo: spacer1.bottomAnchor),
            reveal2.leadingAnchor.constraint(equalTo: spacer2.leadingAnchor),
            reveal2.trailingAnchor.constraint(equalTo: spacer2.trailingAnchor),
            reveal2.topAnchor.constraint(equalTo: spacer2.topAnchor),
            reveal2.bottomAnchor.constraint(equalTo: spacer2.bottomAnchor),
            centred.widthAnchor.constraint(equalToConstant: 101),
            centred.heightAnchor.constraint(equalToConstant: 61),
            centred.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            centred.centerYAnchor.constraint(equalTo: root.topAnchor, constant: 110),
            revealCentred.leadingAnchor.constraint(equalTo: centred.leadingAnchor),
            revealCentred.trailingAnchor.constraint(equalTo: centred.trailingAnchor),
            revealCentred.topAnchor.constraint(equalTo: centred.topAnchor),
            revealCentred.bottomAnchor.constraint(equalTo: centred.bottomAnchor),
            inset.leadingAnchor.constraint(equalTo: centred.leadingAnchor, constant: 8),
            inset.trailingAnchor.constraint(equalTo: centred.trailingAnchor, constant: -8),
            inset.topAnchor.constraint(equalTo: centred.topAnchor, constant: 8),
            inset.bottomAnchor.constraint(equalTo: centred.bottomAnchor, constant: -8),
            owned.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            owned.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -30),
            owned.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            owned.heightAnchor.constraint(equalTo: container.heightAnchor, multiplier: 0.5),
            revealOwned.leadingAnchor.constraint(equalTo: owned.leadingAnchor),
            revealOwned.trailingAnchor.constraint(equalTo: owned.trailingAnchor),
            revealOwned.topAnchor.constraint(equalTo: owned.topAnchor),
            revealOwned.bottomAnchor.constraint(equalTo: owned.bottomAnchor),
            dot.widthAnchor.constraint(equalToConstant: 20),
            dot.heightAnchor.constraint(equalToConstant: 20),
            dot.centerXAnchor.constraint(equalTo: owned.centerXAnchor),
            dot.centerYAnchor.constraint(equalTo: owned.centerYAnchor),
        ])
        return root
    }

    /// Every common control at its fitting size down the left, and beside each a row of four
    /// 1 pt probes whose widths are its horizontal hugging, vertical hugging, horizontal
    /// compression resistance and vertical compression resistance priorities over 4 (250 →
    /// 62.5, 251 → 62.75, 750 → 187.5, 1000 → 250).
    public static let hugging = UIKitFixture("uikit/autolayout/hugging", size: CGSize(width: 320, height: 640)) {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        let label = UILabel()
        label.text = "Label"
        let button = UIButton(type: .system)
        button.setTitle("Button", for: .normal)
        let field = UITextField()
        field.text = "Field"
        field.borderStyle = .roundedRect
        let toggle = UISwitch()
        let slider = UISlider()
        let segments = UISegmentedControl(items: ["One", "Two"])
        let stepper = UIStepper()
        let image = UIImageView(image: UIKitFixtureImage.named("badge"))
        let progress = UIProgressView(progressViewStyle: .default)
        progress.progress = 0.5
        let spinner = UIActivityIndicatorView(style: .medium)
        let pages = UIPageControl()
        pages.numberOfPages = 3
        let text = UITextView()
        text.text = "Text view"
        let scroll = UIScrollView()
        let stack = UIStackView(arrangedSubviews: [UILabel()])
        let stacked = UILabel()
        stacked.text = "Label"
        let filledStack = UIStackView(arrangedSubviews: [stacked])
        let empty = UILabel()
        let plain = UIView()
        let controls: [(String, UIView)] = [("view", plain), ("label", label), ("button", button), ("field", field), ("switch", toggle), ("slider", slider),
                                            ("segments", segments), ("stepper", stepper), ("image", image), ("progress", progress), ("spinner", spinner),
                                            ("pages", pages), ("text", text), ("scroll", scroll), ("stack", stack), ("filledstack", filledStack), ("empty", empty)]
        var y: CGFloat = 8
        for (name, control) in controls {
            let size = control.intrinsicContentSize
            control.frame = CGRect(x: 8, y: y, width: min(120, max(size.width, 20)), height: min(32, max(size.height, 8)))
            root.addSubview(control.probe(name))
            let priorities = [control.contentHuggingPriority(for: .horizontal), control.contentHuggingPriority(for: .vertical),
                              control.contentCompressionResistancePriority(for: .horizontal), control.contentCompressionResistancePriority(for: .vertical)]
            for (index, priority) in priorities.enumerated() {
                let probe = UIView(frame: CGRect(x: 140, y: y + CGFloat(index) * 8, width: CGFloat(priority.rawValue) / 4, height: 1))
                root.addSubview(probe.probe("\(name)-\(index)"))
            }
            y += 36
        }
        // The same two controls sized by constraints alone: the frame Auto Layout gives an
        // intrinsic size with alignment rect insets.
        let pinnedSegments = UISegmentedControl(items: ["One", "Two"])
        pinnedSegments.translatesAutoresizingMaskIntoConstraints = false
        let pinnedSwitch = UISwitch()
        pinnedSwitch.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(pinnedSegments.probe("pinned-segments"))
        root.addSubview(pinnedSwitch.probe("pinned-switch"))
        NSLayoutConstraint.activate([
            pinnedSegments.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 200),
            pinnedSegments.topAnchor.constraint(equalTo: root.topAnchor, constant: 8),
            pinnedSwitch.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 200),
            pinnedSwitch.topAnchor.constraint(equalTo: root.topAnchor, constant: 48),
        ])
        return root
    }

    /// Stack distributions against UIKit: fill proportionally (labels and a column), fill with
    /// too little room (equal and unequal compression resistances), equal spacing and equal
    /// centring with too little room, and the spacing after hidden views (custom or not).
    public static let distribution = UIKitFixture("uikit/stack/distribution", size: CGSize(width: 320, height: 300)) {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 300))
        @MainActor func label(_ text: String, _ id: String, size: CGFloat = 17) -> UILabel {
            let label = UILabel()
            label.text = text
            label.font = .systemFont(ofSize: size)
            label.backgroundColor = .systemGray5
            return label.probe(id)
        }
        @MainActor func row(_ id: String, _ views: [UIView], _ distribution: UIStackView.Distribution, y: CGFloat, width: CGFloat = 288) -> UIStackView {
            let stack = UIStackView(arrangedSubviews: views)
            stack.axis = .horizontal
            stack.spacing = 8
            stack.distribution = distribution
            stack.frame = CGRect(x: 16, y: y, width: width, height: 24)
            return stack.probe(id)
        }
        root.addSubview(row("proportional", [label("A", "pa"), label("Medium", "pb"), label("The longest one", "pc")], .fillProportionally, y: 8))
        root.addSubview(row("overflow", [label("First overflowing", "oa"), label("Second overflowing", "ob"), label("Third", "oc")], .fill, y: 40))
        let soft = label("Second overflowing", "ub")
        soft.setContentCompressionResistancePriority(UILayoutPriority(749), for: .horizontal)
        root.addSubview(row("unequal", [label("First overflowing", "ua"), soft, label("Third", "uc")], .fill, y: 72))
        root.addSubview(row("spacing", [label("First overflowing", "sa"), label("Second overflowing", "sb"), label("Third", "sc")], .equalSpacing, y: 104))
        root.addSubview(row("centering", [label("First overflowing", "ca"), label("Second overflowing", "cb"), label("Third", "cc")], .equalCentering, y: 136))
        let hiddenMiddle = label("Hidden", "hb")
        hiddenMiddle.isHidden = true
        let hidden = row("hidden", [label("Before", "ha"), hiddenMiddle, label("After", "hc")], .fill, y: 168, width: 200)
        hidden.setCustomSpacing(24, after: hidden.arrangedSubviews[0])
        root.addSubview(hidden)
        let hiddenLast = label("Hidden", "lc")
        hiddenLast.isHidden = true
        let trailing = row("hiddenlast", [label("Before", "la"), label("Middle", "lb"), hiddenLast], .equalSpacing, y: 200, width: 200)
        root.addSubview(trailing)
        let column = UIStackView(arrangedSubviews: [label("Tall", "va", size: 28), label("mid", "vb"), label("small", "vc", size: 12)])
        column.axis = .vertical
        column.spacing = 4
        column.distribution = .fillProportionally
        column.alignment = .leading
        column.frame = CGRect(x: 16, y: 232, width: 120, height: 60)
        root.addSubview(column.probe("column"))
        let spread = UIStackView(arrangedSubviews: [label("Tall", "wa", size: 28), label("mid", "wb"), label("small", "wc", size: 12)])
        spread.axis = .vertical
        spread.spacing = 4
        spread.distribution = .fillProportionally
        spread.alignment = .leading
        spread.frame = CGRect(x: 160, y: 180, width: 120, height: 112)
        root.addSubview(spread.probe("spread"))
        return root
    }
}
#endif
