// PhaseAnimator and KeyframeAnimator at rest: triggered animators show their first phase and
// initial value until the trigger changes, so the goldens capture plain layout.
import SwiftUI
import FixtureKit

public enum AnimatorFixtures {
    struct Pulse: Animatable {
        var scale: CGFloat = 1
        var offset: CGFloat = 0
        var animatableData: AnimatablePair<CGFloat, CGFloat> {
            get { AnimatablePair(scale, offset) }
            set { scale = newValue.first; offset = newValue.second }
        }
    }

    public static let phase = Fixture("animator/phase", size: CGSize(width: 300, height: 120), content: {
        HStack(spacing: 20) {
            Text("Pulse")
                .phaseAnimator([false, true], trigger: 0, content: { view, up in
                    view.scaleEffect(up ? 1.5 : 1).opacity(up ? 0.5 : 1)
                }, animation: { _ in .easeInOut(duration: 0.4) })
                .probe("text")
            Color.blue.frame(width: 40, height: 40)
                .phaseAnimator([0, 1, 2], trigger: 0) { view, phase in
                    view.offset(y: CGFloat(phase) * -10)
                }
                .probe("box")
        }
        .probe("row")
    })

    public static let keyframe = Fixture("animator/keyframe", size: CGSize(width: 300, height: 120), content: {
        Color.red.frame(width: 60, height: 40)
            .keyframeAnimator(initialValue: Pulse(), trigger: 0, content: { view, value in
                view.scaleEffect(value.scale).offset(y: value.offset)
            }) { _ in
                KeyframeTrack(\.scale) {
                    SpringKeyframe(1.3, duration: 0.2)
                    LinearKeyframe(1, duration: 0.3)
                }
                KeyframeTrack(\.offset) {
                    CubicKeyframe(-20, duration: 0.25)
                    CubicKeyframe(0, duration: 0.25)
                }
            }
            .probe("box")
    })

    public static let all: [Fixture] = [phase, keyframe]
}
