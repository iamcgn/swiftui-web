// Auto Layout (Layout/Cassowary.swift, LayoutEngine.swift, NSLayoutConstraint.swift): the solver
// places constrained views, honours priorities and inequalities, fits sizes, and re-solves when
// constraints change. The goldens (uikit/autolayout/*) pin the numbers against UIKit; these
// tests hold the mechanics.
import Testing
import UIKit

@Suite @MainActor struct AutoLayoutTests {
    private func window(_ size: CGSize = CGSize(width: 320, height: 300)) -> UIWindow {
        UIKitScene.shared.removeAllWindows()
        UIKitScene.shared.configureScreen(size: size, scale: 2)
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.makeKeyAndVisible()
        return window
    }

    @Test func pinsAndCentring() {
        let window = window()
        let root = UIView(frame: window.bounds)
        window.addSubview(root)
        let banner = UIView()
        banner.translatesAutoresizingMaskIntoConstraints = false
        let centred = UIView()
        centred.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(banner)
        root.addSubview(centred)
        NSLayoutConstraint.activate([
            banner.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            banner.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            banner.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            banner.heightAnchor.constraint(equalToConstant: 40),
            centred.widthAnchor.constraint(equalToConstant: 101),
            centred.heightAnchor.constraint(equalTo: centred.widthAnchor, multiplier: 0.5),
            centred.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            centred.centerYAnchor.constraint(equalTo: root.centerYAnchor),
        ])
        window.layoutIfNeeded()
        #expect(banner.frame == CGRect(x: 16, y: 16, width: 288, height: 40))
        // Centred: (320 − 101) / 2 = 109.5; the height is 50.5 and the origin lands on the pixel
        // grid (the goldens pin which way a quarter point rounds).
        #expect(centred.frame.minX == 109.5 && centred.frame.size == CGSize(width: 101, height: 50.5))
        #expect(abs(centred.frame.midY - 150) <= 0.25)
        // Two-item constraints live on the common ancestor, single-item ones on the item.
        #expect(root.constraints.count == 5)
        #expect(banner.constraints.count == 1)
        #expect(centred.constraints.count == 2)
    }

    @Test func prioritiesAndInequalities() {
        let window = window()
        let root = UIView(frame: window.bounds)
        window.addSubview(root)
        let wide = UIView(), pick = UIView(), atLeast = UIView()
        for view in [wide, pick, atLeast] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
                view.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
                view.heightAnchor.constraint(equalToConstant: 30),
            ])
        }
        let wideWidth = wide.widthAnchor.constraint(equalToConstant: 500)
        wideWidth.priority = UILayoutPriority(999)
        let pick200 = pick.widthAnchor.constraint(equalToConstant: 200)
        pick200.priority = UILayoutPriority(250)
        let pick100 = pick.widthAnchor.constraint(equalToConstant: 100)
        pick100.priority = UILayoutPriority(750)
        let atLeast100 = atLeast.widthAnchor.constraint(greaterThanOrEqualToConstant: 100)
        atLeast100.priority = UILayoutPriority(999)
        let atLeast50 = atLeast.widthAnchor.constraint(equalToConstant: 50)
        atLeast50.priority = UILayoutPriority(750)
        NSLayoutConstraint.activate([wide.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -16), wideWidth, pick200, pick100, atLeast100, atLeast50])
        window.layoutIfNeeded()
        #expect(wide.frame.width == 288)
        #expect(pick.frame.width == 100)
        #expect(atLeast.frame.width == 100)
    }

    @Test func intrinsicSizesAndFitting() {
        let window = window()
        UIKitScene.shared.textEngine = try! Goldens.textEngine()
        let root = UIView(frame: window.bounds)
        window.addSubview(root)
        let card = UIView()
        let title = UILabel()
        title.text = "Title"
        title.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(title)
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: card.topAnchor, constant: 8),
            title.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 8),
            title.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -8),
            title.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -8),
        ])
        let size = card.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        let text = title.intrinsicContentSize
        #expect(size == CGSize(width: text.width + 16, height: text.height + 16))
        card.frame = CGRect(origin: CGPoint(x: 16, y: 16), size: size)
        root.addSubview(card)
        window.layoutIfNeeded()
        #expect(title.frame == CGRect(x: 8, y: 8, width: text.width, height: text.height))
    }

    @Test func changesResolve() {
        let window = window()
        let root = UIView(frame: window.bounds)
        window.addSubview(root)
        let mover = UIView()
        mover.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(mover)
        let leading = mover.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16)
        let narrow = mover.widthAnchor.constraint(equalToConstant: 60)
        let wide = mover.widthAnchor.constraint(equalToConstant: 200)
        NSLayoutConstraint.activate([leading, narrow, mover.topAnchor.constraint(equalTo: root.topAnchor, constant: 16), mover.heightAnchor.constraint(equalToConstant: 40)])
        window.layoutIfNeeded()
        #expect(mover.frame == CGRect(x: 16, y: 16, width: 60, height: 40))
        leading.constant = 100
        window.layoutIfNeeded()
        #expect(mover.frame.minX == 100)
        narrow.isActive = false
        wide.isActive = true
        window.layoutIfNeeded()
        #expect(mover.frame.width == 200)
        #expect(!root.constraints.contains { $0 === narrow })
    }
}

