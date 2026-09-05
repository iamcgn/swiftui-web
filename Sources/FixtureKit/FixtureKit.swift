// FixtureKit (SwiftUIWeb side). The harness has a twin module with the same API built on Apple's
// SwiftUI, so fixture sources compile unchanged against both.
import SwiftUI

/// One mutation of a behaviour fixture's model, applied between renders.
public struct FixtureStep<Model>: Sendable {
    public let name: String
    public let run: @MainActor @Sendable (Model) -> Void

    public init(_ name: String, _ run: @escaping @MainActor @Sendable (Model) -> Void) {
        self.name = name
        self.run = run
    }
}

/// A fixture instantiated for one render session: its root view and the steps bound to the
/// model that view observes. Each instantiation gets a fresh model.
public struct FixtureInstance {
    public struct BoundStep {
        public let name: String
        public let run: @MainActor () -> Void
    }
    public let view: AnyView
    public let steps: [BoundStep]
}

/// The platform a fixture's goldens come from (and the profile the runtime reproduces).
public enum FixturePlatform: String, Sendable {
    case macOS, iOS
}

public struct Fixture: Sendable {
    public let name: String            // e.g. "text/hello"; becomes Fixtures/Goldens/text/hello/
    public let size: CGSize
    /// Names of the behaviour steps, in order; empty for layout-only fixtures.
    public let stepNames: [String]
    public let instantiate: @MainActor @Sendable () -> FixtureInstance
    /// The appearance the fixture is rendered in (the harness sets the window's appearance and
    /// the environment; the runtime sets its root environment).
    public var colorScheme: ColorScheme = .light

    /// The same fixture rendered in `scheme`.
    public func colorScheme(_ scheme: ColorScheme) -> Fixture {
        var copy = self
        copy.colorScheme = scheme
        return copy
    }

    /// The platform whose look the fixture is rendered in: macOS goldens come from an AppKit
    /// window, iOS ones from a UIKit window on Mac Catalyst (`scripts/gen-goldens-ios.sh`); the
    /// runtime sets its platform profile to match. iOS fixtures are named `ios/…`.
    public var platform: FixturePlatform = .macOS

    /// The same fixture rendered for `platform`.
    public func platform(_ platform: FixturePlatform) -> Fixture {
        var copy = self
        copy.platform = platform
        return copy
    }

    /// Whether the harness rasterises the fixture through SwiftUI's own renderer (`drawingGroup`)
    /// instead of the window's layer tree: layer filters (colour effects, blur, blend modes) are
    /// applied by the render server on screen and skipped by an offscreen capture, while the
    /// rasteriser draws them. AppKit-backed views do not draw in a rasterised fixture.
    public var rasterized = false

    /// The same fixture captured through SwiftUI's rasteriser.
    public func rasterized(_ flag: Bool = true) -> Fixture {
        var copy = self
        copy.rasterized = flag
        return copy
    }

    /// The root view of a fresh instance.
    public var content: @MainActor @Sendable () -> AnyView {
        let instantiate = instantiate
        return { instantiate().view }
    }

    /// A layout fixture: a static view.
    public init<V: View>(_ name: String, size: CGSize = CGSize(width: 400, height: 300),
                         @ViewBuilder content: @escaping @MainActor @Sendable () -> V) {
        self.name = name
        self.size = size
        self.stepNames = []
        self.instantiate = { FixtureInstance(view: AnyView(content()), steps: []) }
    }

    /// A behaviour fixture: the view reads an observable `model`; each step mutates it, and the
    /// golden records frames and pixels after every step.
    public init<Model: AnyObject, V: View>(_ name: String, size: CGSize = CGSize(width: 400, height: 300),
                                           model: @escaping @MainActor @Sendable () -> Model,
                                           steps: [FixtureStep<Model>],
                                           @ViewBuilder content: @escaping @MainActor @Sendable (Model) -> V) {
        self.name = name
        self.size = size
        self.stepNames = steps.map(\.name)
        self.instantiate = {
            let model = model()
            return FixtureInstance(view: AnyView(_ModelView(model: model, content: content)),
                                   steps: steps.map { step in .init(name: step.name, run: { @MainActor in step.run(model) }) })
        }
    }
}

/// Reads the model inside a `body`, so observation re-renders the fixture after each step.
public struct _ModelView<Model: AnyObject, Content: View>: View {
    let model: Model
    let content: @MainActor @Sendable (Model) -> Content

    public var body: some View { content(model) }
}

public struct ProbeKey: PreferenceKey {
    public static let defaultValue: [String: CGRect] = [:]
    public static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

public let fixtureRootSpace = "fixtureRoot"

extension View {
    /// Records this view's frame (in the fixture root's coordinate space) under `id`.
    /// Identical on both sides, so the whole GeometryReader/preference chain is exercised by
    /// every fixture.
    public func probe(_ id: String) -> some View {
        background(GeometryReader { proxy in
            Color.clear.preference(key: ProbeKey.self, value: [id: proxy.frame(in: .named(fixtureRootSpace))])
        })
    }
}

// MARK: - Running fixtures on SwiftUIWeb

@MainActor
private final class FrameCollector {
    var frames: [String: CGRect] = [:]
}

/// A fixture mounted in its own runtime. Lays out on demand and applies behaviour steps.
@MainActor
public final class FixtureRunner {
    public let fixture: Fixture
    public let runtime: Runtime
    private let instance: FixtureInstance
    private let collector = FrameCollector()

    public init(_ fixture: Fixture, textEngine: (any TextEngine)? = nil, assets: AssetCatalog = .empty) {
        self.fixture = fixture
        var environment = EnvironmentValues()
        environment.colorScheme = fixture.colorScheme
        runtime = Runtime(environment: environment)
        if let textEngine { runtime.textEngine = textEngine }
        runtime.assetCatalog = assets
        instance = fixture.instantiate()
        let collector = collector
        runtime.mount(
            instance.view
                .frame(width: fixture.size.width, height: fixture.size.height)
                .coordinateSpace(name: fixtureRootSpace)
                .onPreferenceChange(ProbeKey.self) { collector.frames = $0 })
    }

    /// Applies pending updates, lays out at the fixture size and returns the probe frames.
    public func layoutFrames() -> [String: CGRect] {
        runtime.layout(in: fixture.size)
        return collector.frames
    }

    /// Runs step `index` (0-based) against the instance's model.
    public func apply(step index: Int) {
        instance.steps[index].run()
    }
}

extension Fixture {
    /// Mounts the fixture in a fresh runtime, lays it out at its size and returns the probe frames.
    @MainActor
    public func layoutFrames(textEngine: (any TextEngine)? = nil, assets: AssetCatalog = .empty) -> [String: CGRect] {
        FixtureRunner(self, textEngine: textEngine, assets: assets).layoutFrames()
    }
}
