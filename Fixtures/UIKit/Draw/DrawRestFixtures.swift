// Custom drawing, the rest (uk-drawing-rest, Docs/elements/UIKit/Drawing.md): blend modes on
// paths and images, `clear`, attributed strings with ranges, underlines and strikethroughs,
// and paths built with CGMutablePath. Compared by pixels.
#if canImport(UIKit)
import UIKit
import UIKitFixtureKit

/// Blend modes: circles multiplied, screened and differenced over a blue ground, a badge
/// multiplied over orange, a rectangle cleared out of the view's yellow background (the grey
/// band behind the view shows through).
final class BlendView: UIView {
    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        UIColor.systemBlue.setFill()
        UIRectFill(CGRect(x: 10, y: 10, width: 200, height: 60))
        UIColor.systemRed.setFill()
        UIBezierPath(ovalIn: CGRect(x: 20, y: 30, width: 60, height: 60)).fill(with: .multiply, alpha: 1)
        UIColor.systemGreen.setFill()
        UIBezierPath(ovalIn: CGRect(x: 90, y: 30, width: 60, height: 60)).fill(with: .screen, alpha: 1)
        UIColor.systemYellow.setFill()
        UIBezierPath(ovalIn: CGRect(x: 160, y: 30, width: 60, height: 60)).fill(with: .difference, alpha: 1)
        context.saveGState()
        context.setBlendMode(.multiply)
        UIColor.systemOrange.setFill()
        UIRectFill(CGRect(x: 230, y: 10, width: 40, height: 80))
        context.restoreGState()
        UIColor.systemOrange.setFill()
        UIRectFill(CGRect(x: 10, y: 100, width: 60, height: 60))
        UIKitFixtureImage.named("badge")?.draw(in: CGRect(x: 20, y: 110, width: 40, height: 40), blendMode: .multiply, alpha: 1)
        UIKitFixtureImage.named("badge")?.draw(in: CGRect(x: 80, y: 110, width: 40, height: 40), blendMode: .normal, alpha: 0.5)
        context.clear(CGRect(x: 140, y: 100, width: 60, height: 60))
        UIColor.systemPurple.setFill()
        UIBezierPath(ovalIn: CGRect(x: 220, y: 100, width: 60, height: 60)).fill(with: .plusLighter, alpha: 0.8)
    }
}

/// Attributed strings with several ranges: fonts and colours per range, an underlined range
/// and a struck one (in their own colours or the text's), a mutable string built by appending.
final class AttributedDrawingView: UIView {
    override func draw(_ rect: CGRect) {
        let mixed = NSMutableAttributedString(string: "Mixed runs under struck", attributes: [.font: UIFont.systemFont(ofSize: 17), .foregroundColor: UIColor.black])
        mixed.addAttributes([.font: UIFont.systemFont(ofSize: 17, weight: .semibold), .foregroundColor: UIColor.systemRed], range: NSRange(location: 0, length: 5))
        mixed.addAttributes([.underlineStyle: NSUnderlineStyle.single.rawValue, .foregroundColor: UIColor.systemBlue], range: NSRange(location: 11, length: 5))
        mixed.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue, .strikethroughColor: UIColor.systemRed], range: NSRange(location: 17, length: 6))
        mixed.draw(at: CGPoint(x: 10, y: 10))
        let built = NSMutableAttributedString(string: "Small ", attributes: [.font: UIFont.systemFont(ofSize: 13), .foregroundColor: UIColor.darkGray])
        built.append(NSAttributedString(string: "and big", attributes: [.font: UIFont.systemFont(ofSize: 24, weight: .bold), .foregroundColor: UIColor.systemGreen, .underlineStyle: NSUnderlineStyle.single.rawValue, .underlineColor: UIColor.systemOrange]))
        built.draw(at: CGPoint(x: 10, y: 44))
        let wrapped = NSAttributedString(string: "Underlined words wrap in a narrow rect", attributes: [.font: UIFont.systemFont(ofSize: 15), .foregroundColor: UIColor.black, .underlineStyle: NSUnderlineStyle.single.rawValue])
        wrapped.draw(in: CGRect(x: 160, y: 44, width: 110, height: 60))
    }
}

/// Paths built with CGMutablePath: a star through `UIBezierPath(cgPath:)`, an arc path added
/// to the context, a transformed rectangle.
final class CGPathView: UIView {
    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let star = CGMutablePath()
        for index in 0..<5 {
            // The points of a pentagram: a radius turned by multiples of 144° (no trig on wasm).
            let angle = CGFloat(index) * 4 * .pi / 5 - .pi / 2
            let point = CGPoint(x: 36, y: 0).applying(CGAffineTransform(rotationAngle: angle)).applying(CGAffineTransform(translationX: 50, y: 46))
            if index == 0 { star.move(to: point) } else { star.addLine(to: point) }
        }
        star.closeSubpath()
        UIColor.systemYellow.setFill()
        let bezier = UIBezierPath(cgPath: star)
        bezier.usesEvenOddFillRule = true
        bezier.fill()
        let arc = CGMutablePath()
        arc.move(to: CGPoint(x: 120, y: 80))
        arc.addArc(center: CGPoint(x: 150, y: 80), radius: 30, startAngle: .pi, endAngle: 0, clockwise: false)
        arc.addLine(to: CGPoint(x: 150, y: 20))
        arc.closeSubpath()
        context.addPath(arc)
        context.setFillColor(UIColor.systemTeal.cgColor)
        context.setStrokeColor(UIColor.black.cgColor)
        context.setLineWidth(2)
        context.drawPath(using: .fillStroke)
        var transform = CGAffineTransform(translationX: 210, y: 20).rotated(by: .pi / 8)
        let box = CGPath(rect: CGRect(x: 0, y: 0, width: 50, height: 50), transform: &transform)
        let combined = CGMutablePath()
        combined.addPath(box)
        combined.addEllipse(in: CGRect(x: 215, y: 30, width: 30, height: 30))
        context.addPath(combined)
        context.setFillColor(UIColor.systemPink.cgColor)
        context.fillPath(using: .evenOdd)
    }
}

public enum DrawRestFixtures {
    public static let all = [rest]

    public static let rest = UIKitFixture("uikit/draw/rest", size: CGSize(width: 320, height: 420)) {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 420))
        let band = UIView(frame: CGRect(x: 0, y: 100, width: 320, height: 80))
        band.backgroundColor = .systemGray4
        root.addSubview(band)
        let blend = BlendView(frame: CGRect(x: 20, y: 10, width: 280, height: 170))
        blend.backgroundColor = .systemYellow.withAlphaComponent(0.5)
        root.addSubview(blend.probe("blend"))
        let attributed = AttributedDrawingView(frame: CGRect(x: 20, y: 190, width: 280, height: 110))
        attributed.backgroundColor = .clear
        root.addSubview(attributed.probe("attributed"))
        let paths = CGPathView(frame: CGRect(x: 20, y: 310, width: 280, height: 100))
        paths.backgroundColor = .clear
        root.addSubview(paths.probe("paths"))
        return root
    }
}
#endif
