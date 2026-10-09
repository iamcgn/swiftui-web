// uk-view-pixels (Layers/LayerPainting.swift): a layer mask clips what the layer paints, a
// shadow path casts the shadow in the layer's background colour (nothing without one), and a
// corner radius past half a side is CoreAnimation's lens, not a capsule.
import Testing
import UIKit
@testable import UIKitWebCore

@Suite @MainActor struct LayerLookTests {
    private func commands(_ build: (UIView) -> Void) -> [DisplayCommand] {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        scene.textEngine = try! Goldens.textEngine()
        scene.configureScreen(size: CGSize(width: 320, height: 300), scale: 2)
        let root = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 300))
        window.rootViewController = root
        window.makeKeyAndVisible()
        build(root.view)
        scene.layout(in: CGSize(width: 320, height: 300))
        return scene.render(scale: 2, background: false).commands
    }

    private func kinds(_ commands: [DisplayCommand]) -> [String] { commands.map { "\($0)".prefix { $0 != "(" }.description } }

    @Test func masksShadowPathsAndLenses() {
        let masked = commands { root in
            let view = UIView(frame: CGRect(x: 16, y: 16, width: 80, height: 60))
            view.backgroundColor = .systemPurple
            let mask = CAShapeLayer()
            mask.path = UIBezierPath(ovalIn: CGRect(x: 5, y: 5, width: 70, height: 50)).cgPath
            view.layer.mask = mask
            root.addSubview(view)
        }
        // The mask's oval, then the masked purple fill, closed as one group.
        let order = kinds(masked)
        let maskStart = order.firstIndex(of: "beginMask")!
        #expect(order[maskStart + 1] == "fillPath" && order[maskStart + 2] == "beginMasked" && order[maskStart + 3] == "fillRect" && order[maskStart + 4] == "endGroup")

        let shadowed = commands { root in
            let view = UIView(frame: CGRect(x: 16, y: 16, width: 80, height: 60))
            view.backgroundColor = .white
            view.layer.shadowOpacity = 0.5
            view.layer.shadowPath = UIBezierPath(ovalIn: CGRect(x: 10, y: 10, width: 60, height: 40)).cgPath
            root.addSubview(view)
            let clear = UIView(frame: CGRect(x: 120, y: 16, width: 80, height: 60))
            clear.layer.shadowOpacity = 0.5
            clear.layer.shadowPath = UIBezierPath(rect: CGRect(x: 0, y: 0, width: 80, height: 60)).cgPath
            root.addSubview(clear)
        }
        // One shadow group holding the path in the background colour, then the view's own fill
        // outside it; the clear view casts nothing.
        let shadows = shadowed.filter { if case .beginShadow = $0 { return true } else { return false } }
        #expect(shadows.count == 1)
        let start = kinds(shadowed).firstIndex(of: "beginShadow")!
        #expect(kinds(shadowed)[start + 1] == "fillPath" && kinds(shadowed)[start + 2] == "endGroup" && kinds(shadowed)[start + 3] == "fillRect")
        if case .fillPath(let path, let color, _) = shadowed[start + 1] {
            #expect(color == RGBA.white && path.boundingRect.minX == 26 && path.boundingRect.width == 60)
        } else { Issue.record("no shadow path fill") }

        let lens = commands { root in
            let view = UIView(frame: CGRect(x: 16, y: 16, width: 80, height: 60))
            view.backgroundColor = .systemOrange
            view.layer.cornerRadius = 40
            root.addSubview(view)
            let capsule = UIView(frame: CGRect(x: 120, y: 16, width: 80, height: 60))
            capsule.backgroundColor = .systemOrange
            capsule.layer.cornerRadius = 30
            root.addSubview(capsule)
        }
        let fills = lens.filter { if case .fillPath = $0 { return true } else { return false } }
        let capsules = lens.filter { if case .fillRRect(_, let r, _) = $0 { return r == 30 } else { return false } }
        #expect(fills.count == 1 && capsules.count == 1)   // the lens is an explicit path, the capsule a rounded rect
        if case .fillPath(let path, _, _) = fills[0] {
            // The crossing path spans the view; its leftmost point sits in from the edge.
            #expect(path.boundingRect == CGRect(x: 16, y: 16, width: 80, height: 60))
        }
    }
}
