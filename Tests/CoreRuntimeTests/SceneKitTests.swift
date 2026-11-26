// SceneKit (Docs/elements/SceneKit.md): the matrix and rotation arithmetic, the scene graph's
// transforms, actions stepped frame by frame, Core Animation animations worked out at a time,
// and SCNView's projection, hit testing and painting.
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless
@testable import SceneKit

@Suite @MainActor struct SceneKitTests {
    private func close(_ a: Float, _ b: Float, _ tolerance: Float = 1e-4) -> Bool { abs(a - b) < tolerance }
    private func close(_ a: SCNVector3, _ b: SCNVector3, _ tolerance: Float = 1e-4) -> Bool {
        close(a.x, b.x, tolerance) && close(a.y, b.y, tolerance) && close(a.z, b.z, tolerance)
    }

    @Test func matricesApplyTheLeftOneFirst() {
        let translate = SCNMatrix4MakeTranslation(1, 2, 3)
        let rotate = SCNMatrix4MakeRotation(.pi / 2, 0, 0, 1)
        // Rotate a quarter turn about z, then move: (1, 0, 0) → (0, 1, 0) → (1, 3, 3).
        #expect(close(SCNMatrix4Mult(rotate, translate).transformPoint(SCNVector3(1, 0, 0)), SCNVector3(1, 3, 3)))
        // Move, then rotate: (1, 0, 0) → (2, 2, 3) → (-2, 2, 3).
        #expect(close(SCNMatrix4Mult(translate, rotate).transformPoint(SCNVector3(1, 0, 0)), SCNVector3(-2, 2, 3)))
        let m = SCNMatrix4Mult(SCNMatrix4MakeScale(2, 3, 4), SCNMatrix4Mult(rotate, translate))
        let back = SCNMatrix4Mult(m, SCNMatrix4Invert(m))
        for (row, identity) in zip(back.rows, SCNMatrix4Identity.rows) {
            for (a, b) in zip(row, identity) { #expect(close(a, b)) }
        }
    }

    @Test func rotationsReadBackInEveryForm() {
        let node = SCNNode()
        node.eulerAngles = SCNVector3(0.3, -0.7, 1.1)
        #expect(close(node.eulerAngles, SCNVector3(0.3, -0.7, 1.1)))
        node.rotation = SCNVector4(0, 1, 0, Float.pi / 2)
        #expect(close(node.eulerAngles.y, .pi / 2, 1e-3))
        // A quarter turn about y takes the node's +z to the scene's +x.
        #expect(close(node.transform.transformDirection(SCNVector3(0, 0, 1)), SCNVector3(1, 0, 0)))
        node.transform = SCNMatrix4Mult(SCNMatrix4MakeScale(2, 2, 2), SCNMatrix4MakeTranslation(5, 0, 0))
        #expect(close(node.position, SCNVector3(5, 0, 0)) && close(node.scale, SCNVector3(2, 2, 2)))
    }

    @Test func childrenSitInTheirParentsSpace() {
        let parent = SCNNode()
        parent.position = SCNVector3(10, 0, 0)
        parent.eulerAngles = SCNVector3(0, Float.pi / 2, 0)
        let child = SCNNode()
        child.position = SCNVector3(0, 0, 1)
        parent.addChildNode(child)
        #expect(close(child.worldPosition, SCNVector3(11, 0, 0)))
        #expect(close(child.convertPosition(SCNVector3(), to: nil), SCNVector3(11, 0, 0)))
        child.worldPosition = SCNVector3(10, 0, 2)
        #expect(close(child.position, SCNVector3(-2, 0, 0)))
        child.name = "child"
        #expect(parent.childNode(withName: "child", recursively: false) === child)
    }

    @Test func actionsStepAFrameAtATime() {
        let node = SCNNode()
        var ran = 0
        node.runAction(.sequence([.moveBy(x: 2, y: 0, z: 0, duration: 1), .run { _ in ran += 1 }, .fadeOut(duration: 0.5)]), forKey: "walk")
        node.stepActions(0.5)
        #expect(close(node.position.x, 1))
        #expect(ran == 0 && node.hasActions)
        node.stepActions(0.75)
        // The move finished, the block ran, and the fade is half done with the quarter second left over.
        #expect(close(node.position.x, 2) && ran == 1)
        #expect(abs(node.opacity - 0.5) < 1e-6)
        node.stepActions(1)
        #expect(node.opacity == 0 && !node.hasActions)

        let spinner = SCNNode()
        spinner.runAction(.repeatForever(.rotateBy(x: 0, y: .pi, z: 0, duration: 2)))
        spinner.stepActions(1)
        #expect(close(spinner.eulerAngles.y, .pi / 2, 1e-3))
        spinner.stepActions(1000)
        #expect(spinner.hasActions)
        spinner.removeAllActions()
        #expect(!spinner.hasActions)
    }

    @Test func animationsPlayWithoutTouchingTheModel() {
        let node = SCNNode()
        let spin = CABasicAnimation(keyPath: "rotation")
        spin.fromValue = NSValue(scnVector4: SCNVector4(0, 1, 0, 0))
        spin.toValue = NSValue(scnVector4: SCNVector4(0, 1, 0, Float.pi))
        spin.duration = 4
        spin.repeatCount = .infinity
        node.addAnimation(spin, forKey: "spin")
        let start = node.animations[0].start
        let turned = node.localTransform(at: start + 2).transformDirection(SCNVector3(0, 0, 1))
        #expect(close(turned, SCNVector3(1, 0, 0), 1e-3))
        #expect(close(node.eulerAngles.y, 0))
        let rise = CABasicAnimation(keyPath: "position.y")
        rise.fromValue = 0
        rise.toValue = 10
        rise.duration = 1
        node.addAnimation(rise, forKey: nil)
        let raised = node.localTransform(at: node.animations[1].start + 0.25)
        #expect(close(raised.m42, 2.5))
        node.pruneAnimations(at: node.animations[1].start + 5)
        #expect(node.animationKeys == ["spin"])
    }

    private func boxScene(color: UIColor) -> (SCNScene, SCNNode) {
        let scene = SCNScene()
        let box = SCNBox(width: 1, height: 1, length: 1, chamferRadius: 0)
        box.firstMaterial?.diffuse.contents = color
        box.firstMaterial?.lightingModel = .constant
        let node = SCNNode(geometry: box)
        node.name = "box"
        scene.rootNode.addChildNode(node)
        return (scene, node)
    }

    @Test func theViewFramesTheSceneAndFindsWhatIsUnderAPoint() {
        let (scene, node) = boxScene(color: .red)
        let view = SCNView(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        view.scene = scene
        // With no camera in the scene, the view looks down -z at the scene's centre.
        let center = view.projectPoint(SCNVector3())
        #expect(close(center.x, 100) && close(center.y, 50))
        let corner = view.projectPoint(SCNVector3(0.5, 0.5, 0.5))
        #expect(corner.x > 100 && corner.y < 50)
        #expect(view.hitTest(CGPoint(x: 100, y: 50), options: nil).first?.node === node)
        #expect(view.hitTest(CGPoint(x: 2, y: 2), options: nil).isEmpty)

        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.usesOrthographicProjection = true
        cameraNode.camera?.orthographicScale = 1
        cameraNode.position = SCNVector3(0, 0, 5)
        scene.rootNode.addChildNode(cameraNode)
        view.pointOfView = cameraNode
        // Half the view's height is one unit: the box's front face spans 50 points.
        let edge = view.projectPoint(SCNVector3(0.5, 0, 0.5))
        #expect(close(edge.x, 125, 1e-2))
        let back = view.unprojectPoint(SCNVector3(125, 50, edge.z))
        #expect(close(back, SCNVector3(0.5, 0, 0.5), 1e-3))
    }

    @Test func projectedDepthRunsFromTheNearPlaneToTheFarPlane() {
        let (scene, _) = boxScene(color: .red)
        let view = SCNView(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        view.scene = scene
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.zNear = 0.5
        cameraNode.camera?.zFar = 10
        scene.rootNode.addChildNode(cameraNode)
        view.pointOfView = cameraNode
        // The camera sits at the origin looking down -z.
        #expect(close(view.projectPoint(SCNVector3(0, 0, -0.5)).z, 0, 1e-4))
        #expect(close(view.projectPoint(SCNVector3(0, 0, -10)).z, 1, 1e-4))
        let middle = view.projectPoint(SCNVector3(0, 0, -2)).z
        #expect(middle > 0 && middle < 1)
        #expect(close(view.unprojectPoint(SCNVector3(100, 50, 0)), SCNVector3(0, 0, -0.5), 1e-3))
        #expect(close(view.unprojectPoint(SCNVector3(100, 50, 1)), SCNVector3(0, 0, -10), 1e-2))
        #expect(close(view.unprojectPoint(SCNVector3(100, 50, middle)), SCNVector3(0, 0, -2), 1e-3))
        // An orthographic camera's depth is linear between the planes.
        cameraNode.camera?.usesOrthographicProjection = true
        #expect(close(view.projectPoint(SCNVector3(0, 0, -5.25)).z, 0.5, 1e-4))
        #expect(close(view.unprojectPoint(SCNVector3(100, 50, 1)), SCNVector3(0, 0, -10), 1e-3))
    }

    @Test func aSceneViewPaintsItsFacesFarToNear() {
        let (scene, _) = boxScene(color: UIColor(red: 1, green: 0, blue: 0, alpha: 1))
        scene.background.contents = UIColor(red: 0, green: 0, blue: 1, alpha: 1)
        let runtime = Runtime()
        runtime.mount(SceneView(scene: scene, options: [.autoenablesDefaultLighting]).frame(width: 200, height: 100))
        runtime.layout(in: CGSize(width: 200, height: 100))
        let commands = runtime.render(scale: 2).commands.map(\.description)
        let blue = commands.firstIndex { $0.contains("#0000FF") }
        let red = commands.indices.filter { commands[$0].contains("#FF0000") }
        // The background first, then the box's two triangles facing the camera (the others are culled).
        #expect(blue != nil && !red.isEmpty, "\(commands)")
        #expect(red.allSatisfy { $0 > blue! })
    }

    @Test func textAndWireframesDraw() {
        let scene = SCNScene()
        let text = SCNText(string: "Hi", extrusionDepth: 1)
        text.font = UIFont.systemFont(ofSize: 10)
        text.firstMaterial?.diffuse.contents = UIColor(red: 0, green: 1, blue: 0, alpha: 1)
        text.firstMaterial?.lightingModel = .constant
        scene.rootNode.addChildNode(SCNNode(geometry: text))
        let sphere = SCNSphere(radius: 5)
        sphere.segmentCount = 8
        sphere.firstMaterial?.fillMode = .lines
        sphere.firstMaterial?.diffuse.contents = UIColor(red: 1, green: 1, blue: 0, alpha: 1)
        sphere.firstMaterial?.lightingModel = .constant
        let ball = SCNNode(geometry: sphere)
        ball.position = SCNVector3(0, 0, -20)
        scene.rootNode.addChildNode(ball)
        let runtime = Runtime()
        runtime.textEngine = SceneTextEngine()
        runtime.mount(SceneView(scene: scene).frame(width: 200, height: 100))
        runtime.layout(in: CGSize(width: 200, height: 100))
        let commands = runtime.render(scale: 2).commands.map(\.description)
        #expect(commands.contains { $0.contains("drawText(\"Hi\"") }, "\(commands)")
        #expect(commands.contains { $0.contains("#FFFF00") && $0.lowercased().contains("stroke") }, "\(commands)")
    }
}

/// Lays text out at a fixed advance per character, so the scene's text has a size on every
/// platform (the Charts tests' engine isn't built for wasm).
private final class SceneTextEngine: TextEngine {
    func layout(_ runs: [StyledRun], options: TextLayoutOptions, width: CGFloat?) -> TextLayout {
        let string = runs.map(\.string).joined()
        let size = runs.first?.font.size ?? 13
        let w = CGFloat(string.count) * size * 0.6
        let baseline = size * 0.8
        let line = TextLayout.Line(range: string.startIndex..<string.endIndex, width: w, baseline: baseline, fragments: [TextLayout.Fragment(text: string, run: 0, x: 0, width: w)])
        return TextLayout(size: CGSize(width: w, height: size * 1.2), firstBaseline: baseline, lastBaseline: baseline, lines: [line])
    }

    func metrics(for font: ResolvedFont) -> FontMetrics {
        FontMetrics(lineHeight: font.size * 1.2, spacingBelow: 0, spacingAbove: 0, textToText: 0)
    }
}
