// `handleEvents` with Combine's closures and its `Publishers.HandleEvents` type,
// `prefix(untilOutputFrom:)`, and `delay`, `debounce` and `throttle` timed by a scheduler that
// the test advances by hand.
import Testing
#if !canImport(Darwin)
import WebFoundation
#endif
@testable import WebCombine

/// A point on the step scheduler's clock.
private struct Step: Strideable, Hashable {
    typealias Stride = ImmediateScheduler.SchedulerTimeType.Stride
    var count: Int
    func distance(to other: Step) -> Stride { Stride(other.count - count) }
    func advanced(by n: Stride) -> Step { Step(count: count + n.magnitude) }
    static func < (lhs: Step, rhs: Step) -> Bool { lhs.count < rhs.count }
}

/// A scheduler whose clock moves only when the test advances it; due actions run in time order.
private final class StepScheduler: Scheduler, @unchecked Sendable {
    typealias SchedulerTimeType = Step
    typealias SchedulerOptions = Never
    private(set) var now = Step(count: 0)
    var minimumTolerance: Step.Stride { .zero }
    private var queued: [(at: Step, order: Int, action: () -> Void)] = []
    private var made = 0

    func schedule(options: Never?, _ action: @escaping () -> Void) { enqueue(now, action) }
    func schedule(after date: Step, tolerance: Step.Stride, options: Never?, _ action: @escaping () -> Void) {
        enqueue(date, action)
    }
    func schedule(after date: Step, interval: Step.Stride, tolerance: Step.Stride, options: Never?,
                  _ action: @escaping () -> Void) -> any Cancellable {
        enqueue(date, action)
        return AnyCancellable {}
    }
    private func enqueue(_ date: Step, _ action: @escaping () -> Void) {
        made += 1
        queued.append((date, made, action))
    }
    func advance(by steps: Int) {
        let end = Step(count: now.count + steps)
        while let next = queued.filter({ $0.at <= end }).min(by: { ($0.at, $0.order) < ($1.at, $1.order) }) {
            queued.removeAll { $0.order == next.order }
            if now < next.at { now = next.at }
            next.action()
        }
        now = end
    }
}

@MainActor @Suite struct EventAndScheduledOperatorsTests {
    @Test func handleEventsHearsEachEventBeforeTheSubscriber() {
        var events: [String] = []
        let subject = PassthroughSubject<Int, Never>()
        let observed: Publishers.HandleEvents<PassthroughSubject<Int, Never>> = subject.handleEvents(
            receiveSubscription: { _ in events.append("subscription") },
            receiveOutput: { events.append("output \($0)") },
            receiveCompletion: { _ in events.append("completion") },
            receiveCancel: { events.append("cancel") },
            receiveRequest: { events.append("request \($0)") })
        let subscription = observed.sink { events.append("sink \($0)") }
        subject.send(1)
        subject.send(completion: .finished)
        subscription.cancel()
        #expect(events == ["subscription", "request unlimited", "output 1", "sink 1", "completion"])
    }

    @Test func theSubscriptionHandedToHandleEventsCancels() {
        var events: [String] = []
        var handed: (any Subscription)?
        let subject = PassthroughSubject<Int, Never>()
        let subscription = subject
            .handleEvents(receiveSubscription: { handed = $0 }, receiveCancel: { events.append("cancel") })
            .sink { events.append("sink \($0)") }
        subject.send(1)
        handed?.cancel()
        subject.send(2)
        #expect(events == ["sink 1", "cancel"])
        subscription.cancel()
        #expect(events == ["sink 1", "cancel"])
    }

    @Test func prefixUntilOutputIgnoresTheOthersEnd() {
        var values: [Int] = []
        var finished = false
        let subject = PassthroughSubject<Int, Never>()
        let stop = PassthroughSubject<Void, Never>()
        let prefixed: Publishers.PrefixUntilOutput<PassthroughSubject<Int, Never>, PassthroughSubject<Void, Never>> =
            subject.prefix(untilOutputFrom: stop)
        let subscription = prefixed.sink(receiveCompletion: { _ in finished = true }, receiveValue: { values.append($0) })
        subject.send(1)
        stop.send(completion: .finished)
        subject.send(2)
        #expect(values == [1, 2])
        #expect(!finished)
        subscription.cancel()
    }

