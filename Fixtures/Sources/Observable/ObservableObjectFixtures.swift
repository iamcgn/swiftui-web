// ObservableObject fixture: a view observing a class with @Published properties through
// @ObservedObject re-renders when they change; a Toggle binds through the projected value.
import SwiftUI
import FixtureKit

public final class CounterObject: ObservableObject {
    @Published public var count = 0
    @Published public var flag = false
    public init() {}
}

struct ObservedCounter: View {
    @ObservedObject var model: CounterObject
    var body: some View {
        VStack(spacing: 8) {
            Text("Count: \(model.count)").probe("count")
            Toggle("Flag", isOn: $model.flag).probe("toggle")
        }
    }
}

public enum ObservableObjectFixtures {
    public static let object = Fixture(
        "observable/object", size: CGSize(width: 320, height: 120),
        model: { CounterObject() },
        steps: [
            FixtureStep("increment") { $0.count += 1 },
            FixtureStep("flag") { $0.flag = true },
        ]
    ) { model in
        ObservedCounter(model: model).probe("view")
    }

    public static let all: [Fixture] = [object]
}
