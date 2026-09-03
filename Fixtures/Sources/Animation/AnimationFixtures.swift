// Animation fixtures: goldens hold the end states (the harness disables animations); the
// motion between them is checked by unit tests and the browser probe.
import SwiftUI
import FixtureKit

/// Drives `animation/frame`, `animation/transition` and `animation/implicit`.
@Observable
public final class AnimationModel {
    public var expanded = false
    public var show = true
    public var inset: CGFloat = 0
    public var faded = false
    public init() {}
}

public enum AnimationFixtures {
    /// A box grows and shrinks under `withAnimation`; the text below moves with it.
    public static let frame = Fixture(
        "animation/frame", size: CGSize(width: 320, height: 160),
        model: { AnimationModel() },
        steps: [
            FixtureStep("expand") { model in withAnimation(.linear(duration: 0.3)) { model.expanded = true } },
            FixtureStep("collapse") { model in withAnimation(.easeInOut(duration: 0.3)) { model.expanded = false } },
        ]
    ) { model in
        VStack(spacing: 8) {
            Color.red.frame(width: model.expanded ? 200 : 100, height: model.expanded ? 60 : 40).probe("box")
            Text("Below").probe("below")
        }
        .probe("stack")
    }

    /// A text slides in and out with a transition under `withAnimation`.
    public static let transition = Fixture(
        "animation/transition", size: CGSize(width: 320, height: 160),
        model: { AnimationModel() },
        steps: [
            FixtureStep("hide") { model in withAnimation(.linear(duration: 0.3)) { model.show = false } },
            FixtureStep("show") { model in withAnimation(.linear(duration: 0.3)) { model.show = true } },
        ]
    ) { model in
        VStack(spacing: 8) {
            Text("Above").probe("above")
            if model.show {
                Text("Hello").transition(.move(edge: .leading)).probe("hello")
            }
            Text("Below").probe("below")
        }
        .probe("stack")
    }

    /// An implicit `.animation(value:)` moves a box when its inset changes (zero-length, because
    /// the modifier overrides the harness's animation-disabling transaction and a real duration
    /// would leave the golden pixels mid-flight); a fade uses `withAnimation`.
    public static let implicit = Fixture(
        "animation/implicit", size: CGSize(width: 320, height: 120),
        model: { AnimationModel() },
        steps: [
            FixtureStep("move") { $0.inset = 60 },
            FixtureStep("fade") { model in withAnimation(.linear(duration: 0.3)) { model.faded = true } },
        ]
    ) { model in
        HStack(alignment: .top, spacing: 12) {
            Color.blue.frame(width: 40, height: 40).opacity(model.faded ? 0.3 : 1).probe("faded")
            Color.green.frame(width: 40, height: 40).padding(.leading, model.inset).animation(.linear(duration: 0), value: model.inset).probe("moved")
        }
        .probe("row")
    }

    public static let all: [Fixture] = [frame, transition, implicit]
}
