// Combine's subscriber model and schedulers on WebCombine: demand arithmetic, a publisher
// written against `receive(subscriber:)`, a subscriber that asks for values one at a time,
// and the schedulers' time types.
import Testing
#if !canImport(Darwin)
import WebFoundation
#endif
@testable import WebCombine

/// A Combine-style publisher: it implements only `receive(subscriber:)`.
private struct Countdown: Publisher {
    typealias Output = Int
    typealias Failure = Never
    let from: Int
    func receive<S: Subscriber>(subscriber: S) where S.Input == Int, S.Failure == Never {
        subscriber.receive(subscription: Idle())
        for value in stride(from: from, through: 1, by: -1) { _ = subscriber.receive(value) }
        subscriber.receive(completion: .finished)
    }
    final class Idle: Subscription {
        func request(_ demand: Subscribers.Demand) {}
        func cancel() {}
    }
}

/// A subscriber that asks for one value at first and one more after each.
private final class OneAtATime: Subscriber {
    typealias Input = Int
    typealias Failure = Never
    var subscription: (any Subscription)?
    var values: [Int] = []
    var finished = false
    let more: Subscribers.Demand
    init(more: Subscribers.Demand) { self.more = more }
    func receive(subscription: any Subscription) {
        self.subscription = subscription
        subscription.request(.max(1))
    }
    func receive(_ input: Int) -> Subscribers.Demand {
        values.append(input)
        return more
    }
    func receive(completion: Subscribers.Completion<Never>) { finished = true }
}

@MainActor @Suite struct SubscriberSchedulerTests {
    @Test func demandArithmetic() {
        #expect(Subscribers.Demand.max(2) + .max(3) == .max(5))
        #expect(Subscribers.Demand.unlimited + 1 == .unlimited)
        #expect(Subscribers.Demand.max(1) - .max(4) == .none)
        #expect(Subscribers.Demand.unlimited - 7 == .unlimited)
        #expect(Subscribers.Demand.max(3) * 2 == .max(6))
        #expect(Subscribers.Demand.max(9) < .unlimited)
        #expect(Subscribers.Demand.max(2) > 1)
        #expect(Subscribers.Demand.unlimited.max == nil)
        #expect(Subscribers.Demand.max(4).description == "max(4)")
    }

    @Test func combineStylePublisherWorksWithSink() {
        var values: [Int] = []
        var finished = false
        let cancellable = Countdown(from: 3).sink(receiveCompletion: { _ in finished = true }, receiveValue: { values.append($0) })
        #expect(values == [3, 2, 1])
        #expect(finished)
        _ = cancellable
    }

    @Test func subscriberDemandHoldsValuesBack() {
        let countdown = OneAtATime(more: .none)
        [5, 4, 3].publisher.subscribe(countdown)
        #expect(countdown.values == [5])
        #expect(!countdown.finished)
        countdown.subscription?.request(.max(5))
        #expect(countdown.values == [5, 4, 3])
        #expect(countdown.finished)

        let eager = OneAtATime(more: .max(1))
        Just(7).subscribe(eager)
        #expect(eager.values == [7])
        #expect(eager.finished)
    }

    /// A passthrough subject drops what nobody asked for, and its completion needs no demand.
    @Test func passthroughDropsValuesWithoutDemand() {
        let subject = PassthroughSubject<Int, Never>()
        let subscriber = OneAtATime(more: .none)
        subject.subscribe(subscriber)
        subject.send(1)
        subject.send(2)
        subject.send(completion: .finished)
        #expect(subscriber.values == [1])
        #expect(subscriber.finished)
        subscriber.subscription?.request(.max(5))
        #expect(subscriber.values == [1])
    }

    /// A current-value subject keeps the newest value for when demand comes.
    @Test func currentValueKeepsTheNewestWithoutDemand() {
        let subject = CurrentValueSubject<Int, Never>(0)
        let subscriber = OneAtATime(more: .none)
        subject.subscribe(subscriber)
        subject.send(1)
        subject.send(2)
        #expect(subscriber.values == [0])
        subscriber.subscription?.request(.max(1))
        #expect(subscriber.values == [0, 2])
        subject.send(completion: .finished)
        #expect(subscriber.finished)
    }

