// UIView and CALayer (Docs/elements/UIKit/UIView.md): backgrounds, corner radii, borders,
// alpha, a transform, clipping, a shadow, autoresizing.
#if canImport(UIKit)
import UIKit
import UIKitFixtureKit

public enum ViewFixtures {
    public static let all = [layers, autoresizing]

    public static let layers = UIKitFixture("uikit/view/layers", size: CGSize(width: 320, height: 300)) {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 300))
        let plain = UIView(frame: CGRect(x: 16, y: 16, width: 80, height: 60))
        plain.backgroundColor = .systemBlue
        root.addSubview(plain.probe("plain"))
        let rounded = UIView(frame: CGRect(x: 112, y: 16, width: 80, height: 60))
        rounded.backgroundColor = .systemGreen
        rounded.layer.cornerRadius = 12
        root.addSubview(rounded.probe("rounded"))
        let bordered = UIView(frame: CGRect(x: 208, y: 16, width: 80, height: 60))
        bordered.backgroundColor = .systemGray6
        bordered.layer.borderWidth = 2
        bordered.layer.borderColor = UIColor.systemRed.cgColor
        bordered.layer.cornerRadius = 8
        root.addSubview(bordered.probe("bordered"))
        let faded = UIView(frame: CGRect(x: 16, y: 92, width: 80, height: 60))
        faded.backgroundColor = .systemIndigo
        faded.alpha = 0.5
        root.addSubview(faded.probe("faded"))
        let rotated = UIView(frame: CGRect(x: 112, y: 92, width: 80, height: 60))
        rotated.backgroundColor = .systemOrange
        rotated.transform = CGAffineTransform(rotationAngle: .pi / 8)
        root.addSubview(rotated.probe("rotated"))
        let clipping = UIView(frame: CGRect(x: 208, y: 92, width: 80, height: 60))
        clipping.backgroundColor = .systemTeal
        clipping.clipsToBounds = true
        let overflow = UIView(frame: CGRect(x: 40, y: 30, width: 80, height: 60))
        overflow.backgroundColor = .systemPink
        clipping.addSubview(overflow.probe("overflow"))
        root.addSubview(clipping.probe("clipping"))
        let shadowed = UIView(frame: CGRect(x: 16, y: 180, width: 80, height: 60))
        shadowed.backgroundColor = .white
        shadowed.layer.shadowOpacity = 0.3
        shadowed.layer.shadowRadius = 6
        shadowed.layer.shadowOffset = CGSize(width: 0, height: 4)
        root.addSubview(shadowed.probe("shadowed"))
        let continuous = UIView(frame: CGRect(x: 112, y: 180, width: 80, height: 60))
        continuous.backgroundColor = .systemPurple
        continuous.layer.cornerRadius = 20
        continuous.layer.cornerCurve = .continuous
        root.addSubview(continuous.probe("continuous"))
        let corners = UIView(frame: CGRect(x: 208, y: 180, width: 80, height: 60))
        corners.backgroundColor = .systemBrown
        corners.layer.cornerRadius = 16
        corners.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMaxYCorner]
        root.addSubview(corners.probe("corners"))
        return root
    }

    /// Autoresizing masks against a container that is resized after the subviews are placed.
    public static let autoresizing = UIKitFixture("uikit/view/autoresizing", size: CGSize(width: 320, height: 200)) {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 200))
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        container.backgroundColor = .systemGray5
        let flexible = UIView(frame: CGRect(x: 10, y: 10, width: 180, height: 30))
        flexible.backgroundColor = .systemBlue
        flexible.autoresizingMask = [.flexibleWidth, .flexibleBottomMargin]
        container.addSubview(flexible.probe("flexibleWidth"))
        let pinned = UIView(frame: CGRect(x: 150, y: 60, width: 40, height: 30))
        pinned.backgroundColor = .systemRed
        pinned.autoresizingMask = [.flexibleLeftMargin, .flexibleTopMargin]
        container.addSubview(pinned.probe("pinnedBottomRight"))
        let centred = UIView(frame: CGRect(x: 80, y: 40, width: 40, height: 20))
        centred.backgroundColor = .systemGreen
        centred.autoresizingMask = [.flexibleLeftMargin, .flexibleRightMargin, .flexibleTopMargin, .flexibleBottomMargin]
        container.addSubview(centred.probe("centred"))
        root.addSubview(container.probe("container"))
        container.frame = CGRect(x: 16, y: 16, width: 288, height: 160)
        return root
    }
}
#endif
