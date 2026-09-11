// Auto Layout (Docs/elements/UIKit/AutoLayout.md): constraints from anchors, activated on the
// fixture's root view, solved by UIKit's engine on the simulator and by UIKitWeb's Cassowary
// solver: pins and centring, aspect ratios, intrinsic sizes, priorities and inequalities, the
// margins and safe-area guides, fitting sizes, baselines, and constraints changed after layout.
#if canImport(UIKit)
import UIKit
import UIKitFixtureKit

public enum AutoLayoutFixtures {
    public static let all = [pins, priorities, guides, fitting, baseline, update]

    @MainActor static func box(_ color: UIColor, _ id: String) -> UIView {
        let view = UIView()
        view.backgroundColor = color
        view.translatesAutoresizingMaskIntoConstraints = false
        return view.probe(id)
    }

    @MainActor static func label(_ text: String, _ id: String, size: CGFloat = 17) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: size)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label.probe(id)
    }

    /// Edges pinned with constants, centring (on and off the pixel grid), an aspect ratio, labels
    /// at their intrinsic size and stretched between the edges, a view at the bottom right.
    public static let pins = UIKitFixture("uikit/autolayout/pins", size: CGSize(width: 320, height: 300)) {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 300))
        let banner = box(.systemBlue, "banner")
        let centered = box(.systemGreen, "centered")
        let container = UIView(frame: CGRect(x: 205, y: 120, width: 99, height: 51))
        container.backgroundColor = .systemGray5
        let quarter = box(.systemOrange, "quarter")
        let aspect = box(.systemPink, "aspect")
        let pinned = label("Pinned label", "label")
        let stretched = label("Stretched", "stretched")
        stretched.backgroundColor = .systemYellow
        let corner = box(.systemPurple, "corner")
        for view in [banner, centered, aspect, pinned, stretched, corner] { root.addSubview(view) }
        root.addSubview(container.probe("container"))
        container.addSubview(quarter)
        NSLayoutConstraint.activate([
            banner.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            banner.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            banner.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            banner.heightAnchor.constraint(equalToConstant: 40),
            centered.widthAnchor.constraint(equalToConstant: 101),
            centered.heightAnchor.constraint(equalToConstant: 51),
            centered.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            centered.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            quarter.widthAnchor.constraint(equalToConstant: 34.5),
            quarter.heightAnchor.constraint(equalToConstant: 20.5),
            quarter.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            quarter.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            aspect.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            aspect.topAnchor.constraint(equalTo: root.topAnchor, constant: 72),
            aspect.heightAnchor.constraint(equalToConstant: 30),
            aspect.widthAnchor.constraint(equalTo: aspect.heightAnchor, multiplier: 2),
            pinned.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            pinned.topAnchor.constraint(equalTo: root.topAnchor, constant: 120),
            stretched.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            stretched.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            stretched.topAnchor.constraint(equalTo: root.topAnchor, constant: 160),
            corner.widthAnchor.constraint(equalToConstant: 40),
            corner.heightAnchor.constraint(equalToConstant: 40),
            corner.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            corner.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),
        ])
        return root
    }

    /// Priorities: an optional width clamped by a required inequality, two widths at different
    /// priorities, inequalities against equalities, and two labels sharing a row with one that
    /// resists compression less.
    public static let priorities = UIKitFixture("uikit/autolayout/priorities", size: CGSize(width: 320, height: 300)) {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 300))
        let wide = box(.systemBlue, "wide")
        let pick = box(.systemGreen, "pick")
        let atLeast = box(.systemOrange, "atLeast")
        let atLeast2 = box(.systemPink, "atLeast2")
        let left = label("A long label that needs room", "left")
        left.backgroundColor = .systemYellow
        left.setContentCompressionResistancePriority(UILayoutPriority(749), for: .horizontal)
        // The row has room to spare: the label that hugs less (the right one, at UILabel's 251)
        // takes it; equal priorities would leave the layout ambiguous.
        left.setContentHuggingPriority(UILayoutPriority(252), for: .horizontal)
        let right = label("Short", "right")
        right.backgroundColor = .systemTeal
        for view in [wide, pick, atLeast, atLeast2, left, right] { root.addSubview(view) }
        let wideWidth = wide.widthAnchor.constraint(equalToConstant: 500)
        wideWidth.priority = UILayoutPriority(999)
        let pick200 = pick.widthAnchor.constraint(equalToConstant: 200)
        pick200.priority = UILayoutPriority(250)
        let pick100 = pick.widthAnchor.constraint(equalToConstant: 100)
        pick100.priority = UILayoutPriority(750)
        let atLeast100 = atLeast.widthAnchor.constraint(greaterThanOrEqualToConstant: 100)
        atLeast100.priority = UILayoutPriority(750)
        let atLeast50 = atLeast.widthAnchor.constraint(equalToConstant: 50)
        atLeast50.priority = UILayoutPriority(999)
        let atLeast2Min = atLeast2.widthAnchor.constraint(greaterThanOrEqualToConstant: 100)
        atLeast2Min.priority = UILayoutPriority(999)
        let atLeast2Eq = atLeast2.widthAnchor.constraint(equalToConstant: 50)
        atLeast2Eq.priority = UILayoutPriority(750)
        NSLayoutConstraint.activate([
            wide.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            wide.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -16),
            wide.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            wide.heightAnchor.constraint(equalToConstant: 30),
            wideWidth,
            pick.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            pick.topAnchor.constraint(equalTo: wide.bottomAnchor, constant: 8),
            pick.heightAnchor.constraint(equalToConstant: 30),
            pick200, pick100,
            atLeast.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            atLeast.topAnchor.constraint(equalTo: pick.bottomAnchor, constant: 8),
            atLeast.heightAnchor.constraint(equalToConstant: 30),
            atLeast100, atLeast50,
            atLeast2.leadingAnchor.constraint(equalTo: atLeast.trailingAnchor, constant: 8),
            atLeast2.topAnchor.constraint(equalTo: atLeast.topAnchor),
            atLeast2.heightAnchor.constraint(equalTo: atLeast.heightAnchor),
            atLeast2Min, atLeast2Eq,
            left.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            left.topAnchor.constraint(equalTo: atLeast.bottomAnchor, constant: 16),
            right.leadingAnchor.constraint(equalTo: left.trailingAnchor, constant: 8),
            right.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            right.firstBaselineAnchor.constraint(equalTo: left.firstBaselineAnchor),
        ])
        return root
    }

    /// The layout guides: a view filling the root's margins (a controller's view keeps the
    /// system minimum), one at the safe area's top leading corner, one filling a plain
    /// container's margins.
    public static let guides = UIKitFixture("uikit/autolayout/guides", size: CGSize(width: 320, height: 300)) {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 300))
        let margins = box(.systemGray4, "margins")
        let safe = box(.systemBlue, "safe")
        let container = UIView(frame: CGRect(x: 40, y: 150, width: 200, height: 100))
        container.backgroundColor = .systemGray5
        let inner = box(.systemGreen, "inner")
        root.addSubview(margins)
        root.addSubview(safe)
        root.addSubview(container.probe("container"))
        container.addSubview(inner)
        NSLayoutConstraint.activate([
            margins.leadingAnchor.constraint(equalTo: root.layoutMarginsGuide.leadingAnchor),
            margins.trailingAnchor.constraint(equalTo: root.layoutMarginsGuide.trailingAnchor),
            margins.topAnchor.constraint(equalTo: root.layoutMarginsGuide.topAnchor),
            margins.bottomAnchor.constraint(equalTo: root.layoutMarginsGuide.bottomAnchor),
            safe.leadingAnchor.constraint(equalTo: root.safeAreaLayoutGuide.leadingAnchor),
            safe.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor),
            safe.widthAnchor.constraint(equalToConstant: 50),
            safe.heightAnchor.constraint(equalToConstant: 50),
            inner.leadingAnchor.constraint(equalTo: container.layoutMarginsGuide.leadingAnchor),
            inner.trailingAnchor.constraint(equalTo: container.layoutMarginsGuide.trailingAnchor),
            inner.topAnchor.constraint(equalTo: container.layoutMarginsGuide.topAnchor),
            inner.bottomAnchor.constraint(equalTo: container.layoutMarginsGuide.bottomAnchor),
        ])
        return root
    }

    /// A card sized by `systemLayoutSizeFitting` from the labels it constrains inside it.
    public static let fitting = UIKitFixture("uikit/autolayout/fitting", size: CGSize(width: 320, height: 300)) {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 300))
        let card = UIView()
        card.backgroundColor = .systemGray5
        let title = label("Title", "title")
        let subtitle = label("Subtitle text", "subtitle")
        card.addSubview(title)
        card.addSubview(subtitle)
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: card.topAnchor, constant: 8),
            title.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 8),
            title.trailingAnchor.constraint(lessThanOrEqualTo: card.trailingAnchor, constant: -8),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 4),
            subtitle.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 8),
            subtitle.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -8),
            subtitle.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -8),
        ])
        let size = card.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        card.frame = CGRect(origin: CGPoint(x: 16, y: 16), size: size)
        root.addSubview(card.probe("card"))
        // The same card fitted to a required width.
        let wide = UIView()
        wide.backgroundColor = .systemGray5
        let wideTitle = label("Title", "wideTitle")
        let wideSubtitle = label("Subtitle text", "wideSubtitle")
        wide.addSubview(wideTitle)
        wide.addSubview(wideSubtitle)
        NSLayoutConstraint.activate([
            wideTitle.topAnchor.constraint(equalTo: wide.topAnchor, constant: 8),
            wideTitle.leadingAnchor.constraint(equalTo: wide.leadingAnchor, constant: 8),
            wideSubtitle.topAnchor.constraint(equalTo: wideTitle.bottomAnchor, constant: 4),
            wideSubtitle.leadingAnchor.constraint(equalTo: wide.leadingAnchor, constant: 8),
            wideSubtitle.trailingAnchor.constraint(equalTo: wide.trailingAnchor, constant: -8),
            wideSubtitle.bottomAnchor.constraint(equalTo: wide.bottomAnchor, constant: -8),
        ])
        let wideSize = wide.systemLayoutSizeFitting(CGSize(width: 288, height: 0), withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
        wide.frame = CGRect(origin: CGPoint(x: 16, y: 120), size: wideSize)
        root.addSubview(wide.probe("wide"))
        return root
    }

    /// Baselines: labels of 11, 13, 20, 28 and 34 pt with their first baselines on a 17 pt
    /// label's, a box on the 17 pt label's last baseline.
    public static let baseline = UIKitFixture("uikit/autolayout/baseline", size: CGSize(width: 320, height: 300)) {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 300))
        let small = label("Hg", "small")
        let square = box(.systemBlue, "box")
        root.addSubview(small)
        root.addSubview(square)
        NSLayoutConstraint.activate([
            small.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            small.topAnchor.constraint(equalTo: root.topAnchor, constant: 60),
            square.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            square.topAnchor.constraint(equalTo: root.topAnchor, constant: 160),
            square.widthAnchor.constraint(equalToConstant: 30),
            square.heightAnchor.constraint(equalTo: square.widthAnchor),
        ])
        var previous: UIView = small
        for size in [11, 13, 20, 28, 34] as [CGFloat] {
            let other = label("Hg", "size\(Int(size))", size: size)
            root.addSubview(other)
            NSLayoutConstraint.activate([
                other.leadingAnchor.constraint(equalTo: previous.trailingAnchor, constant: 8),
                other.firstBaselineAnchor.constraint(equalTo: small.firstBaselineAnchor),
            ])
            previous = other
        }
        // A box hung from a label's last baseline, and a label whose last baseline sits on a box's bottom.
        let hung = label("Hg", "hung", size: 20)
        root.addSubview(hung)
        NSLayoutConstraint.activate([
            hung.leadingAnchor.constraint(equalTo: square.trailingAnchor, constant: 8),
            hung.lastBaselineAnchor.constraint(equalTo: square.bottomAnchor),
        ])
        return root
    }

    @MainActor public final class UpdateModel {
        var leading: NSLayoutConstraint?
        var narrow: NSLayoutConstraint?
        var wide: NSLayoutConstraint?
        public init() {}
    }

    /// Constraints changed after the first layout: a constant moves a view, swapping the active
    /// width constraint resizes it.
    public static let update = UIKitFixture("uikit/autolayout/update", size: CGSize(width: 320, height: 300),
                                            model: { UpdateModel() },
                                            steps: [UIKitFixtureStep("move") { $0.leading?.constant = 100 },
                                                    UIKitFixtureStep("widen") { $0.narrow?.isActive = false; $0.wide?.isActive = true }]) { model in
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 300))
        let mover = box(.systemBlue, "mover")
        root.addSubview(mover)
        let leading = mover.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16)
        let narrow = mover.widthAnchor.constraint(equalToConstant: 60)
        let wide = mover.widthAnchor.constraint(equalToConstant: 200)
        model.leading = leading
        model.narrow = narrow
        model.wide = wide
        NSLayoutConstraint.activate([
            leading, narrow,
            mover.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            mover.heightAnchor.constraint(equalToConstant: 40),
        ])
        return root
    }
}
#endif
