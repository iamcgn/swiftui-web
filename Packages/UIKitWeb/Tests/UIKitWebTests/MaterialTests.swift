// uk-materials (Views/UIVisualEffectView.swift, the substrate's backdropBlur): an effect view
// blurs what lies beneath and tints it, a vibrancy view is a transparent container, the
// rounded corners follow the layer, and the glass platters blur their ground.
import Testing
import UIKit
@testable import UIKitWebCore

@Suite @MainActor struct MaterialTests {
    private func render(_ build: (UIView) -> Void) -> [DisplayCommand] {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        scene.textEngine = try! Goldens.textEngine()
        scene.configureScreen(size: CGSize(width: 320, height: 300), scale: 2)
        let root = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 300))
        window.overrideUserInterfaceStyle = .light
        window.rootViewController = root
        window.makeKeyAndVisible()
        build(root.view)
        scene.layout(in: CGSize(width: 320, height: 300))
        return scene.render(scale: 2, background: false).commands
    }

    @Test func effectViewsBlurAndTintTheirGround() {
        let effect = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
        let label = UILabel()
        label.font = .systemFont(ofSize: 17, weight: .semibold)
        let commands = render { root in
            let ground = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 300))
            ground.backgroundColor = .systemBlue
            root.addSubview(ground)
            effect.frame = CGRect(x: 20, y: 40, width: 280, height: 60)
            effect.layer.cornerRadius = 12
            effect.clipsToBounds = true
            label.text = "Plain label"   // a recorded string (uikit/view/materials)
            label.sizeToFit()
            effect.contentView.addSubview(label)
            root.addSubview(effect)
        }
        #expect(effect.contentView.frame == CGRect(x: 0, y: 0, width: 280, height: 60) && label.superview === effect.contentView)
        // The ground, then the blur under the view's rounded path, its tint, then the content.
        let blurIndex = commands.firstIndex { if case .backdropBlur = $0 { return true } else { return false } }
        guard let blurIndex, case .backdropBlur(let path, let bounds, let radius, let saturation) = commands[blurIndex] else { Issue.record("no backdrop"); return }
        #expect(bounds == CGRect(x: 20, y: 40, width: 280, height: 60) && radius == 28 && saturation == 1 && path.elements.count > 5)
        guard case .fillPath(_, let tint, _) = commands[blurIndex + 1] else { Issue.record("no tint"); return }
        #expect(abs(tint.alpha - 0.78) < 0.001 && abs(tint.red * 255 - 245) < 0.5)
        let text = commands.lastIndex { if case .drawText = $0 { return true } else { return false } }
        #expect(text != nil && text! > blurIndex)
        let blueFill = commands.firstIndex { if case .fillRect(_, let c) = $0 { return c.blue > 0.9 && c.red < 0.1 } else { return false } }
        #expect(blueFill != nil && blueFill! < blurIndex)
    }

    @Test func stylesAndVibrancy() {
        #expect(UIBlurEffect(style: .systemUltraThinMaterial).look.sigma == 20 && UIBlurEffect(style: .dark).look.sigma == 16)
        #expect(UIBlurEffect(style: .regular).look.saturation == 1.6 && UIBlurEffect(style: .systemThickMaterial).look.saturation == 1)
        #expect(UIBlurEffect(style: .systemMaterialDark).look.light == UIBlurEffect(style: .systemMaterial).look.dark)
        let vibrancy = UIVibrancyEffect(blurEffect: UIBlurEffect(style: .systemMaterial), style: .label)
        let vibrant = UIVisualEffectView(effect: vibrancy)
        let commands = render { root in
            vibrant.frame = CGRect(x: 0, y: 0, width: 100, height: 40)
            root.addSubview(vibrant)
        }
        #expect(!commands.contains { if case .backdropBlur = $0 { return true } else { return false } })
        #expect(vibrancy.blurEffect.style == .systemMaterial && vibrancy.style == .label)
    }

    @Test func glassPlattersBlurTheirGround() {
        let commands = render { root in
            let tabs = UITabBar(frame: CGRect(x: 0, y: 217, width: 320, height: 83))
            tabs.items = [UITabBarItem(title: "Home", image: UIImage(systemName: "house"), tag: 0)]
            tabs.selectedItem = tabs.items?.first
            root.addSubview(tabs)
        }
        let blur = commands.first { if case .backdropBlur = $0 { return true } else { return false } }
        guard case .backdropBlur(_, let bounds, let radius, _)? = blur else { Issue.record("no glass"); return }
        #expect(radius == GlassPainter.sigma && bounds.height == 62)
        let tints = commands.compactMap { command -> RGBA? in if case .fillPath(_, let c, _) = command { return c } else { return nil } }
        #expect(tints.contains { $0.alpha == GlassPainter.lightTint.alpha })
    }
}
