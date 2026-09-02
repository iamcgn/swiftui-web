// FixtureKit (SwiftUIWeb side). The harness has a twin module with the same API built on Apple's
// SwiftUI, so fixture sources compile unchanged against both.
import SwiftUI

public struct Fixture: Sendable {
    public let name: String            // e.g. "text/hello"; becomes Fixtures/Goldens/text/hello/
    public let size: CGSize
    public let content: @MainActor @Sendable () -> AnyView

    public init<V: View>(_ name: String, size: CGSize = CGSize(width: 400, height: 300),
                         @ViewBuilder content: @escaping @MainActor @Sendable () -> V) {
        self.name = name
        self.size = size
        self.content = { AnyView(content()) }
    }
}

public let fixtureRootSpace = "fixtureRoot"

extension View {
    /// Records this view's frame (in the fixture root's coordinate space) under `id`.
    public func probe(_ id: String) -> some View {
        _probe(id)
    }
}

extension Fixture {
    /// Mounts the fixture in a fresh runtime, lays it out at its size and returns the probe frames.
    @MainActor
    public func layoutFrames(textEngine: (any TextEngine)? = nil) -> [String: CGRect] {
        let runtime = Runtime()
        if let textEngine { runtime.textEngine = textEngine }
        runtime.mount(content().frame(width: size.width, height: size.height))
        runtime.layout(in: size)
        return runtime.probeFrames
    }
}
