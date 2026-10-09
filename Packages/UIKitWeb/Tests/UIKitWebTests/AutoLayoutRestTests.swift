// uk-autolayout-rest (Layout/LayoutEngine.swift, Controls/UIStackView.swift): a guide the app
// makes gets its frame from the constraints on it, a constraint change inside an animation
// block tweens through `layoutIfNeeded`, the controls' hugging defaults, a stack's hidden views
// and proportional fill, and the solver's cost on a large tree.
import Foundation
import Testing
import UIKit
@testable import UIKitWebCore

@Suite @MainActor struct AutoLayoutRestTests {
    private func scene(_ size: CGSize = CGSize(width: 320, height: 300)) -> (UIKitScene, UIWindow) {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        scene.textEngine = try! Goldens.textEngine()
        scene.configureScreen(size: size, scale: 2)
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.makeKeyAndVisible()
        return (scene, window)
    }

    @Test func guidesTakeTheirSolvedFrames() {
        let (_, window) = scene()
        let root = UIView(frame: window.bounds)
        window.addSubview(root)
        let guide = UILayoutGuide()
        guide.identifier = "spacer"
        root.addLayoutGuide(guide)
        let box = UIView()
        box.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(box)
        NSLayoutConstraint.activate([
            guide.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
            guide.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            guide.widthAnchor.constraint(equalTo: root.widthAnchor, multiplier: 0.25),
            guide.heightAnchor.constraint(equalToConstant: 30),
            box.leadingAnchor.constraint(equalTo: guide.trailingAnchor, constant: 5),
            box.centerYAnchor.constraint(equalTo: guide.centerYAnchor),
            box.widthAnchor.constraint(equalToConstant: 40),
            box.heightAnchor.constraint(equalToConstant: 10),
        ])
        window.layoutIfNeeded()
        #expect(guide.layoutFrame == CGRect(x: 10, y: 20, width: 80, height: 30) && guide.owningView === root && guide.identifier == "spacer")
        #expect(box.frame == CGRect(x: 95, y: 30, width: 40, height: 10))
        #expect(root.layoutGuides.count == 1)
        root.removeLayoutGuide(guide)
        #expect(root.layoutGuides.isEmpty && guide.owningView !== root)
    }

