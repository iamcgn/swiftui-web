// Custom drawing (Docs/elements/UIKit/Drawing.md): a view's `draw(_:)` through UIBezierPath, the
// current fill and stroke colours, and the current graphics context's transforms, clipping and
// shadows. Compared by pixels (the frames are the views' own).
#if canImport(UIKit)
import UIKit
import UIKitFixtureKit

/// Shapes through UIBezierPath and UIColor: a rounded rectangle, a stroked circle, a triangle,
/// a dashed line, an even-odd ring.
final class ShapesView: UIView {
    override func draw(_ rect: CGRect) {
        UIColor.systemBlue.setFill()
        UIBezierPath(roundedRect: CGRect(x: 10, y: 10, width: 100, height: 60), cornerRadius: 12).fill()

        UIColor.systemGreen.setStroke()
        let circle = UIBezierPath(ovalIn: CGRect(x: 130, y: 10, width: 60, height: 60))
        circle.lineWidth = 4
        circle.stroke()

        UIColor.systemOrange.setFill()
        let triangle = UIBezierPath()
        triangle.move(to: CGPoint(x: 210, y: 70))
        triangle.addLine(to: CGPoint(x: 240, y: 10))
        triangle.addLine(to: CGPoint(x: 270, y: 70))
        triangle.close()
        triangle.fill()

        UIColor.systemRed.setStroke()
        let dashed = UIBezierPath()
        dashed.move(to: CGPoint(x: 10, y: 100))
        dashed.addLine(to: CGPoint(x: 270, y: 100))
        dashed.lineWidth = 2
        dashed.setLineDash([8, 4], count: 2, phase: 0)
        dashed.stroke()

        UIColor.systemPurple.setFill()
        let ring = UIBezierPath(ovalIn: CGRect(x: 10, y: 120, width: 60, height: 60))
        ring.append(UIBezierPath(ovalIn: CGRect(x: 25, y: 135, width: 30, height: 30)))
        ring.usesEvenOddFillRule = true
        ring.fill()
    }
}

/// The graphics context: a translated and rotated square, a clipped fill, a shadowed rectangle,
/// a stroked rect through `stroke(_:width:)`.
final class ContextView: UIView {
    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.saveGState()
        context.translateBy(x: 60, y: 50)
        context.rotate(by: .pi / 8)
        context.setFillColor(UIColor.systemTeal.cgColor)
        context.fill(CGRect(x: -25, y: -25, width: 50, height: 50))
        context.restoreGState()

        context.saveGState()
        context.addEllipse(in: CGRect(x: 120, y: 10, width: 80, height: 80))
        context.clip()
        context.setFillColor(UIColor.systemIndigo.cgColor)
        context.fill(CGRect(x: 120, y: 10, width: 40, height: 80))
        context.setFillColor(UIColor.systemYellow.cgColor)
        context.fill(CGRect(x: 160, y: 10, width: 40, height: 80))
        context.restoreGState()

        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: 4), blur: 6, color: UIColor.black.withAlphaComponent(0.4).cgColor)
        context.setFillColor(UIColor.white.cgColor)
        context.fill(CGRect(x: 220, y: 20, width: 60, height: 60))
        context.restoreGState()

        context.setStrokeColor(UIColor.systemPink.cgColor)
        context.stroke(CGRect(x: 20, y: 110, width: 260, height: 40), width: 3)

        context.setStrokeColor(UIColor.systemGray.cgColor)
        context.setLineWidth(6)
        context.setLineCap(.round)
        context.move(to: CGPoint(x: 30, y: 170))
        context.addLine(to: CGPoint(x: 120, y: 170))
        context.strokePath()
    }
}


/// Strings, attributed strings and images drawn in `draw(_:)`: a semibold title with a line under
/// its measured width, right-aligned and centred lines in a rect, an attributed string, wrapped
/// text in a narrow rect, a rotated string, a tinted symbol scaled into a rect.
final class TextDrawingView: UIView {
    override func draw(_ rect: CGRect) {
        let title = "Hello, drawing"
        let titleAttributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 20, weight: .semibold), .foregroundColor: UIColor.systemBlue]
        title.draw(at: CGPoint(x: 10, y: 10), withAttributes: titleAttributes)
        let measured = title.size(withAttributes: titleAttributes)
        UIColor.systemBlue.setStroke()
        let underline = UIBezierPath()
        underline.move(to: CGPoint(x: 10, y: 10 + measured.height + 2))
        underline.addLine(to: CGPoint(x: 10 + measured.width, y: 10 + measured.height + 2))
        underline.lineWidth = 2
        underline.stroke()

        let right = NSMutableParagraphStyle()
        right.alignment = .right
        "Right aligned".draw(in: CGRect(x: 10, y: 50, width: 260, height: 30), withAttributes: [.font: UIFont.systemFont(ofSize: 17), .foregroundColor: UIColor.label, .paragraphStyle: right])
        let centre = NSMutableParagraphStyle()
        centre.alignment = .center
        "Centred".draw(in: CGRect(x: 10, y: 80, width: 260, height: 30), withAttributes: [.font: UIFont.systemFont(ofSize: 17), .foregroundColor: UIColor.secondaryLabel, .paragraphStyle: centre])

        NSAttributedString(string: "Attributed", attributes: [.font: UIFont.boldSystemFont(ofSize: 15), .foregroundColor: UIColor.systemRed]).draw(at: CGPoint(x: 10, y: 120))

        "The quick brown fox jumps over the lazy dog".draw(in: CGRect(x: 10, y: 150, width: 150, height: 80), withAttributes: [.font: UIFont.systemFont(ofSize: 15), .foregroundColor: UIColor.label])

        if let context = UIGraphicsGetCurrentContext() {
            context.saveGState()
            context.translateBy(x: 180, y: 200)
            context.rotate(by: -.pi / 12)
            "Tilted".draw(at: .zero, withAttributes: [.font: UIFont.systemFont(ofSize: 17, weight: .medium), .foregroundColor: UIColor.systemPurple])
            context.restoreGState()
        }

        UIImage(systemName: "star.fill")?.withTintColor(.systemYellow).draw(in: CGRect(x: 200, y: 10, width: 40, height: 40))
    }
}

public enum DrawFixtures {
    public static let all = [basic, text]

    public static let basic = UIKitFixture("uikit/draw/basic", size: CGSize(width: 320, height: 420)) {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 420))
        let shapes = ShapesView(frame: CGRect(x: 20, y: 10, width: 280, height: 190))
        shapes.backgroundColor = .clear
        root.addSubview(shapes.probe("shapes"))
        let context = ContextView(frame: CGRect(x: 20, y: 210, width: 280, height: 190))
        context.backgroundColor = .clear
        root.addSubview(context.probe("context"))
        return root
    }

    public static let text = UIKitFixture("uikit/draw/text", size: CGSize(width: 320, height: 260)) {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 260))
        let view = TextDrawingView(frame: CGRect(x: 20, y: 10, width: 280, height: 240))
        view.backgroundColor = .clear
        root.addSubview(view.probe("text"))
        return root
    }
}
#endif
