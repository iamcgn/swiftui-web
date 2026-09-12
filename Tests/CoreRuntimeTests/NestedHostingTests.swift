// SwiftUI inside UIKit inside SwiftUI: a representable's controller hosts a UIHostingController;
// the inner tree paints at the outer node's position and takes presses through the outer
// runtime, the representable and the hosting view.
#if !os(WASI)
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless
import Foundation

@Suite @MainActor struct NestedHostingTests {
    @MainActor final class Model {
        var tapped = 0
    }

    struct Inner: View {
        let model: Model
        var body: some View {
            HStack(spacing: 0) {
                Color.red.frame(width: 40, height: 20)
                Color.blue.frame(width: 40, height: 20).onTapGesture { model.tapped += 1 }
            }
        }
    }

    final class Hosting: UIViewController {
        let model: Model
        init(_ model: Model) { self.model = model; super.init(nibName: nil, bundle: nil) }
        override func viewDidLoad() {
            super.viewDidLoad()
            let hosting = UIHostingController(rootView: Inner(model: model))
            addChild(hosting)
            hosting.view.frame = view.bounds
            hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(hosting.view)
            hosting.didMove(toParent: self)
        }
    }

    struct Outer: UIViewControllerRepresentable {
        let model: Model
        func makeUIViewController(context: Context) -> Hosting { Hosting(model) }
        func updateUIViewController(_ uiViewController: Hosting, context: Context) {}
    }

    @Test func innerTreePaintsAndTakesPresses() {
        var environment = EnvironmentValues()
        environment.platformProfile = .iOS
        let runtime = Runtime(environment: environment)
        runtime.textEngine = RecordedTextEngine(entries: [:])
        let model = Model()
        runtime.mount(Outer(model: model).frame(width: 80, height: 20).padding(10)._probe("outer"))
        runtime.layout(in: CGSize(width: 200, height: 100))
        let outer = runtime.probeFrames["outer"]!
        #expect(outer == CGRect(x: 50, y: 30, width: 100, height: 40))
        let commands = runtime.render(scale: 2).commands.map(\.description)
        // The inner runtime's list is concatenated at the hosted view's origin, in iOS's system colours.
        #expect(commands.contains("concat(1, 0, 0, 1, 60, 40)"), "\(commands)")
        #expect(commands.contains("fillRect(0, 0, 40, 20) #FF383C"), "\(commands)")
        #expect(commands.contains("fillRect(40, 0, 40, 20) #0088FF"), "\(commands)")
        runtime.pointerDown(at: CGPoint(x: 120, y: 50))
        runtime.pointerUp(at: CGPoint(x: 120, y: 50))
        #expect(model.tapped == 1)
    }
}
#endif
