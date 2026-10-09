// UIView looks beyond uikit/view/layers (uk-view-pixels, Docs/elements/UIKit/UIView.md): a
// shadow following a shadow path, a coloured tight shadow, a hairline border on a rounded
// view, a thick border on a capsule, a corner radius past the half height, group opacity over
// overlapping children, a layer mask, and a shadow cast by a container's rounded child.
#if canImport(UIKit)
import UIKit
import UIKitFixtureKit

public enum LookFixtures {
    public static let all = [looks]

    public static let looks = UIKitFixture("uikit/view/looks", size: CGSize(width: 320, height: 300)) {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 300))
        root.backgroundColor = .white

        let pathShadow = UIView(frame: CGRect(x: 16, y: 16, width: 80, height: 60))
        pathShadow.backgroundColor = .white
        pathShadow.layer.shadowOpacity = 0.5
        pathShadow.layer.shadowRadius = 4
        pathShadow.layer.shadowOffset = CGSize(width: 0, height: 2)
        pathShadow.layer.shadowPath = UIBezierPath(ovalIn: CGRect(x: 10, y: 10, width: 60, height: 40)).cgPath
        root.addSubview(pathShadow.probe("pathShadow"))

        let tinted = UIView(frame: CGRect(x: 112, y: 16, width: 80, height: 60))
        tinted.backgroundColor = .systemGray6
        tinted.layer.cornerRadius = 10
        tinted.layer.shadowColor = UIColor.systemBlue.cgColor
        tinted.layer.shadowOpacity = 0.6
        tinted.layer.shadowRadius = 2
        tinted.layer.shadowOffset = CGSize(width: 3, height: 3)
        root.addSubview(tinted.probe("tinted"))

        let hairline = UIView(frame: CGRect(x: 208, y: 16, width: 80, height: 60))
        hairline.backgroundColor = .systemGray6
        hairline.layer.cornerRadius = 10
        hairline.layer.borderWidth = 0.5
        hairline.layer.borderColor = UIColor.black.cgColor
        root.addSubview(hairline.probe("hairline"))

        let capsule = UIView(frame: CGRect(x: 16, y: 92, width: 80, height: 60))
        capsule.backgroundColor = .systemYellow
        capsule.layer.cornerRadius = 30
        capsule.layer.borderWidth = 4
        capsule.layer.borderColor = UIColor.systemGreen.cgColor
        root.addSubview(capsule.probe("capsule"))

        let overRadius = UIView(frame: CGRect(x: 112, y: 92, width: 80, height: 60))
        overRadius.backgroundColor = .systemOrange
        overRadius.layer.cornerRadius = 40
        root.addSubview(overRadius.probe("overRadius"))

        let group = UIView(frame: CGRect(x: 208, y: 92, width: 80, height: 60))
        group.alpha = 0.5
        let first = UIView(frame: CGRect(x: 0, y: 0, width: 50, height: 40))
        first.backgroundColor = .systemBlue
        let second = UIView(frame: CGRect(x: 30, y: 20, width: 50, height: 40))
        second.backgroundColor = .systemRed
        group.addSubview(first.probe("first"))
        group.addSubview(second.probe("second"))
        root.addSubview(group.probe("group"))

        let masked = UIView(frame: CGRect(x: 16, y: 168, width: 80, height: 60))
        masked.backgroundColor = .systemPurple
        let mask = CAShapeLayer()
        mask.path = UIBezierPath(ovalIn: CGRect(x: 5, y: 5, width: 70, height: 50)).cgPath
        masked.layer.mask = mask
        root.addSubview(masked.probe("masked"))

        let container = UIView(frame: CGRect(x: 112, y: 168, width: 80, height: 60))
        container.backgroundColor = .clear
        container.layer.shadowOpacity = 0.4
        container.layer.shadowRadius = 5
        container.layer.shadowOffset = CGSize(width: 0, height: 3)
        let child = UIView(frame: CGRect(x: 10, y: 5, width: 60, height: 50))
        child.backgroundColor = .systemTeal
        child.layer.cornerRadius = 14
        container.addSubview(child.probe("child"))
        root.addSubview(container.probe("container"))

        let continuousBorder = UIView(frame: CGRect(x: 208, y: 168, width: 80, height: 60))
        continuousBorder.backgroundColor = .systemPink
        continuousBorder.layer.cornerRadius = 20
        continuousBorder.layer.cornerCurve = .continuous
        continuousBorder.layer.borderWidth = 3
        continuousBorder.layer.borderColor = UIColor.black.cgColor
        root.addSubview(continuousBorder.probe("continuousBorder"))
        return root
    }
}
#endif
