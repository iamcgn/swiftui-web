// Geometry effects (Phase 2 opens): offset, rotation, scale and affine transforms paint through
// concat ops about their anchors, animate their parameters, and offsets move hit testing.
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless
import Foundation

#if !os(WASI)
@Suite @MainActor struct TransformTests {
    @Observable final class Model: @unchecked Sendable { var turned = false; var taps = 0; var show = true }

    private func commands(_ r: Runtime) -> [String] { r.render(scale: 2).commands.map(\.description) }

    /// The six numbers of a concat command.
    private func concat(_ command: String) -> [Double]? {
        guard command.hasPrefix("concat(") else { return nil }
        return command.dropFirst(7).dropLast().split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
    }

    private func near(_ a: [Double]?, _ b: [Double]) -> Bool {
        guard let a, a.count == b.count else { return false }
        return zip(a, b).allSatisfy { abs($0 - $1) < 1e-6 }
    }

    @Test func effectsPaintThroughTransforms() {
        let r = Runtime()
        r.mount(VStack(spacing: 0) {
            Color.red.frame(width: 40, height: 40).offset(x: 10, y: 6)
            Color.blue.frame(width: 40, height: 40).rotationEffect(.degrees(90), anchor: .topLeading)
            Color.green.frame(width: 40, height: 40).scaleEffect(2, anchor: .bottom)
            Color.gray.frame(width: 40, height: 40).transformEffect(CGAffineTransform(translationX: 5, y: 0))
        })
        r.layout(in: CGSize(width: 200, height: 200))
        let painted = commands(r)
        // The column is 40 × 160 at (80, 20). Offset: a translation; rotation about (80, 60);
        // scale about the bottom centre (100, 140); the affine transform about the origin (80, 140).
        let concats = painted.compactMap(concat)
        #expect(concats.contains { near($0, [1, 0, 0, 1, 10, 6]) })
        #expect(concats.contains { near($0, [0, 1, -1, 0, 140, -20]) })
        #expect(concats.contains { near($0, [2, 0, 0, 2, -100, -140]) })
        #expect(concats.contains { near($0, [1, 0, 0, 1, 5, 0]) })
        #expect(painted.filter { $0 == "save" }.count == 4 && painted.filter { $0 == "restore" }.count == 4)
    }

    struct Spinner: View {
        let model: Model
        var body: some View {
            Color.red.frame(width: 40, height: 40).rotationEffect(.degrees(model.turned ? 90 : 0))
        }
    }

    @Test func parametersAnimate() {
        let model = Model()
        let r = Runtime()
        r.mount(Spinner(model: model))
        r.layout(in: CGSize(width: 200, height: 200))
        #expect(!commands(r).contains { $0.hasPrefix("concat(") })
        withAnimation(.linear(duration: 1)) { model.turned = true }
        r.layout(in: CGSize(width: 200, height: 200))
        r.advanceAnimations(elapsed: 0.5)
        // Half way: 45°, cos = sin = 0.7071.
        let mid = commands(r).compactMap(concat).first!
        #expect(abs(mid[0] - 0.70710678) < 1e-6 && abs(mid[1] - 0.70710678) < 1e-6 && r.isAnimating)
        r.advanceAnimations(elapsed: 0.5)
        let end = commands(r).compactMap(concat).first!
        #expect(near(Array(end.prefix(4)), [0, 1, -1, 0]) && !r.isAnimating)
    }

    struct Tappable: View {
        let model: Model
        var body: some View {
            VStack {
                Button("Hit") { model.taps += 1 }.offset(x: 50, y: 0)
            }
        }
    }

    @Test func offsetMovesHitTesting() {
        let model = Model()
        let r = Runtime()
        r.mount(Tappable(model: model))
        r.layout(in: CGSize(width: 200, height: 100))
        // The button's frame is centred; its painted position is 50 to the right.
        let button = r.semanticsTree().first { $0.label == "Hit" }!.frame
        r.pointerDown(at: CGPoint(x: button.midX, y: button.midY)); r.pointerUp(at: CGPoint(x: button.midX, y: button.midY))
        #expect(model.taps == 0)
        r.pointerDown(at: CGPoint(x: button.midX + 50, y: button.midY)); r.pointerUp(at: CGPoint(x: button.midX + 50, y: button.midY))
        #expect(model.taps == 1)
    }

    struct Scaling: View {
        let model: Model
        var body: some View { VStack { if model.show { Color.red.frame(width: 40, height: 40).transition(.scale) } } }
    }

    @Test func scaleTransitionShrinksTheGhost() {
        let model = Model()
        let r = Runtime()
        r.mount(Scaling(model: model))
        r.layout(in: CGSize(width: 200, height: 200))
        withAnimation(.linear(duration: 1)) { model.show = false }
        r.layout(in: CGSize(width: 200, height: 200))
        r.advanceAnimations(elapsed: 0.5)
        // Removal at half way: the ghost paints at scale 0.5 about its centre, which follows the
        // shrinking stack (110, 110 at half way).
        #expect(commands(r).compactMap(concat).contains { near($0, [0.5, 0, 0, 0.5, 55, 55]) })
        r.advanceAnimations(elapsed: 0.5)
        #expect(!commands(r).contains { $0.contains("#FF383C") })
    }
}
#endif
