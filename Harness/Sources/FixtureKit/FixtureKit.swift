// FixtureKit (real-SwiftUI side). The root package has a twin module with the same API built on
// SwiftUIWeb, so fixture sources compile unchanged against both.
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

public struct ProbeKey: PreferenceKey {
    public static let defaultValue: [String: CGRect] = [:]
    public static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

public let fixtureRootSpace = "fixtureRoot"

extension View {
    /// Records this view's frame (in the fixture root's coordinate space) under `id`.
    public func probe(_ id: String) -> some View {
        background(GeometryReader { proxy in
            Color.clear.preference(key: ProbeKey.self, value: [id: proxy.frame(in: .named(fixtureRootSpace))])
        })
    }
}
