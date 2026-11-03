// Key-value observing on wasm: hand-made reports from an object's own property observers, and
// Observation's reports for an observable object (wasm's `Progress`, which ButtonKit observes).
#if os(WASI)
import Testing
import SwiftUI
import WebFoundation

private final class Player: NSObject {
    var rate = 0.0 {
        willSet { willChangeValue(for: \Player.rate) }
        didSet { didChangeValue(for: \Player.rate) }
    }
    var title = "" {
        willSet { willChangeValue(forKey: "title") }
        didSet { didChangeValue(forKey: "title") }
    }
}

@Suite(.serialized) @MainActor struct WasmKeyValueObservingTests {
    @Test func handMadeReportsCarryOptions() {
        let player = Player()
        var seen: [String] = []
        let observation = player.observe(\.rate, options: [.initial, .new, .old, .prior]) { _, change in
            seen.append("\(change.isPrior ? "prior" : "set") new=\(change.newValue.map { "\($0)" } ?? "-") old=\(change.oldValue.map { "\($0)" } ?? "-") \(change.kind == .setting)")
        }
        #expect(seen == ["set new=0.0 old=- true"])
        player.rate = 1.5
        #expect(seen == ["set new=0.0 old=- true", "prior new=- old=0.0 true", "set new=1.5 old=0.0 true"])

        // A key reaches every observation of the object; another key path's report doesn't.
        player.title = "Song"
        #expect(seen.count == 5)
        observation.invalidate()
        player.rate = 2
        #expect(seen.count == 5)
    }

    @Test func releasingAnObservationStopsIt() {
        let player = Player()
        var count = 0
        var observation: NSKeyValueObservation? = player.observe(\.rate) { _, _ in count += 1 }
        player.rate = 1
        #expect(count == 1 && observation != nil)
        observation = nil
        player.rate = 2
        #expect(count == 1)
    }

    @Test func observableProgressReportsItsSets() async throws {
        let progress = Progress(totalUnitCount: 10)
        var fractions: [Double] = []
        let observation = progress.observe(\.fractionCompleted, options: [.initial, .new]) { _, change in
            if let value = change.newValue { fractions.append(value) }
        }
        progress.completedUnitCount = 5
        for _ in 0..<50 where fractions.count < 2 { try await Task.sleep(nanoseconds: 2_000_000) }
        progress.completedUnitCount = 10
        for _ in 0..<50 where fractions.count < 3 { try await Task.sleep(nanoseconds: 2_000_000) }
        #expect(fractions == [0, 0.5, 1])
        observation.invalidate()
        progress.completedUnitCount = 0
        try await Task.sleep(nanoseconds: 10_000_000)
        #expect(fractions == [0, 0.5, 1])
    }
}
#endif
