// UIVisualEffectView (uk-materials, Docs/elements/UIKit/UIView.md): the system materials and
// the plain blur styles over black, blue, white and red bands, so each tint can be read from
// the golden; a vibrant label inside one of them.
#if canImport(UIKit)
import UIKit
import UIKitFixtureKit

public enum MaterialFixtures {
    public static let all = [materials]

    public static let materials = UIKitFixture("uikit/view/materials", size: CGSize(width: 320, height: 440)) {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 440))
        root.backgroundColor = .white
        for (index, colour) in [UIColor.black, .systemBlue, .white, .systemRed].enumerated() {
            let band = UIView(frame: CGRect(x: CGFloat(index) * 80, y: 0, width: 80, height: 440))
            band.backgroundColor = colour
            root.addSubview(band)
        }
        // A sharp edge under the blur: a thin white line across the black band.
        let line = UIView(frame: CGRect(x: 0, y: 16, width: 80, height: 2))
        line.backgroundColor = .white
        root.addSubview(line)

        let styles: [(UIBlurEffect.Style, String)] = [
            (.systemUltraThinMaterial, "ultraThin"), (.systemThinMaterial, "thin"), (.systemMaterial, "material"),
            (.systemThickMaterial, "thick"), (.systemChromeMaterial, "chrome"), (.regular, "regular"),
            (.light, "light"), (.dark, "dark"),
        ]
        for (index, (style, probe)) in styles.enumerated() {
            let effect = UIVisualEffectView(effect: UIBlurEffect(style: style))
            effect.frame = CGRect(x: 0, y: 8 + CGFloat(index) * 50, width: 320, height: 40)
            root.addSubview(effect.probe(probe))
            if index == 2 {
                let blur = UIBlurEffect(style: style)
                let vibrant = UIVisualEffectView(effect: UIVibrancyEffect(blurEffect: blur, style: .label))
                vibrant.frame = effect.contentView.bounds
                vibrant.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                let label = UILabel()
                label.text = "Vibrant label"
                label.font = .systemFont(ofSize: 17, weight: .semibold)
                label.sizeToFit()
                label.frame.origin = CGPoint(x: 12, y: 9)
                vibrant.contentView.addSubview(label.probe("vibrantLabel"))
                effect.contentView.addSubview(vibrant.probe("vibrant"))
            }
            if index == 5 {
                let label = UILabel()
                label.text = "Plain label"
                label.font = .systemFont(ofSize: 17, weight: .semibold)
                label.sizeToFit()
                label.frame.origin = CGPoint(x: 12, y: 9)
                effect.contentView.addSubview(label.probe("plainLabel"))
            }
        }
        // A rounded, clipped material over the bands.
        let rounded = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
        rounded.frame = CGRect(x: 40, y: 412, width: 240, height: 24)
        rounded.layer.cornerRadius = 12
        rounded.clipsToBounds = true
        root.addSubview(rounded.probe("rounded"))
        return root
    }
}
#endif
