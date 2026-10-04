// Phase 8 step 6, sw-animation: completion callbacks, spring initial velocity, reduce motion,
// ghosts inside containers that paint their own children, symbol content transitions
// (Docs/elements/Animation.md).
import Testing
import SwiftUI
import SwiftUIWebHeadless

#if !os(WASI)
@Observable private final class Model {
    var wide = false
    var rows = ["a", "b", "c"]
    var symbol = "star"
}

private struct Growing: View {
    let model: Model
    var body: some View { Color.red.frame(width: model.wide ? 100 : 50, height: 20) }
}

private struct Rows: View {
    let model: Model
    var body: some View {
        List {
            ForEach(model.rows, id: \.self) { row in Color.red.frame(height: 20)._probe(row) }
        }
    }
}

private struct Motion: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View { Text(reduceMotion ? "Still" : "Moving") }
}

@Suite @MainActor struct AnimationCompletionTests {
    private static let body = ResolvedFont(family: "system", size: 13, weight: .regular, italic: false, textStyle: nil)

    private func runtime<V: View>(_ view: V) -> Runtime {
        let runtime = Runtime()
        var entries: [String: RecordedTextEngine.Entry] = [:]
        for word in ["Still", "Moving"] {
            entries[RecordedTextEngine.key(font: Self.body, width: nil, string: word)] = .init(width: 40, height: 16, firstBaseline: 13, lastBaseline: 13)
        }
        runtime.textEngine = RecordedTextEngine(entries: entries)
        runtime.mount(view)
        runtime.layout(in: CGSize(width: 300, height: 200))
        return runtime
    }

    @Test func completionsFireWhenTheAnimationCompletes() async {
        let model = Model()
        let runtime = runtime(Growing(model: model))
        var completed = 0, removed = 0
        withAnimation(.linear(duration: 1).repeatCount(2, autoreverses: false)) { model.wide = true } completion: { completed += 1 }
        runtime.layout(in: CGSize(width: 300, height: 200))
        #expect(completed == 0 && runtime.isAnimating)
        // Logically complete after one duration, though the repeat still runs.
        _ = runtime.advanceAnimations(elapsed: 1.05)
        #expect(completed == 1 && runtime.isAnimating)
        _ = runtime.advanceAnimations(elapsed: 1)
        // Removed: only once the repeats have ended.
        withAnimation(.linear(duration: 1).repeatCount(2, autoreverses: false), completionCriteria: .removed) { model.wide = false } completion: { removed += 1 }
        runtime.layout(in: CGSize(width: 300, height: 200))
        _ = runtime.advanceAnimations(elapsed: 1.05)
        #expect(removed == 0)
        _ = runtime.advanceAnimations(elapsed: 1)
        #expect(removed == 1)
        // A change without an animation completes at once; one that invalidates nothing on the next turn.
        var plain = 0
        withAnimation(nil) { model.wide = true } completion: { plain += 1 }
        runtime.layout(in: CGSize(width: 300, height: 200))
        #expect(plain == 1)
        var idle = 0
        withAnimation { } completion: { idle += 1 }
        await Task.yield()
        #expect(idle == 1)
        // `Transaction.addAnimationCompletion` does the same through a transaction.
        var transacted = 0
        var transaction = Transaction()
        transaction.animation = .linear(duration: 0.5)
        transaction.addAnimationCompletion { transacted += 1 }
        withTransaction(transaction) { model.wide = false }
        runtime.layout(in: CGSize(width: 300, height: 200))
        _ = runtime.advanceAnimations(elapsed: 0.6)
        #expect(transacted == 1)
    }

    @Test func springsStartWithTheirInitialVelocity() {
        // A positive initial velocity gets ahead of the spring from rest early on.
        let still = Animation.interpolatingSpring(stiffness: 100, damping: 10)
        let moving = Animation.interpolatingSpring(stiffness: 100, damping: 10, initialVelocity: 8)
        #expect(moving.value(at: 0.05) > still.value(at: 0.05))
        #expect(abs(still.value(at: 0) - 0) < 1e-9 && abs(moving.value(at: 10) - 1) < 1e-3)
    }

    @Test func reduceMotionReachesTheEnvironment() {
        let runtime = runtime(Motion())
        #expect(runtime.render(scale: 2).commands.map(\.description).contains { $0.hasPrefix("drawText(\"Moving\"") })
        runtime.hostReducesMotion = true
        runtime.layout(in: CGSize(width: 300, height: 200))
        #expect(runtime.render(scale: 2).commands.map(\.description).contains { $0.hasPrefix("drawText(\"Still\"") })
    }

    @Test func removedListRowsLingerAsGhosts() {
        let model = Model()
        let runtime = runtime(Rows(model: model))
        let before = runtime.render(scale: 2).commands.map(\.description).filter { $0.contains("#FF383C") }.count
        withAnimation(.linear(duration: 1)) { model.rows = ["a", "c"] }
        runtime.layout(in: CGSize(width: 300, height: 200))
        #expect(runtime.probeFrames["b"] == nil)
        _ = runtime.advanceAnimations(elapsed: 0.5)
        // The removed row still paints (fading) through the list's own paint.
        let during = runtime.render(scale: 2).commands.map(\.description)
        #expect(during.filter { $0.contains("#FF383C") }.count == before)
        #expect(during.contains("beginGroup(opacity: 0.5)"))
        _ = runtime.advanceAnimations(elapsed: 0.6)
        #expect(runtime.render(scale: 2).commands.map(\.description).filter { $0.contains("#FF383C") }.count == before - 1)
    }

    @Test func symbolsCrossfadeUnderAContentTransition() {
        let model = Model()
        struct Icon: View {
            let model: Model
            var body: some View { Image(systemName: model.symbol).contentTransition(.symbolEffect(.replace)) }
        }
        let runtime = runtime(Icon(model: model))
        withAnimation(.linear(duration: 1)) { model.symbol = "heart" }
        runtime.layout(in: CGSize(width: 300, height: 200))
        _ = runtime.advanceAnimations(elapsed: 0.25)
        let painted = runtime.render(scale: 2).commands.map(\.description)
        #expect(painted.contains("beginGroup(opacity: 0.75)") && painted.contains("beginGroup(opacity: 0.25)"))
        _ = runtime.advanceAnimations(elapsed: 1)
        #expect(!runtime.render(scale: 2).commands.map(\.description).contains { $0.hasPrefix("beginGroup") })
    }
}
#endif