/// The visual format language (Layout/NSLayoutConstraint.swift): spacing, sizes, relations,
/// priorities, metrics and alignment options resolve to the frames UIKit gives
/// (uikit/autolayout/visualformat pins the same layout on the simulator).
@Suite @MainActor struct VisualFormatTests {
    @Test func formatsLayOutTheViews() {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        scene.configureScreen(size: CGSize(width: 320, height: 300), scale: 2)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 300))
        let controller = UIViewController()   // a root view's margins are 16 sideways: `|-[c]-|` lands on them
        window.rootViewController = controller
        let root = controller.view!
        let a = UIView(), b = UIView(), c = UIView(), d = UIView()
        for view in [a, b, c, d] { view.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(view) }
        let views: [String: Any] = ["a": a, "b": b, "c": c, "d": d]
        let metrics: [String: Any] = ["gap": 12, "side": 16]
        var constraints: [NSLayoutConstraint] = []
        constraints += NSLayoutConstraint.constraints(withVisualFormat: "H:|-side-[a(80)]-8-[b(>=60)]-side-|", options: [.alignAllTop, .alignAllBottom], metrics: metrics, views: views)
        constraints += NSLayoutConstraint.constraints(withVisualFormat: "V:|-20-[a(40)]-gap-[c(30)]-(>=8)-|", options: [], metrics: metrics, views: views)
        constraints += NSLayoutConstraint.constraints(withVisualFormat: "H:|-[c]-|", options: [], metrics: nil, views: views)
        constraints += NSLayoutConstraint.constraints(withVisualFormat: "V:[c]-gap-[d(24)]", options: [], metrics: metrics, views: views)
        constraints += NSLayoutConstraint.constraints(withVisualFormat: "H:|-(>=20)-[d(120@750)]-20-|", options: [], metrics: nil, views: views)
        #expect(constraints.count == 19)
        NSLayoutConstraint.activate(constraints)
        window.makeKeyAndVisible()
        scene.layout(in: CGSize(width: 320, height: 300))
        #expect(a.frame == CGRect(x: 16, y: 20, width: 80, height: 40))
        #expect(b.frame == CGRect(x: 104, y: 20, width: 200, height: 40))
        #expect(c.frame == CGRect(x: 16, y: 72, width: 288, height: 30))
        #expect(d.frame == CGRect(x: 180, y: 114, width: 120, height: 24))
        // A format that does not parse yields nothing.
        #expect(NSLayoutConstraint.constraints(withVisualFormat: "H:[missing]", options: [], metrics: nil, views: views).isEmpty)
        #expect(NSLayoutConstraint.constraints(withVisualFormat: "H:|-[a", options: [], metrics: nil, views: views).isEmpty)
    }
}
