// Connectable publishers and `AnySubscriber`: a publisher that starts on `connect()`,
// `autoconnect()` connecting with the first subscriber and stopping after the last, and
// `makeConnectable()` / `multicast` sharing one upstream subscription.
import Testing
#if !canImport(Darwin)
import WebFoundation
#endif
@testable import WebCombine

/// A connectable publisher that counts its connections and sends through a subject once connected.
private final class Ticker: ConnectablePublisher {
    typealias Output = Int
    typealias Failure = Never
    let subject = PassthroughSubject<Int, Never>()
    var connections = 0
    var disconnections = 0
    var connected = false

    @MainActor func _subscribe(_ receive: @escaping @MainActor (Int) -> Void,
                               _ complete: @escaping @MainActor (Subscribers.Completion<Never>) -> Void) -> AnyCancellable {
        subject._subscribe(receive, complete)
    }

    func connect() -> any Cancellable {
        connections += 1
        connected = true
        return AnyCancellable { [self] in
            connected = false
            disconnections += 1
        }
    }

    func tick(_ value: Int) { if connected { subject.send(value) } }
}

@MainActor @Suite struct ConnectableTests {
    @Test func autoconnectRunsWhileSubscribed() {
        let ticker = Ticker()
        let shared = ticker.autoconnect()
        ticker.tick(0)
        #expect(ticker.connections == 0)

        var a: [Int] = []
        var b: [Int] = []
        let first = shared.sink { a.append($0) }
        let second = shared.sink { b.append($0) }
        #expect(ticker.connections == 1)
        ticker.tick(1)
        first.cancel()
        ticker.tick(2)
        #expect(ticker.disconnections == 0)
        second.cancel()
        #expect(ticker.disconnections == 1)
        ticker.tick(3)
        #expect(a == [1] && b == [1, 2])
    }

    @Test func makeConnectableWaitsForConnect() {
        let source = PassthroughSubject<Int, Never>()
        let connectable = source.makeConnectable()
        var values: [Int] = []
        let sink = connectable.sink { values.append($0) }
        source.send(1)
        let connection = connectable.connect()
        source.send(2)
        source.send(3)
        connection.cancel()
        source.send(4)
        #expect(values == [2, 3])
        sink.cancel()
    }

    @Test func multicastSharesOneUpstreamSubscription() {
        var subscriptions = 0
        let upstream = Deferred { () -> Just<Int> in
            subscriptions += 1
            return Just(subscriptions)
        }
        let multicast = upstream.multicast { PassthroughSubject<Int, Never>() }
        var a: [Int] = []
        var b: [Int] = []
        var finished = 0
        let first = multicast.sink(receiveCompletion: { _ in finished += 1 }, receiveValue: { a.append($0) })
        let second = multicast.sink(receiveCompletion: { _ in finished += 1 }, receiveValue: { b.append($0) })
        let connection = multicast.connect()
        #expect(subscriptions == 1 && a == [1] && b == [1] && finished == 2)
        _ = (first, second, connection)
    }

    @Test func anySubscriberForwardsToWhatItWraps() {
        var values: [Int] = []
        var completed = false
        var subscribed = false
        let erased = AnySubscriber<Int, Never>(receiveSubscription: { subscribed = true; $0.request(.unlimited) },
                                               receiveValue: { values.append($0); return .none },
                                               receiveCompletion: { _ in completed = true })
        [4, 5].publisher.subscribe(erased)
        #expect(subscribed && values == [4, 5] && completed)

        let twice = AnySubscriber(erased)
        #expect(twice.combineIdentifier == erased.combineIdentifier)

        let subject = PassthroughSubject<Int, Never>()
        var relayed: [Int] = []
        let relay = subject.sink { relayed.append($0) }
        Just(9).subscribe(AnySubscriber(subject))
        #expect(relayed == [9])
        relay.cancel()

        let silent = AnySubscriber<Int, Never>()
        #expect(silent.receive(1) == .none)
    }
}
