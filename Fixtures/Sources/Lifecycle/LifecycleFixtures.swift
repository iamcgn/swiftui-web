// Lifecycle fixtures: onAppear/onDisappear counts as a child comes and goes.
import SwiftUI
import FixtureKit

/// Drives `lifecycle/appear`.
@Observable
public final class LifecycleModel {
    public var appeared = 0
    public var disappeared = 0
    public var showChild = true
    public init() {}
}

public enum LifecycleFixtures {
    /// The counts text follows the child's appear and disappear actions.
    public static let appear = Fixture(
        "lifecycle/appear", size: CGSize(width: 320, height: 120),
        model: { LifecycleModel() },
        steps: [
            FixtureStep("hide") { $0.showChild = false },
            FixtureStep("show") { $0.showChild = true },
        ]
    ) { model in
        VStack(spacing: 8) {
            Text("A\(model.appeared) D\(model.disappeared)").probe("counts")
            if model.showChild {
                Text("Child")
                    .onAppear { model.appeared += 1 }
                    .onDisappear { model.disappeared += 1 }
                    .probe("child")
            }
        }
        .probe("stack")
    }

    // `.task` has no golden: the harness captures before the task's turn, the browser after it.

    public static let all: [Fixture] = [appear]
}
