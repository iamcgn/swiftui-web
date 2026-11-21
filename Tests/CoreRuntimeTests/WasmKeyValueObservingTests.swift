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

private struct StoreKeyID: Hashable {
    let key: String
    let store: UserDefaults
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
        let kept: Set<NSKeyValueObservation> = [observation, observation]
        #expect(kept.count == 1)
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

    // Waits by yielding: under Node a sleeping task asks WASI for timers it doesn't have.
    @Test func aKeyPathPublisherSendsTheValueThenItsChanges() {
        let player = Player()
        var rates: [Double] = []
        let subscription = player.publisher(for: \.rate).sink { rates.append($0) }
        player.rate = 1.5
        #expect(rates == [0, 1.5])
        subscription.cancel()
        player.rate = 2
        #expect(rates == [0, 1.5])

        var later: [Double] = []
        let changesOnly = player.publisher(for: \.rate, options: [.new]).sink { later.append($0) }
        player.rate = 3
        #expect(later == [3])
        changesOnly.cancel()
    }

    @Test func observableProgressReportsItsSets() async {
        let progress = Progress(totalUnitCount: 10)
        var fractions: [Double] = []
        let observation = progress.observe(\.fractionCompleted, options: [.initial, .new]) { _, change in
            if let value = change.newValue { fractions.append(value) }
        }
        progress.completedUnitCount = 5
        for _ in 0..<50 where fractions.count < 2 { await Task.yield() }
        progress.completedUnitCount = 10
        for _ in 0..<50 where fractions.count < 3 { await Task.yield() }
        #expect(fractions == [0, 0.5, 1])
        observation.invalidate()
        progress.completedUnitCount = 0
        for _ in 0..<20 { await Task.yield() }
        #expect(fractions == [0, 0.5, 1])
    }

    // An observer added by key path (swift-sharing's app storage watches its user defaults key
    // this way): it hears the defaults' sets of that key, with the values it asked for.
    @Test func anObserverByKeyHearsTheDefaultsSetsOfItsKey() throws {
        let defaults = try #require(UserDefaults(suiteName: "kvo.\(Int.random(in: 0..<1_000_000))"))
        let observer = KeyObserver()
        var context = 7
        defaults.set(1, forKey: "count")
        defaults.addObserver(observer, forKeyPath: "count", options: [.new, .old, .prior], context: &context)
        defaults.set(2, forKey: "count")
        defaults.set("x", forKey: "other")
        #expect(observer.seen == ["prior count old=1 new=-", "count old=1 new=2"])
        #expect(observer.contexts.count == 2 && observer.contexts.allSatisfy { $0 != nil })

        defaults.removeObject(forKey: "count")
        #expect(observer.seen.last == "count old=2 new=<null>")
        defaults.removeObserver(observer, forKeyPath: "count")
        defaults.set(3, forKey: "count")
        #expect(observer.seen.count == 4)
    }

    // swift-sharing's own shapes: a key that names its store, and a check by selector before
    // asking the store for its suite.
    @Test func appStorageShapes() throws {
        let defaults = try #require(UserDefaults(suiteName: "kvo.\(Int.random(in: 0..<1_000_000))"))
        let ids: Set<StoreKeyID> = [StoreKeyID(key: "flag", store: defaults), StoreKeyID(key: "flag", store: defaults),
                                    StoreKeyID(key: "flag", store: .standard)]
        #expect(ids.count == 2)
        #expect(!defaults.responds(to: Selector(("_identifier"))))
    }

    @Test func anObserverByKeyHearsAHandMadeReportAndInitialValue() throws {
        let player = Player()
        let observer = KeyObserver()
        player.addObserver(observer, forKeyPath: "title", options: [.initial], context: nil)
        #expect(observer.seen == ["title old=- new=-"])
        player.title = "Song"
        player.rate = 1
        #expect(observer.seen == ["title old=- new=-", "title old=- new=-"])
        player.removeObserver(observer, forKeyPath: "title", context: nil)
        player.title = "Other"
        #expect(observer.seen.count == 2)
    }
}

/// Records each change it is sent, as `prior key old=… new=…`.
private final class KeyObserver: NSObject {
    var seen: [String] = []
    var contexts: [UnsafeMutableRawPointer?] = []
    override func observeValue(forKeyPath keyPath: String?, of object: Any?,
                               change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        func describe(_ value: Any?) -> String {
            guard let value else { return "-" }
            return value is NSNull ? "<null>" : "\(value)"
        }
        let prior = (change?[.notificationIsPriorKey] as? Bool) == true
        seen.append("\(prior ? "prior " : "")\(keyPath ?? "") old=\(describe(change?[.oldKey])) new=\(describe(change?[.newKey]))")
        contexts.append(context)
    }
}
#endif
