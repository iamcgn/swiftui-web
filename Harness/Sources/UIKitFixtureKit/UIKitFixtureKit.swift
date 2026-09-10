// UIKitFixtureKit (real-UIKit side, Mac Catalyst). UIKitWeb has a twin module with the same
// API, so the UIKit fixture sources compile unchanged against both (decision 0014).
#if canImport(UIKit)
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

/// A fixture instantiated for one render session: the controller that owns its root view, and
/// the steps bound to the model it reads. Each instantiation gets a fresh model.
@MainActor
public struct UIKitFixtureInstance {
    public struct BoundStep {
        public let name: String
        public let run: @MainActor () -> Void
    }
    public let controller: UIViewController
    public let steps: [BoundStep]
}

/// A UIKit fixture: a name (`uikit/…`, its goldens directory), a size, and the root view or
/// controller it shows.
public struct UIKitFixture: Sendable {
    public let name: String
    public let size: CGSize
    public let stepNames: [String]
    public let instantiate: @MainActor @Sendable () -> UIKitFixtureInstance
    /// The appearance the fixture is rendered in.
    public var style: UIUserInterfaceStyle = .light

    public func style(_ style: UIUserInterfaceStyle) -> UIKitFixture {
        var copy = self
        copy.style = style
        return copy
    }

    /// A layout fixture: a root view laid out in a plain controller.
    public init(_ name: String, size: CGSize = CGSize(width: 320, height: 300), content: @escaping @MainActor @Sendable () -> UIView) {
        self.name = name
        self.size = size
        self.stepNames = []
        self.instantiate = { UIKitFixtureInstance(controller: UIKitFixtureController(content()), steps: []) }
    }

    /// A fixture whose root is a view controller.
    public init(_ name: String, size: CGSize = CGSize(width: 320, height: 300), controller: @escaping @MainActor @Sendable () -> UIViewController) {
        self.name = name
        self.size = size
        self.stepNames = []
        self.instantiate = { UIKitFixtureInstance(controller: controller(), steps: []) }
    }

    /// A behaviour fixture: the view is built from a model; each step mutates the model and the
    /// tree as an app would, and the golden records frames and pixels after every step.
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
}

/// The controller a view fixture is hosted in: the fixture view is its view, transparent.
@MainActor
public final class UIKitFixtureController: UIViewController {
    private let content: UIView

    public init(_ content: UIView) {
        self.content = content
        super.init(nibName: nil, bundle: nil)
    }

    public required init?(coder: NSCoder) { nil }

    public override func loadView() {
        view = content
    }
}

/// The probe registry: every `probe(_:)` call records its view; the host reads the frames
/// relative to the fixture's root view after layout.
@MainActor
public enum UIKitProbes {
    private struct Entry { let id: String; weak var view: UIView? }
    private static var entries: [Entry] = []

    static func register(_ id: String, _ view: UIView) {
        entries.removeAll { $0.id == id || $0.view == nil }
        entries.append(Entry(id: id, view: view))
    }

    public static func reset() { entries.removeAll() }

    /// The probes' frames in `root`'s coordinates.
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
    /// Records this view's frame (in the fixture root's coordinates) under `id`.
    @discardableResult
    public func probe(_ id: String) -> Self {
        UIKitProbes.register(id, self)
        return self
    }
}
#endif