    @Test func constraintChangesAnimateThroughLayoutIfNeeded() {
        let (scene, window) = scene()
        let root = UIView(frame: window.bounds)
        window.addSubview(root)
        let mover = UIView()
        mover.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(mover)
        let leading = mover.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16)
        NSLayoutConstraint.activate([leading, mover.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
                                     mover.widthAnchor.constraint(equalToConstant: 60), mover.heightAnchor.constraint(equalToConstant: 40)])
        window.layoutIfNeeded()
        #expect(mover.frame.minX == 16)
        leading.constant = 116
        var completed = false
        UIView.animate(withDuration: 1, delay: 0, options: [.curveLinear], animations: { window.layoutIfNeeded() }, completion: { _ in completed = true })
        #expect(mover.frame.minX == 116)   // the model moved inside the block
        _ = scene.advanceFrame(elapsed: 0.5)
        let presented = mover.layer.presented(.position, model: .point(mover.layer.position)).point.x
        #expect(abs(presented - (66 + 30)) < 0.01)   // halfway: the centre from 46 to 146
        _ = scene.advanceFrame(elapsed: 0.6)
        #expect(completed && !scene.isAnimating)
    }

    @Test func huggingDefaultsAndHiddenStacks() {
        let (_, window) = scene()
        let label = UILabel()
        #expect(label.contentHuggingPriority(for: .horizontal) == .defaultLow && label.contentCompressionResistancePriority(for: .vertical) == .defaultHigh)
        #expect(label.intrinsicContentSize == .zero && label.sizeThatFits(CGSize(width: 100, height: 100)) == .zero)
        for control: UIView in [UISwitch(), UIStepper(), UIActivityIndicatorView(style: .medium)] {
            #expect(control.contentHuggingPriority(for: .horizontal) == .defaultHigh && control.contentHuggingPriority(for: .vertical) == .defaultHigh)
        }
        for control: UIView in [UISlider(), UISegmentedControl(items: ["One"]), UIProgressView(progressViewStyle: .default), UIPageControl()] {
            #expect(control.contentHuggingPriority(for: .horizontal) == .defaultLow && control.contentHuggingPriority(for: .vertical) == .defaultHigh)
        }
        let segments = UISegmentedControl(items: ["One", "Two"])
        #expect(segments.intrinsicContentSize == CGSize(width: 88, height: 31) && segments.sizeThatFits(.zero) == CGSize(width: 88, height: 32))
        let toggle = UISwitch()
        toggle.frame = CGRect(x: 0, y: 0, width: 10, height: 10)
        #expect(toggle.frame.size == CGSize(width: 68, height: 30) && toggle.intrinsicContentSize.width == 66 && toggle.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).width == 68)
        let progress = UIProgressView(progressViewStyle: .default)
        progress.frame = CGRect(x: 0, y: 0, width: 100, height: 8)
        #expect(progress.frame.height == 4)

        // A stack has no intrinsic size of its own but sizes its content under constraints.
        let root = UIView(frame: window.bounds)
        window.addSubview(root)
        let a = UILabel(), b = UILabel(), c = UILabel()
        a.text = "Before"; b.text = "Hidden"; c.text = "After"
        b.isHidden = true
        let stack = UIStackView(arrangedSubviews: [a, b, c])
        stack.spacing = 8
        stack.setCustomSpacing(24, after: a)
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16), stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
                                     stack.widthAnchor.constraint(equalToConstant: 200), stack.heightAnchor.constraint(equalToConstant: 24)])
        window.layoutIfNeeded()
        #expect(stack.intrinsicContentSize.width == UIView.noIntrinsicMetric && stack._contentSize == CGSize(width: 50.5 + 24 + 37.5, height: 20.5))
        #expect(a.frame == CGRect(x: 0, y: 0, width: 138.5, height: 24) && c.frame == CGRect(x: 162.5, y: 0, width: 37.5, height: 24))
        #expect(b.frame == CGRect(x: 150.5, y: 0, width: 0, height: 24))   // the midpoint of the gap
        stack.distribution = .fillProportionally
        b.isHidden = false
        stack.layoutIfNeeded()
        // 50.5, 55 and 37.5 over their sum plus 32 of spacing (24 + 8), in 200, each rounded to
        // the pixel; the last takes the rest.
        #expect(a.frame.width == 57.5 && b.frame.width == 63 && c.frame.width == 200 - 32 - 57.5 - 63)
    }

    @Test func largeTreesSolveQuickly() {
        let (_, window) = scene(CGSize(width: 320, height: 2000))
        let root = UIView(frame: window.bounds)
        window.addSubview(root)
        // A column of 200 rows, each a label beside a box, chained top to bottom: 1,000
        // constraints over 400 views.
        var previous: UIView = root
        var constraints: [NSLayoutConstraint] = []
        for index in 0..<200 {
            let label = UILabel()
            label.text = "Row"
            label.translatesAutoresizingMaskIntoConstraints = false
            let box = UIView()
            box.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(label)
            root.addSubview(box)
            constraints += [
                label.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
                label.topAnchor.constraint(equalTo: index == 0 ? root.topAnchor : previous.bottomAnchor, constant: 4),
                box.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 8),
                box.centerYAnchor.constraint(equalTo: label.centerYAnchor),
                box.widthAnchor.constraint(equalToConstant: 20),
                box.heightAnchor.constraint(equalTo: label.heightAnchor),
            ]
            previous = label
        }
        NSLayoutConstraint.activate(constraints)
        let start = Date()
        window.layoutIfNeeded()
        let elapsed = Date().timeIntervalSince(start)
        #expect(previous.frame.minY > 0 && (root.subviews.last?.frame.minX ?? 0) > 16)
        #expect(elapsed < 1.5, "a 1,000-constraint pass took \(elapsed) s")   // 0.27 s in debug on an M-series Mac; was 5.6 s before the column index
    }
}
