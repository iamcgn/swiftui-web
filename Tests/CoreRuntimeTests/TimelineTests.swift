// TimelineView (Phase 3): periodic schedules wake through a main-actor task, explicit
// schedules stop after their last date, the animation schedule re-renders per frame and
// unmounting cancels the wake.
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless
import Foundation

#if !os(WASI)
@Suite @MainActor struct TimelineTests {
    @Observable final class Model: @unchecked Sendable { var show = true; var dates: [Date] = [] }

    struct Periodic: View {
        let model: Model
        var body: some View {
            VStack {
                if model.show {
                    TimelineView(.periodic(from: .now, by: 0.05)) { context in
                        Color.red.frame(width: 10, height: 10).onAppear { model.dates.append(context.date) }.onChange(of: context.date) { model.dates.append(context.date) }
                    }
                }
            }
        }
    }

    @Test func periodicScheduleWakesAndStopsOnUnmount() async {
        let model = Model()
        let r = Runtime()
        r.mount(Periodic(model: model))
        r.layout(in: CGSize(width: 100, height: 100))
        #expect(model.dates.count == 1)
        // Headless, each wake needs a flush to schedule the next one (the host flushes on its own).
        for _ in 0..<3 {
            try? await Task.sleep(nanoseconds: 70_000_000)
            r.layout(in: CGSize(width: 100, height: 100))
        }
        let woken = model.dates.count
        #expect(woken >= 3)
        // Successive dates lie on the 50 ms grid.
        if model.dates.count >= 3 {
            let gap = model.dates[2].timeIntervalSince(model.dates[1])
            #expect(abs(gap - 0.05) < 0.001)
        }
        model.show = false
        r.layout(in: CGSize(width: 100, height: 100))
        try? await Task.sleep(nanoseconds: 120_000_000)
        r.layout(in: CGSize(width: 100, height: 100))
        #expect(model.dates.count == woken)
    }

    struct Animated: View {
        let model: Model
        var body: some View {
            TimelineView(.animation) { context in
                Color.blue.frame(width: 10, height: 10).onChange(of: context.date) { model.dates.append(context.date) }
            }
        }
    }

    @Test func animationScheduleFollowsFrames() {
        let model = Model()
        let r = Runtime()
        r.mount(Animated(model: model))
        r.layout(in: CGSize(width: 100, height: 100))
        #expect(r.advanceAnimations(elapsed: 0.016))
        r.layout(in: CGSize(width: 100, height: 100))
        r.advanceAnimations(elapsed: 0.016)
        r.layout(in: CGSize(width: 100, height: 100))
        #expect(model.dates.count == 2)
    }

    @Test func explicitScheduleEntries() {
        let base = Date(timeIntervalSinceReferenceDate: 1000)
        let explicit = ExplicitTimelineSchedule([base, base.addingTimeInterval(1)])
        #expect(Array(explicit.entries(from: base, mode: .normal)) == [base, base.addingTimeInterval(1)])
        let periodic = PeriodicTimelineSchedule(from: base, by: 10)
        var entries = periodic.entries(from: base.addingTimeInterval(25), mode: .normal)
        #expect(entries.next() == base.addingTimeInterval(30) && entries.next() == base.addingTimeInterval(40))
        var minute = EveryMinuteTimelineSchedule().entries(from: Date(timeIntervalSinceReferenceDate: 125), mode: .normal)
        #expect(minute.next() == Date(timeIntervalSinceReferenceDate: 120))
    }
}
#endif
