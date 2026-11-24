// SceneKit in the browser, for comparing its renderers (Playwright/webgl): three scenes picked
// at the top. Waves and Globe are mikelikesdesign's SwiftUIExperiments scenes as written; Spheres
// is a heavier lit, textured scene. ?mesh=cpu draws on the CPU, ?mesh=2d without WebGL.
import SwiftUI
import SceneKit

@main
struct SceneDemoApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

struct ContentView: View {
    @State private var scene = "Spheres"
    var body: some View {
        VStack(spacing: 0) {
            Picker("Scene", selection: $scene) {
                ForEach(["Spheres", "Waves", "Globe"], id: \.self) { Text($0) }
            }
            .pickerStyle(.segmented)
            .padding(8)
            ZStack {
                switch scene {
                case "Waves": WavesView()
                case "Globe": GlobeView()
                default: SpheresView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
        }
    }
}

// MARK: - Spheres: 16 lit spheres turning, a textured box, a floor, three lights

struct SpheresView: UIViewRepresentable {
    static let checker = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAYAAACqaXHeAAAAgUlEQVR42u3YMREAIAwEQeREBBKRgzAcgINQE7agTMFWN9+ij529NSN9r983AAAAAAAA4GOA6h+83QMAAAAAAAA/AyhBAAAAAAAAwB6gBAEAAAAAAAB7gBIEAAAAAAAA7AFKEAAAAAAAALAHKEEAAAAAAADAHqAEAQAAAAAAgHIAB5i50iwRbMzgAAAAAElFTkSuQmCC")!

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        let scene = SCNScene()
        view.scene = scene
        view.backgroundColor = .black
        let colors: [UIColor] = [.systemRed, .systemOrange, .systemYellow, .systemGreen, .systemTeal, .systemBlue, .systemIndigo, .systemPink]
        for row in 0..<4 {
            for column in 0..<4 {
                let sphere = SCNSphere(radius: 0.7)
                sphere.segmentCount = 48
                let material = SCNMaterial()
                material.diffuse.contents = colors[(row * 4 + column) % colors.count]
                sphere.materials = [material]
                let node = SCNNode(geometry: sphere)
                node.position = SCNVector3(Float(column) * 1.8 - 2.7, Float(row) * 1.8 - 1.2, 0)
                node.runAction(.repeatForever(.rotateBy(x: 0, y: 2 * .pi, z: 0, duration: Double(4 + row + column))))
                scene.rootNode.addChildNode(node)
            }
        }
        let box = SCNBox(width: 1.6, height: 1.6, length: 1.6, chamferRadius: 0)
        let boxMaterial = SCNMaterial()
        boxMaterial.diffuse.contents = UIImage(data: Self.checker)
        box.materials = [boxMaterial]
        let boxNode = SCNNode(geometry: box)
        boxNode.position = SCNVector3(0, 1.5, 3)
        boxNode.runAction(.repeatForever(.rotateBy(x: 1, y: 2, z: 0, duration: 6)))
        scene.rootNode.addChildNode(boxNode)

        let floor = SCNFloor()
        floor.firstMaterial?.diffuse.contents = UIColor.darkGray
        let floorNode = SCNNode(geometry: floor)
        floorNode.position = SCNVector3(0, -2.5, 0)
        scene.rootNode.addChildNode(floorNode)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 250
        scene.rootNode.addChildNode(ambient)
        let sun = SCNNode()
        sun.light = SCNLight()
        sun.light?.type = .directional
        sun.light?.intensity = 800
        sun.eulerAngles = SCNVector3(-Float.pi / 3, Float.pi / 6, 0)
        scene.rootNode.addChildNode(sun)
        let lamp = SCNNode()
        lamp.light = SCNLight()
        lamp.light?.type = .omni
        lamp.light?.color = UIColor.systemTeal
        lamp.light?.intensity = 600
        lamp.position = SCNVector3(-3, 3, 4)
        scene.rootNode.addChildNode(lamp)

        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.position = SCNVector3(0, 1, 10)
        camera.look(at: SCNVector3(0, 0.5, 0))
        scene.rootNode.addChildNode(camera)
        view.pointOfView = camera
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}
}

// MARK: - Waves (SwiftUIExperiments, waves/ContentView.swift: SceneKitView)

struct WavesView: UIViewRepresentable {
    func makeUIView(context: Context) -> SCNView {
        let sceneView = SCNView()
        sceneView.scene = SCNScene()
        sceneView.backgroundColor = .clear
        sceneView.autoenablesDefaultLighting = true

        let sphere = SCNSphere(radius: 8)
        sphere.segmentCount = 40

        let material = SCNMaterial()
        material.fillMode = .lines
        material.diffuse.contents = UIColor(Color.cyan)
        material.emission.contents = UIColor(Color.cyan.opacity(0.5))
        sphere.materials = [material]

        let sphereNode = SCNNode(geometry: sphere)
        let sphere2 = SCNSphere(radius: 8)
        sphere2.segmentCount = 40
        let material2 = SCNMaterial()
        material2.fillMode = .lines
        material2.diffuse.contents = UIColor(Color.cyan.opacity(0.6))
        material2.emission.contents = UIColor(Color.cyan.opacity(0.3))
        sphere2.materials = [material2]

        let sphere2Node = SCNNode(geometry: sphere2)
        sphere2Node.rotation = SCNVector4(1, 0, 0, Float.pi / 2)
        sphereNode.addChildNode(sphere2Node)

        sceneView.scene?.rootNode.addChildNode(sphereNode)
        let rotation = CABasicAnimation(keyPath: "rotation")
        rotation.toValue = NSValue(scnVector4: SCNVector4(0, 1, 0, Float.pi * 2))
        rotation.duration = 12
        rotation.repeatCount = .infinity
        sphereNode.addAnimation(rotation, forKey: "rotate")

        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(x: 0, y: 0, z: 25)
        sceneView.scene?.rootNode.addChildNode(cameraNode)

        return sceneView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}
}

// MARK: - Globe (SwiftUIExperiments, globe/ContentView.swift: GlobeView)

struct GlobeView: UIViewRepresentable {
    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.scene = createGlobeScene()
        scnView.backgroundColor = UIColor.black
        scnView.autoenablesDefaultLighting = true
        scnView.allowsCameraControl = true

