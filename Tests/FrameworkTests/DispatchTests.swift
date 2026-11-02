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

    @Test(.timeLimit(.minutes(1))) func groupsNotifyAndTimersFire() async {
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
        for _ in 0..<400 where box.values.count < 4 { try? await Task.sleep(nanoseconds: 5_000_000) }
        #expect(box.values.sorted() == [1, 2, 3, 4])

        let ticks = Box()
        let timer = DispatchSource.makeTimerSource(queue: done)
        timer.schedule(deadline: .now() + .milliseconds(5), repeating: .milliseconds(10))
        timer.setEventHandler { ticks.append(0) }
        timer.setCancelHandler { ticks.append(-1) }
        timer.resume()
        for _ in 0..<400 where ticks.values.count < 2 { try? await Task.sleep(nanoseconds: 5_000_000) }
        timer.cancel()
        #expect(timer.isCancelled)
        for _ in 0..<400 where !ticks.values.contains(-1) { try? await Task.sleep(nanoseconds: 5_000_000) }
        let fired = ticks.values.filter { $0 == 0 }.count
        #expect(fired >= 2 && ticks.values.contains(-1))
        try? await Task.sleep(nanoseconds: 40_000_000)
        #expect(ticks.values.filter { $0 == 0 }.count <= fired + 1)
    }

    @Test func percentEncodingAndSelectorNames() {
        #expect("a b&c".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) == "a%20b&c")
        #expect("a%20b".removingPercentEncoding == "a b")
        #expect("x/y z".addingPercentEncoding(withAllowedCharacters: .alphanumerics) == "x%2Fy%20z")
    }
}