    /// Type erasure and one-for-one operators keep a subject's policy (as Combine's pass demand
    /// up to the subject).
    @Test func wrappedPassthroughDropsValuesWithoutDemand() {
        let wrapped: [(PassthroughSubject<Int, Never>) -> AnyPublisher<Int, Never>] = [
            { $0.eraseToAnyPublisher() },
            { $0.map { $0 }.eraseToAnyPublisher() },
            { $0.filter { _ in true }.compactMap { Optional($0) }.eraseToAnyPublisher() },
        ]
        for wrap in wrapped {
            let subject = PassthroughSubject<Int, Never>()
            let subscriber = OneAtATime(more: .none)
            wrap(subject).subscribe(subscriber)
            subject.send(1)
            subject.send(2)
            subject.send(completion: .finished)
            #expect(subscriber.values == [1])
            #expect(subscriber.finished)
            subscriber.subscription?.request(.max(1))
            #expect(subscriber.values == [1])
        }
        let subject = PassthroughSubject<Int, Never>()
        let subscriber = OneAtATime(more: .none)
        subject.map { $0 * 10 }.subscribe(subscriber)
        subject.send(1)
        subject.send(2)
        subject.send(completion: .finished)
        #expect(subscriber.values == [10])
        #expect(subscriber.finished)
    }

    @Test func wrappedCurrentValueKeepsTheNewestWithoutDemand() {
        let subject = CurrentValueSubject<Int, Never>(0)
        let subscriber = OneAtATime(more: .none)
        subject.map { $0 }.eraseToAnyPublisher().subscribe(subscriber)
        subject.send(1)
        subject.send(2)
        #expect(subscriber.values == [0])
        subscriber.subscription?.request(.max(1))
        #expect(subscriber.values == [0, 2])
        subject.send(completion: .finished)
        #expect(subscriber.finished)
    }

    /// A sequence keeps holding its values through the same operators.
    @Test func wrappedSequenceStillHoldsValues() {
        let subscriber = OneAtATime(more: .none)
        [5, 4, 3].publisher.map { $0 }.eraseToAnyPublisher().subscribe(subscriber)
        #expect(subscriber.values == [5])
        #expect(!subscriber.finished)
        subscriber.subscription?.request(.max(2))
        #expect(subscriber.values == [5, 4, 3])
        #expect(subscriber.finished)
    }

    @Test func cancellingTheSubscriptionStopsValues() {
        let subject = PassthroughSubject<Int, Never>()
        let subscriber = OneAtATime(more: .unlimited)
        subject.subscribe(subscriber)
        subject.send(1)
        subscriber.subscription?.cancel()
        subject.send(2)
        #expect(subscriber.values == [1])
    }

    @Test func immediateSchedulerRunsInPlace() {
        var ran = 0
        let scheduler = ImmediateScheduler.shared
        scheduler.schedule { ran += 1 }
        scheduler.schedule(after: scheduler.now.advanced(by: .seconds(5))) { ran += 1 }
        _ = scheduler.schedule(after: scheduler.now, interval: 1) { ran += 1 }
        #expect(ran == 3)
        let stride: ImmediateScheduler.SchedulerTimeType.Stride = 4
        #expect(stride + .seconds(1) == 5)
        #expect(-stride == .seconds(-4))
    }

    #if !canImport(Darwin)
    @Test func dispatchQueueTimeArithmetic() {
        let start = DispatchQueue.main.now
        let later = start.advanced(by: .seconds(5))
        #expect(start.distance(to: later) == .seconds(5))
        #expect(start < later)
        #expect(DispatchQueue.SchedulerTimeType.Stride.milliseconds(1_500) == 1.5)
        #expect(DispatchQueue.SchedulerTimeType.Stride.microseconds(2).magnitude == 2_000)
        #expect(DispatchQueue.SchedulerTimeType.Stride(.milliseconds(250)) == .seconds(0.25))
    }

    @Test func dateSchedulersShareSecondsStrides() {
        let start = RunLoop.main.now
        let later = start.advanced(by: .milliseconds(500))
        #expect(abs(start.distance(to: later).timeInterval - 0.5) < 1e-6)
        #expect(OperationQueue.SchedulerTimeType.Stride.seconds(2) == 2)
        #expect(RunLoop.SchedulerTimeType.Stride.nanoseconds(1_000).timeInterval == 1e-6)
    }

    // combine-schedulers extends `AnyScheduler` once for each scheduler's time and options
    // types; they have to be distinct types for both extensions to compile.
    @Test func eachDateSchedulerHasItsOwnTimeType() {
        #expect(SchedulerName<RunLoop>.name == "run loop")
        #expect(SchedulerName<OperationQueue>.name == "operation queue")
    }
    #endif
}

#if !canImport(Darwin)
private enum SchedulerName<S: Scheduler> {}
extension SchedulerName where S.SchedulerTimeType == RunLoop.SchedulerTimeType, S.SchedulerOptions == RunLoop.SchedulerOptions {
    static var name: String { "run loop" }
}
extension SchedulerName where S.SchedulerTimeType == OperationQueue.SchedulerTimeType, S.SchedulerOptions == OperationQueue.SchedulerOptions {
    static var name: String { "operation queue" }
}
#endif
