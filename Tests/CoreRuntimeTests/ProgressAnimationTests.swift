// Phase 8 step 6, sw-progress: the spinner's rotation and the indeterminate bar's motion,
// animated progress and gauge values, timer intervals, Progress objects and tint
// (Docs/elements/ProgressView.md, Docs/elements/Gauge.md).
import Testing
import SwiftUI
import SwiftUIWebHeadless
import Foundation

#if !os(WASI)
@Observable private final class Model { var value = 0.2 }

#if os(Linux)
// corelibs Foundation exposes a read-only description; override it for the same label fixture.
private final class NamedProgress: Progress, @unchecked Sendable {
    override var localizedDescription: String { "Copying" }
}
#endif

/// The values read in a body, so a change re-evaluates it.
private struct Values: View {
    let model: Model
    var body: some View {
        VStack {
            ProgressView(value: model.value)
            Gauge(value: model.value, in: 0...1) { Text("Level") }
        }
    }
}

@Suite @MainActor struct ProgressAnimationTests {
    private func runtime<V: View>(_ view: V, iOS: Bool = false) -> Runtime {
        var environment = EnvironmentValues()
        if iOS { environment.platformProfile = .iOS }
        let runtime = Runtime(environment: environment)
        runtime.textEngine = RecordedTextEngine(entries: [:])
        runtime.mount(view)
        runtime.layout(in: CGSize(width: 200, height: 100))
        return runtime
    }

    private func commands(_ runtime: Runtime) -> [String] { runtime.render(scale: 2).commands.map(\.description) }

    @Test func theSpinnerStepsAndTheBarSegmentTravels() {
        let spinner = runtime(ProgressView())
        let ring = spinner.root.descendants(where: { $0 is ProgressRingNode }).first as! ProgressRingNode
        #expect(ring.spinnerPhase == 0)
        // A frame subscription: the clock advances the phase (the spokes' angles) and asks for a repaint.
        #expect(spinner.advanceAnimations(elapsed: 0.3))
        #expect(ring.spinnerPhase == 2)
        _ = spinner.advanceAnimations(elapsed: 0.7)
        #expect(ring.spinnerPhase == 0)
        let bar = runtime(ProgressView().progressViewStyle(.linear))
        let start = commands(bar)
        #expect(bar.advanceAnimations(elapsed: 0.75))
        let moved = commands(bar)
        #expect(moved != start)
        // Half a period on: the segment is half way across the 200 pt track.
        #expect(moved.contains { $0.hasPrefix("fillRRect(96,") })
    }

    @Test func valuesAnimateUnderWithAnimation() {
        let model = Model()
        let runtime = runtime(Values(model: model))
        let bar = runtime.root.descendants(where: { $0 is ProgressBarNode }).first as! ProgressBarNode
        let gauge = runtime.root.descendants(where: { $0 is GaugeBarNode }).first as! GaugeBarNode
        withAnimation(.linear(duration: 1)) { model.value = 0.8 }
        runtime.layout(in: CGSize(width: 200, height: 100))
        _ = runtime.advanceAnimations(elapsed: 0.5)
        #expect(abs((bar.presentedFraction ?? 0) - 0.5) < 0.01)
        #expect(abs(gauge.presentedFraction - 0.5) < 0.01)
        _ = runtime.advanceAnimations(elapsed: 0.6)
        #expect(bar.presentedFraction == 0.8 && gauge.presentedFraction == 0.8)
    }

    @Test func timerIntervalsAndProgressObjects() {
        let now = Date()
        let runtime = runtime(ProgressView(timerInterval: now.addingTimeInterval(-30)...now.addingTimeInterval(30)))
        let bar = runtime.root.descendants(where: { $0 is ProgressBarNode }).first as! ProgressBarNode
        // Half the minute is left: the bar is half full, the label reads 0:30.
        #expect(abs((bar.presentedFraction ?? 0) - 0.5) < 0.02)
        #expect(runtime.root.descendants(where: { ($0 as? TextNode)?.view.resolvedString == "0:30" }).first != nil)
        #if os(Linux)
        let progress = NamedProgress(totalUnitCount: 10)
        #else
        let progress = Progress(totalUnitCount: 10)
        progress.localizedDescription = "Copying"
        #endif
        progress.completedUnitCount = 3
        let polled = self.runtime(ProgressView(progress))
        let polledBar = polled.root.descendants(where: { $0 is ProgressBarNode }).first as! ProgressBarNode
        #expect(abs((polledBar.presentedFraction ?? 0) - 0.3) < 0.001)
        #expect(polled.root.descendants(where: { ($0 as? TextNode)?.view.resolvedString == "Copying" }).first != nil)
        progress.completedUnitCount = 7
        _ = polled.advanceAnimations(elapsed: 0.2)
        polled.layout(in: CGSize(width: 200, height: 100))
        #expect(abs((polledBar.presentedFraction ?? 0) - 0.7) < 0.001)
    }

    @Test func tintAndTheActiveWindow() {
        let ios = runtime(ProgressView(value: 0.5).tint(Color(red: 1, green: 0, blue: 0)), iOS: true)
        #expect(commands(ios).contains { $0.hasPrefix("fillRRect") && $0.hasSuffix("#FF0000") })
        let mac = runtime(ProgressView(value: 0.5).tint(Color(red: 1, green: 0, blue: 0)))
        #expect(!commands(mac).contains { $0.hasSuffix("#FF0000") })
        mac.windowIsActive = true
        #expect(commands(mac).contains { $0.hasPrefix("fillRRect") && $0.hasSuffix("#FF0000") })
    }
}
#endif
