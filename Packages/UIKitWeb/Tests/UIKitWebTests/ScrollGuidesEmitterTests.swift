// A scroll view's content and frame layout guides (Controls/UIScrollView.swift,
// Layout/LayoutEngine.swift), a text view's typing attributes and range scrolling
// (Controls/UITextView.swift), and the emitter layer's particles (Layers/CAEmitterLayer.swift).
import Testing
import UIKit
import WebGraphics
@testable import UIKitWebCore

@Suite @MainActor struct ScrollGuidesEmitterTests {
    private func window() -> UIWindow {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        scene.textEngine = SyntheticTextEngine()
        scene.configureScreen(size: CGSize(width: 320, height: 480), scale: 2)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        window.makeKeyAndVisible()
        return window
    }

    /// The reading tracker's and swipe interaction's setup: content pinned to the content guide's
    /// edges and as wide as the frame guide.
    @Test func theContentGuidesSolvedSizeIsTheContentSize() {
        let window = window()
        let scroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        window.addSubview(scroll)
        let content = UIView()
        content.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
            content.heightAnchor.constraint(equalToConstant: 1200),
        ])
        window.layoutIfNeeded()
        #expect(content.frame == CGRect(x: 0, y: 0, width: 320, height: 1200))
        #expect(scroll.contentSize == CGSize(width: 320, height: 1200))
        #expect(scroll.contentLayoutGuide.layoutFrame == CGRect(x: 0, y: 0, width: 320, height: 1200))
        #expect(scroll.contentLayoutGuide === scroll.contentLayoutGuide && scroll.contentLayoutGuide.owningView === scroll)
        // The content now scrolls to its end.
        scroll.setContentOffset(CGPoint(x: 0, y: 5000), animated: false)
        #expect(scroll.contentOffset.y == 720)
    }

    @Test func theFrameGuideIsTheVisiblePart() {
        let window = window()
        let scroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: 200, height: 300))
        scroll.contentSize = CGSize(width: 200, height: 900)
        window.addSubview(scroll)
        scroll.contentOffset = CGPoint(x: 0, y: 100)
        let badge = UIView()
        badge.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(badge)
        NSLayoutConstraint.activate([
            badge.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -10),
            badge.bottomAnchor.constraint(equalTo: scroll.frameLayoutGuide.bottomAnchor, constant: -10),
            badge.widthAnchor.constraint(equalToConstant: 20),
            badge.heightAnchor.constraint(equalToConstant: 20),
        ])
        window.layoutIfNeeded()
        // In the content's coordinates: the visible rectangle starts 100 points down.
        #expect(badge.frame == CGRect(x: 170, y: 370, width: 20, height: 20))
        // A scroll view whose content guide no constraint names keeps the size it was given.
        #expect(scroll.contentSize == CGSize(width: 200, height: 900))
    }

    /// Reading the content guide with nothing constraining it leaves the size the app set: the
    /// guide's frame is that rectangle, and the offset stays (#375).
    @Test func anUnconstrainedContentGuideKeepsTheGivenSize() {
        let window = window()
        let scroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: 200, height: 300))
        scroll.contentSize = CGSize(width: 200, height: 900)
        window.addSubview(scroll)
        scroll.contentOffset = CGPoint(x: 0, y: 100)
        let badge = UIView()
        badge.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(badge)
        NSLayoutConstraint.activate([
            badge.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -10),
            badge.bottomAnchor.constraint(equalTo: scroll.frameLayoutGuide.bottomAnchor, constant: -10),
            badge.widthAnchor.constraint(equalToConstant: 20),
            badge.heightAnchor.constraint(equalToConstant: 20),
        ])
        _ = scroll.contentLayoutGuide
        window.layoutIfNeeded()
        #expect(scroll.contentSize == CGSize(width: 200, height: 900))
        #expect(scroll.contentLayoutGuide.layoutFrame == CGRect(x: 0, y: 0, width: 200, height: 900))
        #expect(scroll.contentOffset == CGPoint(x: 0, y: 100))
        #expect(badge.frame == CGRect(x: 170, y: 370, width: 20, height: 20))
    }

    /// The drag-delete prototype's keyboard: the attributes set are what is typed next, until
    /// the selection moves.
    @Test func typedTextTakesTheTypingAttributes() {
        _ = window()
        let view = UITextView(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
        let plain = UIFont.systemFont(ofSize: 17)
        let bold = UIFont.boldSystemFont(ofSize: 17)
        view.attributedText = NSAttributedString(string: "ab", attributes: [.font: plain])
        view.selectedRange = NSRange(location: 2, length: 0)
        #expect((view.typingAttributes[.font] as? UIFont) === plain)
        let red = UIColor.red
        view.typingAttributes = [.font: bold, .foregroundColor: red]
        view.insertText("cd")
        let text = view.attributedText!
        #expect(text.string == "abcd")
        #expect((text.attributes(at: 0, effectiveRange: nil)[.font] as? UIFont) === plain)
        #expect((text.attributes(at: 2, effectiveRange: nil)[.font] as? UIFont) === bold)
        #expect((text.attributes(at: 3, effectiveRange: nil)[.foregroundColor] as? UIColor) === red)
        // After the typed text the caret takes its attributes; a moved selection takes the
        // attributes of the text it lands in.
        #expect((view.typingAttributes[.font] as? UIFont) === bold)
        view.selectedRange = NSRange(location: 1, length: 0)
        #expect((view.typingAttributes[.font] as? UIFont) === plain)
    }

    @Test func scrollRangeToVisibleBringsTheEndIntoView() {
        let window = window()
        let view = UITextView(frame: CGRect(x: 0, y: 0, width: 200, height: 60))
        window.addSubview(view)
        view.text = (1...40).map { "line \($0)" }.joined(separator: "\n")
        window.layoutIfNeeded()
        view.contentSize = CGSize(width: 200, height: view.contentHeight(for: 200))
        #expect(view.contentOffset.y == 0)
        let length = (view.text ?? "").utf16.count
        view.scrollRangeToVisible(NSRange(location: length, length: 0))
        let caret = view.caretRect(for: UITextPosition(offset: length))
        #expect(view.contentOffset.y > 0)
        #expect(caret.maxY <= view.contentOffset.y + view.bounds.height + 0.5 && caret.minY >= view.contentOffset.y - 0.5)
    }

    /// The reading tracker's confetti: a cell's birth rate, lifetime, velocity and gravity.
    @Test func cellsEmitMoveAndRetireParticles() {
        _ = window()
        let layer = CAEmitterLayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 200, height: 200)
        layer.emitterPosition = CGPoint(x: 100, y: 0)
        layer.emitterShape = .line
        layer.emitterSize = CGSize(width: 200, height: 1)
        let cell = CAEmitterCell()
        cell.birthRate = 10
        cell.lifetime = 2
        cell.velocity = 50
        cell.emissionLongitude = .pi / 2   // down the screen
        cell.yAcceleration = 100
        layer.emitterCells = [cell]
        #expect(layer.isAnimating)
        layer.step(1)
        #expect(layer.particles.count == 10)
        for particle in layer.particles {
            #expect(particle.position.x >= 0 && particle.position.x <= 200)
            #expect(particle.position.y > 0 && particle.velocity.dy > 50)
        }
        // The first born is the farthest down; nothing outlives its two seconds.
        #expect(layer.particles[0].position.y > layer.particles[9].position.y)
        layer.step(1)
        #expect(layer.particles.count == 20)
        layer.birthRate = 0
        layer.step(2.5)
        #expect(layer.particles.isEmpty)
        #expect(!layer.isAnimating)
    }

    @Test func theSeedRepeatsTheParticles() {
        func run(seed: UInt32) -> [CGPoint] {
            let layer = CAEmitterLayer()
            layer.seed = seed
            layer.emitterShape = .circle
            layer.emitterMode = .outline
            layer.emitterSize = CGSize(width: 100, height: 100)
            layer.emitterPosition = CGPoint(x: 50, y: 50)
            let cell = CAEmitterCell()
            cell.birthRate = 20
            cell.lifetime = 5
            cell.emissionRange = .pi
            layer.emitterCells = [cell]
            layer.step(0.5)
            return layer.particles.map(\.position)
        }
        let first = run(seed: 7)
        #expect(first.count == 10)
        #expect(first == run(seed: 7))
        #expect(first != run(seed: 8))
        // On the outline: fifty points from the centre.
        for point in first {
            let distance = ((point.x - 50) * (point.x - 50) + (point.y - 50) * (point.y - 50)).squareRoot()
            #expect(abs(distance - 50) < 0.01)
        }
    }
}
