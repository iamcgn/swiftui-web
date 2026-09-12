// Custom drawing (Drawing/GraphicsContext.swift, UIBezierPath.swift): `draw(_:)` records into
// the display list at the view's origin through the current transform, state saves and
// restores nest, clips and shadows close.
import Testing
import UIKit
#if canImport(AppKit)
import WebGraphicsNative
#endif

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

    /// String and image drawing (Drawing/StringDrawing.swift): text lands as drawText commands
    /// under a concat of the context's transform, at the view's origin plus the point; an alpha
    /// wraps an image in a group.
    @Test func drawsStringsAndImagesThroughTheTransform() throws {
        #if canImport(AppKit)
        UIKitScene.shared.textEngine = CoreTextEngine()
        #endif
        defer { UIKitScene.shared.textEngine = try! Goldens.textEngine() }
        let commands = render { context in
            "Hi".draw(at: CGPoint(x: 5, y: 7), withAttributes: [.font: UIFont.systemFont(ofSize: 17), .foregroundColor: UIColor.red])
            context.translateBy(x: 20, y: 0)
            NSAttributedString(string: "There", attributes: [.font: UIFont.boldSystemFont(ofSize: 15)]).draw(at: .zero)
            context.setAlpha(0.5)
            UIImage(systemName: "star.fill")?.draw(in: CGRect(x: 0, y: 30, width: 20, height: 20))
        }
        #if canImport(AppKit)
        let texts = commands.filter { $0.hasPrefix("drawText(") }
        #expect(texts.count == 2, "\(commands)")
        // The first string is red at (5, 7 + ascender) inside a concat translating by the view's origin (10, 20).
        #expect(texts.first?.contains("\"Hi\"") == true && texts.first?.contains("#FF0000") == true)
        let concats = commands.filter { $0.hasPrefix("concat(") }
        #expect(concats.first == "concat(1, 0, 0, 1, 10, 20)", "\(concats)")
        #expect(concats.dropFirst().first == "concat(1, 0, 0, 1, 30, 20)", "\(concats)")
        #endif
        #expect(commands.contains { $0.hasPrefix("beginGroup(opacity: 0.5") })
        let measured = "Hi".size(withAttributes: [.font: UIFont.systemFont(ofSize: 17)])
        #if canImport(AppKit)
        #expect(measured.width > 10 && measured.height > 15)
        #else
        #expect(measured.height >= 0)
        #endif
    }

    @Test func gradientsFillTheClippedRegionThroughTheTransform() {
        let commands = render { context in
            let space = CGColorSpaceCreateDeviceRGB()
            let linear = CGGradient(colorsSpace: space, colors: [UIColor.red.cgColor, UIColor.blue.cgColor] as CFArray, locations: [0, 1])!
            context.saveGState()
            context.clip(to: CGRect(x: 0, y: 0, width: 50, height: 20))
            context.drawLinearGradient(linear, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 50, y: 0), options: [])
            context.restoreGState()
            context.translateBy(x: 10, y: 10)
            context.setAlpha(0.5)
            let radial = CGGradient(colorsSpace: space, colors: [UIColor.white.cgColor, UIColor.black.cgColor] as CFArray, locations: [0, 1])!
            context.drawRadialGradient(radial, startCenter: CGPoint(x: 5, y: 5), startRadius: 2, endCenter: CGPoint(x: 10, y: 10), endRadius: 20, options: [])
        }
        let gradients = commands.filter { $0.hasPrefix("fillGradient(") }
        #expect(gradients.count == 2, "\(commands)")
        // The linear band lands after the clip, its points at the view's origin (10, 20).
        #expect(commands.firstIndex { $0.hasPrefix("clipPath(") }! < commands.firstIndex { $0.hasPrefix("fillGradient(") }!)
        #expect(gradients[0].contains("linear 10.0,20.0→60.0,20.0") && gradients[0].contains("0.0:FF0000") && gradients[0].contains("1.0:0000FF"), "\(gradients[0])")
        // The radial one: two circles through the translation, an even-odd region outside the start circle, half alpha.
        #expect(gradients[1].contains(" eo ") && gradients[1].contains("radial 25.0,35.0 r2.0→30.0,40.0 r20.0"), "\(gradients[1])")
        #expect(gradients[1].contains("FFFFFF") && gradients[1].contains("000000"))
    }

    @Test func imageRenderersRecordAndReplay() throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 10))
        let badge = renderer.image { context in
            UIColor.green.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 20, height: 10))
            UIColor.white.setStroke()
            UIBezierPath(rect: CGRect(x: 2, y: 2, width: 16, height: 6)).stroke()
        }
        #expect(badge.size == CGSize(width: 20, height: 10))
        #expect(badge.drawing?.commands.count == 2)
        #expect(UIGraphicsGetCurrentContext() == nil)
        let commands = render { context in
            badge.draw(at: CGPoint(x: 5, y: 5))
            badge.draw(in: CGRect(x: 0, y: 30, width: 40, height: 20))
        }
        let concats = commands.filter { $0.hasPrefix("concat(") }
        // Each draw: the context's transform (the view at 10, 20), then the image's placement and scale.
        #expect(concats == ["concat(1, 0, 0, 1, 10, 20)", "concat(1, 0, 0, 1, 5, 5)", "concat(1, 0, 0, 1, 10, 20)", "concat(2, 0, 0, 2, 0, 30)"], "\(concats)")
        #expect(commands.filter { $0.hasPrefix("fillPath(") && $0.contains("#00FF00") }.count == 2)
        #expect(commands.filter { $0.hasPrefix("strokePath(") && $0.contains("#FFFFFF") }.count == 2)

        // The older functions record the same way, and the image view draws the recording too.
        UIGraphicsBeginImageContextWithOptions(CGSize(width: 8, height: 8), false, 0)
        UIColor.red.setFill()
        UIRectFill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let square = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        #expect(square?.size == CGSize(width: 8, height: 8) && square?.drawing?.commands.count == 1)
        #expect(UIGraphicsGetImageFromCurrentImageContext() == nil)
        let imageView = UIImageView(image: square)
        #expect(imageView.intrinsicContentSize == CGSize(width: 8, height: 8))
        UIKitScene.shared.removeAllWindows()
        UIKitScene.shared.configureScreen(size: CGSize(width: 200, height: 200), scale: 2)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        imageView.frame = CGRect(x: 3, y: 4, width: 8, height: 8)
        window.addSubview(imageView)
        window.makeKeyAndVisible()
        UIKitScene.shared.layout(in: CGSize(width: 200, height: 200))
        let painted = UIKitScene.shared.render(scale: 2, background: false).commands.map(\.description)
        let placement = try #require(painted.firstIndex(of: "concat(1, 0, 0, 1, 3, 4)"), "\(painted)")
        #expect(painted[placement - 1] == "save" && painted[placement + 2] == "restore")
        #expect(painted[placement + 1].hasPrefix("fillPath(") && painted[placement + 1].contains("#FF0000"), "\(painted[placement + 1])")
    }
}
