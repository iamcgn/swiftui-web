// `Publisher.subscribe(_:)` with a subject: the subject is given the subscription, is sent every
// value and the completion, and stops being sent them when the returned cancellable is
// cancelled. swift-sharing feeds its own relay subject this way.
import Testing
#if !canImport(Darwin)
import WebFoundation
#endif
@testable import WebCombine

/// A subject in the shape of swift-sharing's relay: it records what it is sent, and the
/// subscriptions it is given.
private final class Relay: Subject {
    typealias Output = Int
    typealias Failure = Never
    var values: [Int] = []
    var completions = 0
    var subscriptions = 0

    func send(_ value: Int) { values.append(value) }
    func send(completion: Subscribers.Completion<Never>) { completions += 1 }
    func send(subscription: any Subscription) {
        subscriptions += 1
        subscription.request(.unlimited)
    }
    func receive<S: Subscriber>(subscriber: S) where S.Input == Int, S.Failure == Never {}
}

@MainActor @Suite struct SubjectSubscribeTests {
    @Test func aSubjectIsSentValuesUntilCancelled() {
        let upstream = PassthroughSubject<Int, Never>()
        let relay = Relay()
        let cancellable = upstream.subscribe(relay)
        #expect(relay.subscriptions == 1)
        upstream.send(1)
        upstream.send(2)
        #expect(relay.values == [1, 2])
        cancellable.cancel()
        upstream.send(3)
        #expect(relay.values == [1, 2])
    }

    @Test func theCompletionReachesTheSubject() {
        let upstream = PassthroughSubject<Int, Never>()
        let relay = Relay()
        let cancellable = upstream.subscribe(relay)
        upstream.send(completion: .finished)
        #expect(relay.completions == 1)
        _ = cancellable
    }

    @Test func aSubjectWithoutItsOwnSubscriptionHandlingAsksForEverything() {
        let upstream = CurrentValueSubject<Int, Never>(1)
        let downstream = PassthroughSubject<Int, Never>()
        var received: [Int] = []
        let sink = downstream.sink { received.append($0) }
        let link = upstream.subscribe(downstream)
        upstream.value = 2
        upstream.value = 3
        #expect(received == [1, 2, 3])
        _ = (sink, link)
    }
}
