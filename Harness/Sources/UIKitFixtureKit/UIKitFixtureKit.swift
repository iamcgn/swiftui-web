// UIKitFixtureKit (real-UIKit side, Mac Catalyst). UIKitWeb has a twin module with the same
// API, so the UIKit fixture sources compile unchanged against both (decision 0014).
#if canImport(UIKit)
import UIKit
import ImageIO

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
    public private(set) var name: String
    public let size: CGSize
    public let stepNames: [String]
    public let instantiate: @MainActor @Sendable () -> UIKitFixtureInstance
    /// The appearance the fixture is rendered in.
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

// MARK: - Catalog images

/// Named images from `Fixtures/Assets.xcassets` for real UIKit (decision 0011: the SwiftPM
/// harness has no compiled catalog, so `UIImage(named:)` finds nothing): the universal 2×
/// variant of the light appearance, decoded with `UIImage(cgImage:scale:orientation:)`, as a
/// template when the set says so. UIKitWeb's kit answers the same call with `UIImage(named:)`.
public enum UIKitFixtureImage {
    static let root: URL = {
        var url = URL(fileURLWithPath: #filePath)
        while url.lastPathComponent != "Harness" { url.deleteLastPathComponent() }
        url.deleteLastPathComponent()
        return url.appendingPathComponent("Fixtures/Assets.xcassets")
    }()

    private struct Variant { let url: URL; let scale: CGFloat; let idiom: String; let appearance: String }
    nonisolated(unsafe) private static var sets: [String: (variants: [Variant], template: Bool)] = [:]
    nonisolated(unsafe) private static var loaded = false

    private static func contents(_ directory: URL) -> [String: Any] {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("Contents.json")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return json
    }

    private static func walk(_ directory: URL, prefix: String) {
        let children = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let name = prefix + child.deletingPathExtension().lastPathComponent
            switch child.pathExtension {
            case "imageset":
                let doc = contents(child)
                var variants: [Variant] = []
                for entry in doc["images"] as? [[String: Any]] ?? [] {
                    guard let filename = entry["filename"] as? String else { continue }
                    let scaleText = (entry["scale"] as? String ?? "1x").dropLast()
                    var appearance = "any"
                    for item in entry["appearances"] as? [[String: Any]] ?? [] where item["appearance"] as? String == "luminosity" { appearance = item["value"] as? String ?? "any" }
                    variants.append(Variant(url: child.appendingPathComponent(filename), scale: CGFloat(Double(scaleText) ?? 1), idiom: entry["idiom"] as? String ?? "universal", appearance: appearance))
                }
                let template = ((doc["properties"] as? [String: Any])?["template-rendering-intent"] as? String) == "template"
                sets[name] = (variants, template)
            case "":
                let namespace = (contents(child)["properties"] as? [String: Any])?["provides-namespace"] as? Bool ?? false
                walk(child, prefix: namespace ? name + "/" : prefix)
            default: break
            }
        }
    }

    /// The catalog image named `name`, nil when there is none.
    public static func named(_ name: String) -> UIImage? {
        if !loaded { loaded = true; walk(root, prefix: "") }
        guard let set = sets[name] else { return nil }
        let universal = set.variants.filter { $0.idiom == "universal" && ($0.appearance == "any" || $0.appearance == "light") }
        guard let variant = universal.first(where: { $0.scale == 2 }) ?? universal.max(by: { $0.scale < $1.scale }),
              let source = CGImageSourceCreateWithURL(variant.url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let image = UIImage(cgImage: cgImage, scale: variant.scale, orientation: .up)
        return set.template ? image.withRenderingMode(.alwaysTemplate) : image
    }
}
#endif
