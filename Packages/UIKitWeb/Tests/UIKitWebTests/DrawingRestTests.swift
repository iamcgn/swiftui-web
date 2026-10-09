// uk-drawing-rest (Drawing/GraphicsContext.swift, StringDrawing.swift, CGPathBridge.swift):
// a view's drawing is recorded once and kept until it is invalidated, blend modes and `clear`
// become blend groups inside a group of the view's own, attributed strings draw their ranges
// with underlines and strikethroughs, and CGMutablePath builds paths on both platforms.
import Testing
import UIKit
import WebGraphicsHeadless
@testable import UIKitWebCore

@MainActor private final class CountingView: UIView {
    var draws = 0
    var blend = false
    override func draw(_ rect: CGRect) {
        draws += 1
        UIColor.systemBlue.setFill()
        UIRectFill(CGRect(x: 0, y: 0, width: 20, height: 20))
        if blend {
            UIColor.systemRed.setFill()
            UIBezierPath(ovalIn: CGRect(x: 10, y: 10, width: 20, height: 20)).fill(with: .multiply, alpha: 1)
            UIGraphicsGetCurrentContext()?.clear(CGRect(x: 0, y: 30, width: 10, height: 10))
        }
    }
}

@Suite @MainActor struct DrawingRestTests {
    private func scene() -> (UIKitScene, UIView) {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        scene.textEngine = try! Goldens.textEngine()
        scene.configureScreen(size: CGSize(width: 320, height: 300), scale: 2)
        let root = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 300))
        window.overrideUserInterfaceStyle = .light
        window.rootViewController = root
        window.makeKeyAndVisible()
        scene.layout(in: CGSize(width: 320, height: 300))
        return (scene, root.view)
    }

    private func kinds(_ list: DisplayList) -> [String] { list.commands.map { "\($0)".prefix { $0 != "(" }.description } }

    @Test func drawingIsCachedUntilInvalidated() {
        let (scene, root) = scene()
        let view = CountingView(frame: CGRect(x: 10, y: 10, width: 60, height: 60))
        view.backgroundColor = .clear
        root.addSubview(view)
        _ = scene.render(scale: 2)
        _ = scene.render(scale: 2)
        #expect(view.draws == 1)   // the second frame replays the recording
        // The recording is in the view's coordinates, replayed translated to its origin.
        func placement(_ list: DisplayList) -> CGPoint? {
            for command in list.commands {
                if case .fillPath(let path, _, _) = command, path.boundingRect.size == CGSize(width: 20, height: 20) { return path.boundingRect.origin }
            }
            return nil
        }
        #expect(placement(scene.render(scale: 2)) == CGPoint(x: 10, y: 10))
        view.setNeedsDisplay()
        _ = scene.render(scale: 2)
        #expect(view.draws == 2)
        view.frame.size.width = 80   // a new size draws again
        _ = scene.render(scale: 2)
        #expect(view.draws == 3)
        view.center.x += 10   // a move does not
        let moved = scene.render(scale: 2)
        #expect(view.draws == 3)
        #expect(placement(moved) == CGPoint(x: 20, y: 10))
        view.overrideUserInterfaceStyle = .dark   // another appearance draws again
        _ = scene.render(scale: 2)
        #expect(view.draws == 4)
    }

    @Test func blendModesGroupTheViewsPainting() {
        let (scene, root) = scene()
        let view = CountingView(frame: CGRect(x: 10, y: 10, width: 60, height: 60))
        view.backgroundColor = .systemYellow
        view.blend = true
        root.addSubview(view)
        let order = kinds(scene.render(scale: 2, background: false))
        // The view's own group opens before its background and holds the blend groups.
        let group = order.firstIndex(of: "beginGroup")!
        #expect(order[group + 1] == "fillRect" && order[group + 2] == "fillPath")   // the yellow background, then the recording
        let blends = scene.render(scale: 2, background: false).commands.compactMap { command -> (BlendMode, CGRect)? in
            if case .beginBlend(let mode, let bounds) = command { return (mode, bounds) } else { return nil }
        }
        #expect(blends.map(\.0) == [.multiply, .destinationOut])
        #expect(blends[0].1 == CGRect(x: 20, y: 20, width: 20, height: 20) && blends[1].1 == CGRect(x: 10, y: 40, width: 10, height: 10))
        #expect(order.filter { $0 == "endGroup" }.count >= 3)
        // Without blending the view's painting is not grouped.
        view.blend = false
        view.setNeedsDisplay()
        #expect(!kinds(scene.render(scale: 2, background: false)).contains("beginGroup"))
        #expect(UIGraphicsRecordingContext.blendMode(.copy) == nil && UIGraphicsRecordingContext.blendMode(.clear) == .destinationOut && UIGraphicsRecordingContext.blendMode(.plusLighter) == .plusLighter)
    }

    @Test func attributedRangesDrawWithDecorations() {
        let (scene, root) = scene()
        final class TextView: UIView {
            override func draw(_ rect: CGRect) {
                let text = NSMutableAttributedString(string: "Mixed runs under struck", attributes: [.font: UIFont.systemFont(ofSize: 17), .foregroundColor: UIColor.black])
                text.addAttributes([.font: UIFont.systemFont(ofSize: 17, weight: .semibold), .foregroundColor: UIColor.systemRed], range: NSRange(location: 0, length: 5))
                text.addAttributes([.underlineStyle: NSUnderlineStyle.single.rawValue, .foregroundColor: UIColor.systemBlue], range: NSRange(location: 11, length: 5))
                text.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue, .strikethroughColor: UIColor.systemRed], range: NSRange(location: 17, length: 6))
                text.draw(at: CGPoint(x: 10, y: 10))
            }
        }
        let view = TextView(frame: CGRect(x: 20, y: 20, width: 280, height: 40))
        view.backgroundColor = .clear
        root.addSubview(view)
        let list = scene.render(scale: 2, background: false)
        #expect((scene.textEngine as? RecordedTextEngine)?.misses.isEmpty == true, Comment(rawValue: "misses: \((scene.textEngine as? RecordedTextEngine)?.misses ?? [])"))
        let texts = list.commands.compactMap { command -> (String, Int, RGBA)? in
            if case .drawText(let text, let font, _, let color) = command { return (text, font.weight, color) } else { return nil }
        }
        #expect(texts.map(\.0).joined() == "Mixed runs under struck" && texts.count >= 4)   // the engine may split a run at a space
        guard texts.count >= 4 else { return }
        #expect(texts[0].1 == 600 && texts[1].1 == 400 && texts[0].2.red > 0.9 && texts[2].2.blue > 0.9)
        let lines = list.commands.compactMap { command -> (CGRect, RGBA)? in
            if case .fillRect(let rect, let color) = command { return (rect, color) } else { return nil }
        }
        #expect(lines.count >= 2)   // the underline, then the strikethrough (one per fragment)
        guard lines.count >= 2, let last = lines.last else { return }
        let baseline = 10 + UIFont.systemFont(ofSize: 17).ascender   // string drawing records under its own concat, in the view's coordinates
        #expect(lines[0].0.height == 1 && lines[0].0.minY == baseline + 2 && lines[0].1.blue > 0.9)   // under "under", in its colour
        #expect(last.0.minY < baseline - 3 && last.0.minY > baseline - 6 && last.1.red > 0.9)   // through "struck", in red
        #expect(NSMutableAttributedString(string: "ab").length == 2)
    }

    @Test func cgPathsBuildSubstratePaths() {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: 40, y: 0))
        path.addArc(center: CGPoint(x: 40, y: 20), radius: 20, startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: false)
        path.closeSubpath()
        var transform = CGAffineTransform(translationX: 100, y: 0)
        let box = CGPath(rect: CGRect(x: 0, y: 0, width: 10, height: 10), transform: &transform)
        path.addPath(box)
        let bezier = UIBezierPath(cgPath: path)
        #expect(bezier.bounds.minX == 0 && bezier.bounds.maxX == 110 && abs(bezier.bounds.maxY - 40) < 0.01)
        #expect(bezier.cgPath.contains(CGPoint(x: 50, y: 20)) && bezier.cgPath.contains(CGPoint(x: 105, y: 5)) && !bezier.cgPath.contains(CGPoint(x: 80, y: 5)))
        let (scene, root) = scene()
        final class PathView: UIView {
            let path: CGPath
            init(path: CGPath, frame: CGRect) { self.path = path; super.init(frame: frame) }
            override func draw(_ rect: CGRect) {
                guard let context = UIGraphicsGetCurrentContext() else { return }
                context.addPath(path)
                context.setFillColor(UIColor.systemTeal.cgColor)
                context.fillPath()
            }
        }
        let view = PathView(path: path, frame: CGRect(x: 10, y: 10, width: 200, height: 60))
        view.backgroundColor = .clear
        root.addSubview(view)
        let fills = scene.render(scale: 2, background: false).commands.compactMap { command -> Path? in if case .fillPath(let p, _, _) = command { return p } else { return nil } }
        #expect(fills.count == 1 && fills[0].boundingRect.minX == 10 && fills[0].boundingRect.maxX == 120)
    }
}