        // Update the texture more frequently for smoother animation
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            scnView.scene?.rootNode.childNodes.first?.geometry?.firstMaterial?.diffuse.contents = self.createTextTexture()
        }

        return scnView
    }

    func updateUIView(_ scnView: SCNView, context: Context) {}

    private func createGlobeScene() -> SCNScene {
        let scene = SCNScene()
        let globeNode = SCNNode(geometry: SCNSphere(radius: 1.0))
        globeNode.position = SCNVector3(x: 0, y: 0, z: 0)

        let material = SCNMaterial()
        material.diffuse.contents = createTextTexture()
        globeNode.geometry?.materials = [material]

        scene.rootNode.addChildNode(globeNode)
        return scene
    }

    private func createTextTexture() -> UIImage {
        let size = CGSize(width: 1024, height: 512)
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { ctx in
            let rectangle = CGRect(origin: .zero, size: size)
            ctx.cgContext.setFillColor(UIColor.black.cgColor)
            ctx.cgContext.addRect(rectangle)
            ctx.cgContext.drawPath(using: .fill)

            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .left

            for _ in 0..<1000 {
                let randomString = String((0..<1).map{ _ in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".randomElement()! })
                let randomX = CGFloat.random(in: 0..<size.width)
                let randomY = CGFloat.random(in: 0..<size.height)
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 16),
                    .paragraphStyle: paragraphStyle,
                    .foregroundColor: UIColor.white.withAlphaComponent(Bool.random() ? 0.1 : 1.0)
                ]
                randomString.draw(with: CGRect(x: randomX, y: randomY, width: 20, height: 20), options: .usesLineFragmentOrigin, attributes: attrs, context: nil)
            }
        }
    }
}
