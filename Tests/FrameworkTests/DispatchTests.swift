// Dispatch as packages use it (TelemetryDeck's barrier queue, Alamofire's preconditions,
// Kingfisher's specifics, timer sources): the wasm stand-in
// (Packages/WebGraphics/Sources/WebFoundation/Dispatch.swift) gives the answers Dispatch does
// on macOS and Linux, where these run against the real one.
import Testing
import WebFoundation

private final class Box: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [Int] = []
    func append(_ value: Int) { lock.withLock { items.append(value) } }
    var values: [Int] { lock.withLock { items } }
}

@Suite struct DispatchTests {
    @Test func semaphoresAndGroupsAnswerTimedWaits() {
        let semaphore = DispatchSemaphore(value: 1)
        #expect(semaphore.wait(timeout: .now()) == .success)
        #expect(semaphore.wait(timeout: .now()) == .timedOut)
        semaphore.signal()
        #expect(semaphore.wait(timeout: .now()) == .success)
        semaphore.signal()

        let group = DispatchGroup()
        #expect(group.wait(timeout: .now()) == .success)
        group.enter()
        group.leave()
        #expect(group.wait(timeout: .now() + .milliseconds(10)) == .success)
    }

    @Test func queuesKeepSpecificsAndRunBarriers() {
        let queue = DispatchQueue(label: "specifics", qos: .utility, attributes: .concurrent)
        let key = DispatchSpecificKey<Int>()
        queue.setSpecific(key: key, value: 7)
        #expect(queue.getSpecific(key: key) == 7)
        #expect(queue.sync { DispatchQueue.getSpecific(key: key) } == 7)
        #expect(queue.sync(flags: .barrier) { 5 } == 5)
        queue.sync { dispatchPrecondition(condition: .onQueue(queue)) }
        dispatchPrecondition(condition: .notOnQueue(queue))
        queue.setSpecific(key: key, value: nil)
        #expect(queue.getSpecific(key: key) == nil)
        #expect(queue.label == "specifics" && queue.qos == .utility)
    }

    @Test func concurrentPerformRunsEveryIteration() {
        let box = Box()
        DispatchQueue.concurrentPerform(iterations: 10) { box.append($0) }
        #expect(box.values.sorted() == Array(0..<10))
    }

    @Test func uptimeOrdersTimes() {
        #expect(DispatchTime(uptimeNanoseconds: 5_000_000_000) < DispatchTime(uptimeNanoseconds: 6_000_000_000))
        let now = DispatchTime.now()
        #expect((now + .seconds(1)).uptimeNanoseconds > now.uptimeNanoseconds && (now + .seconds(1)) > now && (now - .milliseconds(1)) < now)
    }

    /// Intervals are an enum whose cases code matches (RevenueCat converts them this way), equal
    /// when they span the same time; the span between two times is one.
    @Test func intervalsMatchAsCasesAndMeasureSpans() {
        // `if case` rather than a switch: Apple's enum is resilient and wants `@unknown default`,
        // which the others warn is never reached.
        func seconds(_ interval: DispatchTimeInterval) -> Double {
            if case .seconds(let s) = interval { return Double(s) }
            if case .milliseconds(let ms) = interval { return Double(ms) / 1_000 }
            if case .microseconds(let us) = interval { return Double(us) / 1_000_000 }
            if case .nanoseconds(let ns) = interval { return Double(ns) / 1_000_000_000 }
            if case .never = interval { return .infinity }
            return .nan
        }
        #expect(seconds(.milliseconds(1500)) == 1.5 && seconds(.never) == .infinity)
        #expect(DispatchTimeInterval.seconds(1) == .milliseconds(1000) && DispatchTimeInterval.seconds(1) != .seconds(2))
        if case .microseconds(let us) = DispatchTimeInterval.microseconds(7) { #expect(us == 7) } else { Issue.record("not microseconds") }
        // `distance(to:)` and `advanced(by:)` come from Apple's Dispatch overlay (and ours on
        // wasm); Linux's corelibs Dispatch has neither.
        #if os(WASI) || canImport(Darwin)
        let start = DispatchTime(uptimeNanoseconds: 5_000_000_000)
        let end = DispatchTime(uptimeNanoseconds: 7_000_000_000)
        #expect(abs(seconds(start.distance(to: end)) - 2) < 0.001)
        #expect(abs(seconds(end.distance(to: start)) + 2) < 0.001)
        #expect(start.advanced(by: .seconds(2)) == end)
        #endif
    }

    /// Lets queued work run: the wasm test runner has no event loop to sleep on (Node's WASI
    /// can't wait), so there it yields to the main actor's queued jobs instead. For the same
    /// reason no test here takes a time limit: its watchdog sleeps. The loops are bounded.
    private func pause() async {
        #if os(WASI)
        await Task.yield()
        #else
        try? await Task.sleep(nanoseconds: 5_000_000)
        #endif
    }

    @Test func groupsAndWorkItemsNotify() async {
        let box = Box()
        let group = DispatchGroup()
        // Their own queues, not `.main`: Linux's test runner doesn't drain the main queue.
        let queue = DispatchQueue(label: "work")
        let done = DispatchQueue(label: "done")
        queue.async(group: group, flags: .barrier) { box.append(1) }
        group.notify(queue: done) { box.append(2) }
        let item = DispatchWorkItem(flags: .barrier) { box.append(3) }
        item.notify(queue: done) { box.append(4) }
        queue.async(execute: item)
        for _ in 0..<400 where box.values.count < 4 { await pause() }
        #expect(box.values.sorted() == [1, 2, 3, 4])
    }

    #if !os(WASI)
    // A timer waits out real time, which the wasm test runner can't (see `pause()`).
    @Test func timersFireUntilCancelled() async {
        let ticks = Box()
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "timer"))
        timer.schedule(deadline: .now() + .milliseconds(5), repeating: .milliseconds(10))
        timer.setEventHandler { ticks.append(0) }
        timer.setCancelHandler { ticks.append(-1) }
        timer.resume()
        for _ in 0..<400 where ticks.values.count < 2 { await pause() }
        timer.cancel()
        #expect(timer.isCancelled)
        for _ in 0..<400 where !ticks.values.contains(-1) { await pause() }
        let fired = ticks.values.filter { $0 == 0 }.count
        #expect(fired >= 2 && ticks.values.contains(-1))
        try? await Task.sleep(nanoseconds: 40_000_000)
        #expect(ticks.values.filter { $0 == 0 }.count <= fired + 1)
    }
    #endif

    @Test func percentEncodingAndSelectorNames() {
        #expect("a b&c".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) == "a%20b&c")
        #expect("a%20b".removingPercentEncoding == "a b")
        #expect("x/y z".addingPercentEncoding(withAllowedCharacters: .alphanumerics) == "x%2Fy%20z")
    }
}
