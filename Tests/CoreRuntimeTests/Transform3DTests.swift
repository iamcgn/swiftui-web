// Phase 8 step 6, sw-transform3d: 3D rotations and projections paint their affine part, custom
// geometry effects animate, hit testing follows rotations and scales, scale transitions keep
// their anchor (Docs/elements/Transform.md).
import Testing
import SwiftUI
import SwiftUIWebHeadless
import Foundation

#if !os(WASI)
@MainActor private final class Counter { var taps = 0 }
@Observable private final class Model { var skew: CGFloat = 0; var shown = true }

private struct Skew: GeometryEffect {
    var amount: CGFloat
    var animatableData: CGFloat {
        get { amount }
        set { amount = newValue }
    }
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(a: 1, b: 0, c: amount, d: 1, tx: 0, ty: 0))
    }
}

private struct Skewed: View {
    let model: Model
    var body: some View { Color.red.frame(width: 40, height: 40).modifier(Skew(amount: model.skew)) }
}

@Suite @MainActor struct Transform3DTests {
    private func runtime<V: View>(_ view: V) -> Runtime {
        let runtime = Runtime()
        runtime.textEngine = RecordedTextEngine(entries: [:])
        runtime.mount(view)
        runtime.layout(in: CGSize(width: 200, height: 200))
        return runtime
    }

    private func concat(_ runtime: Runtime) -> String? {
        runtime.render(scale: 2).commands.map(\.description).first { $0.hasPrefix("concat(") }
    }

    /// The transform's six numbers, or nil (floating-point noise rounded away).
    private func matrix(_ runtime: Runtime) -> [Double]? {
        guard let text = concat(runtime) else { return nil }
        let inner = text.dropFirst("concat(".count).dropLast()
        return inner.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }.map { ($0 * 1000).rounded() / 1000 }
    }

    @Test func rotations3DAndProjectionsPaintTheirAffinePart() {
        // About the vertical axis a 60° turn halves the width (cos 60° = 0.5) about the centre.
        let y = runtime(Color.red.frame(width: 40, height: 40).rotation3DEffect(.degrees(60), axis: (x: 0, y: 1, z: 0)))
        #expect(matrix(y)?.prefix(4) == [0.5, 0, 0, 1])
        // About the depth axis it is a plain rotation.
        let z = runtime(Color.red.frame(width: 40, height: 40).rotation3DEffect(.degrees(90), axis: (x: 0, y: 0, z: 1)))
        #expect(matrix(z)?.prefix(4) == [0, 1, -1, 0])
        let projected = runtime(Color.red.frame(width: 40, height: 40).projectionEffect(ProjectionTransform(CGAffineTransform(a: 1, b: 0, c: 0.5, d: 1, tx: 0, ty: 0))))
        #expect(matrix(projected)?.prefix(4) == [1, 0, 0.5, 1])
        #expect(ProjectionTransform(CGAffineTransform(scaleX: 2, y: 3)).affine == CGAffineTransform(scaleX: 2, y: 3))
        #expect(!ProjectionTransform(CGAffineTransform(scaleX: 2, y: 3)).isIdentity && ProjectionTransform().isIdentity)
    }

    @Test func geometryEffectsAnimateTheirData() {
        let model = Model()
        let runtime = runtime(Skewed(model: model))
        #expect(concat(runtime) == nil)
        withAnimation(.linear(duration: 1)) { model.skew = 1 }
        runtime.layout(in: CGSize(width: 200, height: 200))
        _ = runtime.advanceAnimations(elapsed: 0.5)
        #expect(matrix(runtime)?.prefix(4) == [1, 0, 0.5, 1])
        _ = runtime.advanceAnimations(elapsed: 0.6)
        #expect(matrix(runtime)?.prefix(4) == [1, 0, 1, 1] && !runtime.isAnimating)
    }

    @Test func hitTestingFollowsRotationsAndScales() {
        let counter = Counter()
        let runtime = runtime(VStack {
            Button(action: { counter.taps += 1 }) { Color.red.frame(width: 40, height: 10) }.buttonStyle(.plain)
                .rotationEffect(.degrees(90))._probe("rotated")
            Button(action: { counter.taps += 10 }) { Color.blue.frame(width: 10, height: 10) }.buttonStyle(.plain)
                .scaleEffect(3)._probe("scaled")
        })
        let rotated = runtime.probeFrames["rotated"]!
        // Turned 90° about its centre the bar stands upright: a press at its centre 15 above hits, 15 beside misses.
        runtime.pointerDown(at: CGPoint(x: rotated.midX, y: rotated.midY - 15)); runtime.pointerUp(at: CGPoint(x: rotated.midX, y: rotated.midY - 15))
        #expect(counter.taps == 1)
        runtime.pointerDown(at: CGPoint(x: rotated.midX + 15, y: rotated.midY)); runtime.pointerUp(at: CGPoint(x: rotated.midX + 15, y: rotated.midY))
        #expect(counter.taps == 1)
        // Scaled three times the square takes presses 12 from its centre.
        let scaled = runtime.probeFrames["scaled"]!
        runtime.pointerDown(at: CGPoint(x: scaled.midX + 12, y: scaled.midY)); runtime.pointerUp(at: CGPoint(x: scaled.midX + 12, y: scaled.midY))
        #expect(counter.taps == 11)
    }

    @Test func scaleTransitionsKeepTheirAnchor() {
        let model = Model()
        struct Appearing: View {
            let model: Model
            var body: some View {
                VStack(spacing: 0) { if model.shown { Color.red.frame(width: 40, height: 40).transition(.scale(0.5, anchor: .topLeading)) } }
            }
        }
        let runtime = runtime(Appearing(model: model))
        withAnimation(.linear(duration: 1)) { model.shown = false }
        runtime.layout(in: CGSize(width: 200, height: 200))
        _ = runtime.advanceAnimations(elapsed: 0.5)
        // Halfway the ghost is scaled 0.75 about its top leading corner (90, 90): the corner
        // stays put, so the translation is a quarter of it.
        #expect(matrix(runtime) == [0.75, 0, 0, 0.75, 22.5, 22.5])
    }
}
#endif
