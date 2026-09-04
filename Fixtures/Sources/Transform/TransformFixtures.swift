// Transform effect fixtures: offset, rotation, scale and an affine transform leave the layout
// alone (frames unchanged) and move the pixels; a behaviour fixture animates them.
import SwiftUI
import FixtureKit

@Observable
public final class TransformModel {
    public var turned = false
    public init() {}
}

public enum TransformFixtures {
    public static let basic = Fixture("transform/basic", size: CGSize(width: 320, height: 260)) {
        VStack(spacing: 24) {
            HStack(spacing: 40) {
                Color.red.frame(width: 40, height: 40).offset(x: 10, y: 6).probe("offset")
                Color.blue.frame(width: 40, height: 40).rotationEffect(.degrees(45)).probe("rotated")
                Color.green.frame(width: 40, height: 40).scaleEffect(1.5).probe("scaled")
            }
            .probe("row1")
            HStack(spacing: 40) {
                Color.orange.frame(width: 40, height: 40).rotationEffect(.degrees(30), anchor: .topLeading).probe("anchored")
                Color.purple.frame(width: 40, height: 40).scaleEffect(x: 2, y: 0.5, anchor: .bottom).probe("stretched")
                Text("Tilt").rotationEffect(.degrees(-20)).probe("text")
            }
            .probe("row2")
            Color.gray.frame(width: 60, height: 20).transformEffect(CGAffineTransform(translationX: 20, y: -4)).probe("affine")
        }
        .probe("stack")
    }

    public static let steps = Fixture(
        "transform/steps", size: CGSize(width: 320, height: 120),
        model: { TransformModel() },
        steps: [FixtureStep("turn") { model in withAnimation(.linear(duration: 0.3)) { model.turned = true } }]
    ) { model in
        HStack(spacing: 40) {
            Color.red.frame(width: 40, height: 40).rotationEffect(.degrees(model.turned ? 90 : 0)).probe("spin")
            Color.blue.frame(width: 40, height: 40).scaleEffect(model.turned ? 1.5 : 1).probe("grow")
            Color.green.frame(width: 40, height: 40).offset(x: model.turned ? 20 : 0).probe("slide")
        }
        .probe("row")
    }

    public static let all: [Fixture] = [basic, steps]
}
