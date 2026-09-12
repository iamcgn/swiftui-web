// UIKitFixtureKit (UIKitWeb side). The harness has a twin module with the same API built on
// real UIKit (Mac Catalyst), so the UIKit fixture sources compile unchanged against both.
import UIKit

/// One mutation of a behaviour fixture's model, applied between renders.
public struct UIKitFixtureStep<Model>: Sendable {
    public let name: String
    public let run: @MainActor @Sendable (Model) -> Void

    public init(_ name: String, _ run: @escaping @MainActor @Sendable (Model) -> Void) {
        self.name = name
        self.run = run
    }
}

/// A fixture instantiated for one render session.
@MainActor
public struct UIKitFixtureInstance {
    public struct BoundStep {
        public let name: String
        public let run: @MainActor () -> Void
    }
    public let controller: UIViewController
    public let steps: [BoundStep]
}

public struct UIKitFixture: Sendable {
    public private(set) var name: String
    public let size: CGSize
    public let stepNames: [String]
    public let instantiate: @MainActor @Sendable () -> UIKitFixtureInstance
    public var style: UIUserInterfaceStyle = .light
    /// Whether the golden captures the whole window (presented alerts and sheets live beside the
    /// root controller's view, not in it) and its probes are relative to the window.
    public var capturesWindow = false

    public func style(_ style: UIUserInterfaceStyle) -> UIKitFixture {
        var copy = self
        copy.style = style
        return copy
    }

    /// The same fixture under another name (a dark twin of a light fixture).
    public func renamed(_ name: String) -> UIKitFixture {
        var copy = self
        copy.name = name
        return copy
    }

    public func capturesWindow(_ flag: Bool = true) -> UIKitFixture {
        var copy = self
        copy.capturesWindow = flag
        return copy
    }

    public init(_ name: String, size: CGSize = CGSize(width: 320, height: 300), content: @escaping @MainActor @Sendable () -> UIView) {
        self.name = name
        self.size = size
        self.stepNames = []
        self.instantiate = { UIKitFixtureInstance(controller: UIKitFixtureController(content()), steps: []) }
    }

    public init(_ name: String, size: CGSize = CGSize(width: 320, height: 300), controller: @escaping @MainActor @Sendable () -> UIViewController) {
        self.name = name
        self.size = size
        self.stepNames = []
        self.instantiate = { UIKitFixtureInstance(controller: controller(), steps: []) }
    }

    public init<Model: AnyObject>(_ name: String, size: CGSize = CGSize(width: 320, height: 300),
                                  model: @escaping @MainActor @Sendable () -> Model,
                                  steps: [UIKitFixtureStep<Model>],
                                  content: @escaping @MainActor @Sendable (Model) -> UIView) {
        self.name = name
        self.size = size
        self.stepNames = steps.map(\.name)
        self.instantiate = {
            let model = model()
            return UIKitFixtureInstance(controller: UIKitFixtureController(content(model)),
                                        steps: steps.map { step in .init(name: step.name, run: { @MainActor in step.run(model) }) })
        }
    }

    /// A behaviour fixture around a view controller (a navigation or tab bar controller).
    public init<Model: AnyObject>(_ name: String, size: CGSize = CGSize(width: 320, height: 300),
                                  model: @escaping @MainActor @Sendable () -> Model,
                                  steps: [UIKitFixtureStep<Model>],
                                  controller: @escaping @MainActor @Sendable (Model) -> UIViewController) {
        self.name = name
        self.size = size
        self.stepNames = steps.map(\.name)
        self.instantiate = {
            let model = model()
            return UIKitFixtureInstance(controller: controller(model),
                                        steps: steps.map { step in .init(name: step.name, run: { @MainActor in step.run(model) }) })
        }
    }
}

/// The controller a view fixture is hosted in: the fixture view is its view.
@MainActor
public final class UIKitFixtureController: UIViewController {
    private let content: UIView

    public init(_ content: UIView) {
        self.content = content
        super.init(nibName: nil, bundle: nil)
    }

    public override func loadView() {
        view = content
    }
}

/// The probe registry (the same as the harness's).
@MainActor
public enum UIKitProbes {
    private struct Entry { let id: String; weak var view: UIView? }
    private static var entries: [Entry] = []

    static func register(_ id: String, _ view: UIView) {
        entries.removeAll { $0.id == id || $0.view == nil }
        entries.append(Entry(id: id, view: view))
    }

    public static func reset() { entries.removeAll() }

    public static func frames(in root: UIView) -> [String: CGRect] {
        var frames: [String: CGRect] = [:]
        for entry in entries {
            guard let view = entry.view, view.isDescendant(of: root) || view === root else { continue }
            frames[entry.id] = view.convert(view.bounds, to: root)
        }
        return frames
    }
}

extension UIView {
    @discardableResult
    public func probe(_ id: String) -> Self {
        UIKitProbes.register(id, self)
        return self
    }
}

/// Drives a fixture in the scene without a host: mounts it in a window of the fixture size,
/// lays out with the given text engine, and returns the probe frames (Tier A).
@MainActor
public final class UIKitFixtureRunner {
    public let fixture: UIKitFixture
    public let instance: UIKitFixtureInstance
    private let window: UIWindow

    public init(_ fixture: UIKitFixture, textEngine: (any TextEngine)? = nil, assets: AssetCatalog = .empty) {
        self.fixture = fixture
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        UIKitProbes.reset()
        if let textEngine { scene.textEngine = textEngine }
        scene.assetCatalog = assets
        scene.configureScreen(size: fixture.size, scale: 2)
        scene.hostColorScheme = fixture.style == .dark ? .dark : .light
        instance = fixture.instantiate()
        window = UIWindow(frame: CGRect(origin: .zero, size: fixture.size))
        window.overrideUserInterfaceStyle = fixture.style
        window.rootViewController = instance.controller
        window.makeKeyAndVisible()
    }

    /// Lays out at the fixture size and returns the probe frames relative to the root view (or
    /// the window, for a fixture that captures it).
    public func layoutFrames() -> [String: CGRect] {
        UIKitScene.shared.layout(in: fixture.size)
        return UIKitProbes.frames(in: fixture.capturesWindow ? window : instance.controller.view)
    }

    /// Paints the laid-out fixture into a display list at `scale`.
    public func render(scale: CGFloat = 2) -> DisplayList {
        UIKitScene.shared.layout(in: fixture.size)
        return UIKitScene.shared.render(scale: scale, background: false)
    }

    public func apply(step index: Int) {
        instance.steps[index].run()
    }
}