    @Test func prefixUntilOutputStopsAtTheOthersValue() {
        var values: [Int] = []
        var finished = false
        let subject = PassthroughSubject<Int, Never>()
        let stop = PassthroughSubject<Void, Never>()
        let subscription = subject.prefix(untilOutputFrom: stop)
            .sink(receiveCompletion: { _ in finished = true }, receiveValue: { values.append($0) })
        subject.send(1)
        subject.send(2)
        stop.send(())
        subject.send(3)
        #expect(values == [1, 2])
        #expect(finished)
        subscription.cancel()
    }

    @Test func delayWaitsForTheSchedulersClock() {
        let scheduler = StepScheduler()
        var values: [Int] = []
        var finished = false
        let subject = PassthroughSubject<Int, Never>()
        let subscription = subject.delay(for: .seconds(2), scheduler: scheduler)
            .sink(receiveCompletion: { _ in finished = true }, receiveValue: { values.append($0) })
        subject.send(1)
        subject.send(completion: .finished)
        scheduler.advance(by: 1)
        #expect(values.isEmpty)
        #expect(!finished)
        scheduler.advance(by: 1)
        #expect(values == [1])
        #expect(finished)
        subscription.cancel()
    }

    @Test func debounceDeliversTheLastValueOfABurst() {
        let scheduler = StepScheduler()
        var values: [Int] = []
        let subject = PassthroughSubject<Int, Never>()
        let subscription = subject.debounce(for: .seconds(3), scheduler: scheduler).sink { values.append($0) }
        subject.send(1)
        scheduler.advance(by: 2)
        subject.send(2)
        scheduler.advance(by: 2)
        #expect(values.isEmpty)
        scheduler.advance(by: 1)
        #expect(values == [2])
        subject.send(3)
        subscription.cancel()
        scheduler.advance(by: 5)
        #expect(values == [2])
    }

    @Test func throttleDeliversTheFirstThenTheLatestOfTheWindow() {
        let scheduler = StepScheduler()
        var latest: [Int] = []
        var first: [Int] = []
        let subject = PassthroughSubject<Int, Never>()
        let keepingLatest = subject.throttle(for: .seconds(2), scheduler: scheduler, latest: true).sink { latest.append($0) }
        let keepingFirst = subject.throttle(for: .seconds(2), scheduler: scheduler, latest: false).sink { first.append($0) }
        subject.send(1)
        subject.send(2)
        subject.send(3)
        #expect(latest == [1] && first == [1])
        scheduler.advance(by: 2)
        #expect(latest == [1, 3] && first == [1])
        subject.send(4)
        #expect(latest == [1, 3, 4] && first == [1, 4])
        keepingLatest.cancel()
        keepingFirst.cancel()
    }

    @Test func nothingFollowsAThrottledStreamsCompletion() {
        let scheduler = StepScheduler()
        var events: [String] = []
        let subject = PassthroughSubject<Int, Never>()
        let subscription = subject.throttle(for: .seconds(2), scheduler: scheduler, latest: true)
            .sink(receiveCompletion: { _ in events.append("finished") }, receiveValue: { events.append("value \($0)") })
        subject.send(1)
        subject.send(2)
        subject.send(completion: .finished)
        #expect(events == ["value 1", "finished"])
        scheduler.advance(by: 2)
        #expect(events == ["value 1", "finished"])
        subscription.cancel()
    }

    @Test func aNumberStillPicksTheSecondsForms() {
        let delayed: _Pipe<Int, Never> = Just(1).delay(for: 0.01, scheduler: StepScheduler())
        _ = delayed
    }
}
