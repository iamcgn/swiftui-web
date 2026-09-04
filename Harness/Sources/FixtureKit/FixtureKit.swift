// FixtureKit (real-SwiftUI side). The root package has a twin module with the same API built on
// SwiftUIWeb, so fixture sources compile unchanged against both.
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
