// uk-layers (Layers/CALayer.swift, CAGradientLayer and CATextLayer): the gradient layer's
// kinds map to the substrate's gradients with Core Animation's conventions (unit points,
// even locations, the radial ellipse, the conic's start toward the end point), and the text
// layer draws Helvetica from its top edge, centred when asked, wrapped when asked.
import Testing
import UIKit
import WebGraphicsHeadless
@testable import UIKitWebCore

@Suite @MainActor struct LayerContentTests {
    private func render(_ build: (UIView) -> Void) -> ([DisplayCommand], RecordedTextEngine) {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        let engine = try! Goldens.textEngine()
        scene.textEngine = engine
        scene.configureScreen(size: CGSize(width: 320, height: 300), scale: 2)
        let root = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 300))
        window.overrideUserInterfaceStyle = .light
        window.rootViewController = root
        window.makeKeyAndVisible()
        build(root.view)
        scene.layout(in: CGSize(width: 320, height: 300))
        return (scene.render(scale: 2, background: false).commands, engine)
    }

    private func gradients(_ commands: [DisplayCommand]) -> [DisplayGradient] {
        commands.compactMap { if case .fillGradient(_, let gradient, _) = $0 { return gradient } else { return nil } }
    }

    @Test func gradientKinds() {
        let (commands, _) = render { root in
            let axial = CAGradientLayer()
            axial.frame = CGRect(x: 10, y: 10, width: 100, height: 50)
            axial.colors = [UIColor.red.cgColor, UIColor.green.cgColor, UIColor.blue.cgColor]
            root.layer.addSublayer(axial)
            let radial = CAGradientLayer()
            radial.frame = CGRect(x: 10, y: 100, width: 100, height: 50)
            radial.type = .radial
            radial.colors = [UIColor.white.cgColor, UIColor.black.cgColor]
            radial.startPoint = CGPoint(x: 0.5, y: 0.5)
            radial.endPoint = CGPoint(x: 1, y: 1)
            root.layer.addSublayer(radial)
            let conic = CAGradientLayer()
            conic.frame = CGRect(x: 10, y: 200, width: 100, height: 50)
            conic.type = .conic
            conic.colors = [UIColor.red.cgColor, UIColor.blue.cgColor]
            conic.locations = [0.2, 0.8]
            conic.startPoint = CGPoint(x: 0.5, y: 0.5)
            conic.endPoint = CGPoint(x: 0.5, y: 1)
            root.layer.addSublayer(conic)
            let empty = CAGradientLayer()
            empty.frame = CGRect(x: 200, y: 10, width: 50, height: 50)
            root.layer.addSublayer(empty)
        }
        let found = gradients(commands)
        #expect(found.count == 3)   // the layer without colours paints nothing
        guard found.count == 3 else { return }
        // Axial: top centre to bottom centre by default, evenly spaced stops.
        if case .linear(let start, let end) = found[0].kind {
            #expect(start == CGPoint(x: 60, y: 10) && end == CGPoint(x: 60, y: 60))
        } else { Issue.record("axial is not linear") }
        #expect(found[0].stops.map { $0.location } == [0, 0.5, 1])
        // Radial: a circle of the end point's x offset, scaled to the y offset's ellipse.
        if case .radial(let center, let startRadius, let endRadius) = found[1].kind {
            #expect(center == CGPoint(x: 60, y: 125) && startRadius == 0 && endRadius == 50)
        } else { Issue.record("radial is not radial") }
        let radialIndex = commands.firstIndex { if case .fillGradient(_, let g, _) = $0 { return g == found[1] } else { return false } }!
        if case .concat(let transform) = commands[radialIndex - 1] {
            #expect(abs(transform.d - 0.5) < 1e-9 && transform.a == 1)   // 25 / 50
        } else { Issue.record("no ellipse scale") }
        // Conic: starts toward the end point (straight down), keeps the given locations.
        if case .angular(let center, let startAngle) = found[2].kind {
            #expect(center == CGPoint(x: 60, y: 225) && abs(startAngle - .pi / 2) < 1e-9)
        } else { Issue.record("conic is not angular") }
        #expect(found[2].stops.map { $0.location } == [0.2, 0.8])
    }

    @Test func textLayersDrawHelveticaFromTheTop() {
        let (commands, engine) = render { root in
            let text = CATextLayer()
            text.frame = CGRect(x: 16, y: 20, width: 140, height: 30)
            text.string = "Text layer"
            text.fontSize = 20
            text.foregroundColor = UIColor.black.cgColor
            root.layer.addSublayer(text)
            let centred = CATextLayer()
            centred.frame = CGRect(x: 16, y: 60, width: 140, height: 24)
            centred.string = "Centred"
            centred.fontSize = 14
            centred.alignmentMode = .center
            centred.foregroundColor = UIColor.systemBlue.cgColor
            root.layer.addSublayer(centred)
            let wrapped = CATextLayer()
            wrapped.frame = CGRect(x: 172, y: 20, width: 120, height: 60)
            wrapped.string = "Wrapped text layer in a narrow box"
            wrapped.fontSize = 13
            wrapped.isWrapped = true
            wrapped.foregroundColor = UIColor.darkGray.cgColor
            root.layer.addSublayer(wrapped)
        }
        let texts = commands.compactMap { command -> (String, DisplayFont, CGPoint, RGBA)? in
            if case .drawText(let text, let font, let origin, let color) = command { return (text, font, origin, color) } else { return nil }
        }
        #expect(engine.misses.isEmpty, Comment(rawValue: "unrecorded: " + engine.misses.joined(separator: ", ")))
        #expect(texts.count == 3)
        guard let first = texts.first(where: { $0.0 == "Text layer" }) else { Issue.record("no text"); return }
        #expect(first.1.family.lowercased().contains("helvetica") && first.1.size == 20)
        #expect(first.2.x == 16 && first.2.y > 20 && first.2.y < 40)   // the baseline sits below the top edge
        guard let centred = texts.first(where: { $0.0 == "Centred" }) else { Issue.record("no centred text"); return }
        #expect(centred.2.x > 16 + 30 && centred.2.x < 16 + 70 && centred.3.blue > 0.9)
        // The wrapped layer lays its string out to its width (the recorded engine keeps the
        // lines together; the browser and native engines break them).
        guard let wrapped = texts.first(where: { $0.1.size == 13 }) else { Issue.record("no wrapped text"); return }
        #expect(wrapped.2.x == 172 && wrapped.2.y > 20 && wrapped.2.y < 36)
    }
}
