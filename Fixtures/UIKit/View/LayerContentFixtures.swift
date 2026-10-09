// CAGradientLayer and CATextLayer (uk-layers, Docs/elements/UIKit/Animation.md): axial,
// radial and conic gradients with locations and end points, and text layers at two sizes,
// alignments and a wrapped one, as sublayers of plain views.
#if canImport(UIKit)
import UIKit
import UIKitFixtureKit

public enum LayerContentFixtures {
    public static let all = [content]

    public static let content = UIKitFixture("uikit/layer/content", size: CGSize(width: 320, height: 300)) {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 300))
        root.backgroundColor = .white

        @MainActor func host(_ layer: CALayer, frame: CGRect, probe: String) {
            let view = UIView(frame: frame)
            layer.frame = view.bounds
            view.layer.addSublayer(layer)
            root.addSubview(view.probe(probe))
        }
        let axial = CAGradientLayer()
        axial.colors = [UIColor.systemBlue.cgColor, UIColor.systemPurple.cgColor, UIColor.systemPink.cgColor]
        axial.locations = [0, 0.3, 1]
        axial.startPoint = CGPoint(x: 0, y: 0)
        axial.endPoint = CGPoint(x: 1, y: 1)
        host(axial, frame: CGRect(x: 16, y: 16, width: 120, height: 80), probe: "axial")

        let vertical = CAGradientLayer()
        vertical.colors = [UIColor.systemYellow.cgColor, UIColor.systemOrange.cgColor]
        host(vertical, frame: CGRect(x: 152, y: 16, width: 152, height: 80), probe: "vertical")

        let radial = CAGradientLayer()
        radial.type = .radial
        radial.colors = [UIColor.white.cgColor, UIColor.systemTeal.cgColor]
        radial.startPoint = CGPoint(x: 0.5, y: 0.5)
        radial.endPoint = CGPoint(x: 1, y: 1)
        host(radial, frame: CGRect(x: 16, y: 112, width: 120, height: 80), probe: "radial")

        let conic = CAGradientLayer()
        conic.type = .conic
        conic.colors = [UIColor.systemRed.cgColor, UIColor.systemGreen.cgColor, UIColor.systemRed.cgColor]
        conic.startPoint = CGPoint(x: 0.5, y: 0.5)
        conic.endPoint = CGPoint(x: 1, y: 0.5)
        host(conic, frame: CGRect(x: 152, y: 112, width: 152, height: 80), probe: "conic")

        let text = CATextLayer()
        text.string = "Text layer"
        text.fontSize = 20
        text.foregroundColor = UIColor.label.cgColor
        text.contentsScale = 2
        host(text, frame: CGRect(x: 16, y: 208, width: 140, height: 30), probe: "text")

        let centred = CATextLayer()
        centred.string = "Centred"
        centred.fontSize = 14
        centred.alignmentMode = .center
        centred.foregroundColor = UIColor.systemBlue.cgColor
        centred.contentsScale = 2
        host(centred, frame: CGRect(x: 16, y: 246, width: 140, height: 24), probe: "centred")

        let wrapped = CATextLayer()
        wrapped.string = "Wrapped text layer in a narrow box"
        wrapped.fontSize = 13
        wrapped.isWrapped = true
        wrapped.foregroundColor = UIColor.secondaryLabel.cgColor
        wrapped.contentsScale = 2
        host(wrapped, frame: CGRect(x: 172, y: 208, width: 120, height: 60), probe: "wrapped")
        return root
    }
}
#endif
