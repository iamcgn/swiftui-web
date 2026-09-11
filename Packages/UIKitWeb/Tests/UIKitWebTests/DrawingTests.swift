// Custom drawing (Drawing/GraphicsContext.swift, UIBezierPath.swift): `draw(_:)` records into
// the display list at the view's origin through the current transform, state saves and
// restores nest, clips and shadows close.
import Testing
import UIKit

@Suite @MainActor struct DrawingTests {
    final class Drawer: UIView {
        var body: (@MainActor (UIGraphicsRecordingContext) -> Void)?
        override func draw(_ rect: CGRect) {
            if let context = UIGraphicsGetCurrentContext() { body?(context) }
        }
    }

    private func render(_ body: @escaping @MainActor (UIGraphicsRecordingContext) -> Void) -> [String] {
        UIKitScene.shared.removeAllWindows()
        UIKitScene.shared.configureScreen(size: CGSize(width: 200, height: 200), scale: 2)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        let view = Drawer(frame: CGRect(x: 10, y: 20, width: 100, height: 100))
        view.body = body
        window.addSubview(view)
        window.makeKeyAndVisible()
        UIKitScene.shared.layout(in: CGSize(width: 200, height: 200))
        return UIKitScene.shared.render(scale: 2, background: false).commands.map(\.description)
    }

    @Test func fillsInTheViewsCoordinates() {
        let commands = render { context in
            UIColor.red.setFill()
            UIRectFill(CGRect(x: 5, y: 5, width: 20, height: 10))
            context.setStrokeColor(red: 0, green: 0, blue: 1, alpha: 1)
            context.setLineWidth(3)
            context.stroke(CGRect(x: 0, y: 0, width: 50, height: 50))
        }
        #expect(commands.contains { $0.hasPrefix("fillPath(") && $0.contains("#FF0000") })
        #expect(commands.contains { $0.hasPrefix("strokePath(") && $0.contains("w=3") && $0.contains("#0000FF") })
    }

    @Test func statesNestAndClose() {
        let commands = render { context in
            context.saveGState()
            context.translateBy(x: 10, y: 10)
            context.setShadow(offset: CGSize(width: 0, height: 2), blur: 4, color: UIColor.black.cgColor)
            context.addRect(CGRect(x: 0, y: 0, width: 10, height: 10))
            context.clip()
            context.setFillColor(gray: 0.5, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
            context.restoreGState()
            context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        let saves = commands.filter { $0 == "save" }.count
        let restores = commands.filter { $0 == "restore" }.count
        #expect(saves == restores)
        let shadows = commands.filter { $0.hasPrefix("beginShadow") }.count
        let ends = commands.filter { $0 == "endGroup" }.count
        #expect(shadows == 1 && ends >= shadows)
        #expect(commands.contains { $0.hasPrefix("clipPath") })
        // A fill after the restore is unshadowed and unclipped: the last command is a plain fill.
        #expect(commands.last?.hasPrefix("fillPath") == true)
    }

    @Test func bezierPathsBuildAndPaint() {
        let path = UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: 40, height: 20), cornerRadius: 5)
        #expect(path.bounds == CGRect(x: 0, y: 0, width: 40, height: 20))
        path.move(to: CGPoint(x: 50, y: 50))
        path.addLine(to: CGPoint(x: 60, y: 60))
        #expect(path.currentPoint == CGPoint(x: 60, y: 60))
        let commands = render { _ in
            UIColor.green.setStroke()
            path.lineWidth = 2
            path.stroke()
        }
        #expect(commands.contains { $0.hasPrefix("strokePath(") && $0.contains("w=2") && $0.contains("#00FF00") })
    }
}
