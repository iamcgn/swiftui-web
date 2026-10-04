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

    /// A 3D rotation about the depth axis, a projection and a custom `GeometryEffect`. Rotations
    /// about the x and y axes are not capturable (the harness's `cacheDisplay` drops or misplaces
    /// the layers Apple turns in perspective), so they stay out and are unit-tested only.
    public static let threeD = Fixture("transform/3d", size: CGSize(width: 320, height: 200)) {
        VStack(spacing: 30) {
            HStack(spacing: 40) {
                Color.green.frame(width: 40, height: 40).rotation3DEffect(.degrees(45), axis: (x: 0, y: 0, z: 1)).probe("aboutZ")
            }
            .probe("row1")
            HStack(spacing: 40) {
                Color.orange.frame(width: 40, height: 40).projectionEffect(ProjectionTransform(CGAffineTransform(a: 1, b: 0, c: 0.5, d: 1, tx: 0, ty: 0))).probe("projected")
                Color.purple.frame(width: 40, height: 40).modifier(FixtureSkew(amount: 0.4)).probe("skewed")
            }
            .probe("row2")
        }
        .probe("stack")
    }

    public static let all: [Fixture] = [basic, steps, threeD]
}

/// A custom geometry effect: a horizontal skew by `amount` of the height.
public struct FixtureSkew: GeometryEffect {
    public var amount: CGFloat
    public init(amount: CGFloat) { self.amount = amount }
    public var animatableData: CGFloat {
        get { amount }
        set { amount = newValue }
    }
    public func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(a: 1, b: 0, c: amount, d: 1, tx: -amount * size.height / 2, ty: 0))
    }
}
