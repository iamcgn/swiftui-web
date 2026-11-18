// Two of Combine's operator types spelt out, for code that names them: the Composable
// Architecture's effect cancellation returns
// `Publishers.HandleEvents<Publishers.PrefixUntilOutput<…, PassthroughSubject<Void, Never>>>`.
// The other operators stay `_Pipe`s (decision 0021).
import WebFoundation

extension Publishers {
    /// A publisher that performs the specified closures when publisher events occur.
    public struct HandleEvents<Upstream: Publisher>: Publisher, _CarriesDemandPolicy {
        public typealias Output = Upstream.Output
        public typealias Failure = Upstream.Failure

        public let upstream: Upstream
        public var receiveSubscription: (@MainActor (any Subscription) -> Void)?
        public var receiveOutput: (@MainActor (Upstream.Output) -> Void)?
        public var receiveCompletion: (@MainActor (Subscribers.Completion<Upstream.Failure>) -> Void)?
        public var receiveCancel: (@MainActor () -> Void)?
        public var receiveRequest: (@MainActor (Subscribers.Demand) -> Void)?

        public init(upstream: Upstream,
                    receiveSubscription: (@MainActor (any Subscription) -> Void)? = nil,
                    receiveOutput: (@MainActor (Upstream.Output) -> Void)? = nil,
                    receiveCompletion: (@MainActor (Subscribers.Completion<Upstream.Failure>) -> Void)? = nil,
                    receiveCancel: (@MainActor () -> Void)? = nil,
                    receiveRequest: (@MainActor (Subscribers.Demand) -> Void)? = nil) {
            self.upstream = upstream
            self.receiveSubscription = receiveSubscription
            self.receiveOutput = receiveOutput
            self.receiveCompletion = receiveCompletion
            self.receiveCancel = receiveCancel
            self.receiveRequest = receiveRequest
        }

        var _carriedDemandPolicy: _DemandPolicy { upstream._demandPolicy }

        @MainActor public func _subscribe(_ receive: @escaping @MainActor (Output) -> Void,
                                          _ complete: @escaping @MainActor (Subscribers.Completion<Failure>) -> Void) -> AnyCancellable {
            let onOutput = self.receiveOutput, onCompletion = self.receiveCompletion, onCancel = self.receiveCancel
            let ended = _State(false)
            let upstreamLink = _State<AnyCancellable?>(nil)
            let cancellable = AnyCancellable {
                MainActor.assumeIsolated {
                    if !ended.value {
                        ended.value = true
                        onCancel?()
                    }
                    upstreamLink.value?.cancel()
                    upstreamLink.value = nil
                }
            }
            self.receiveSubscription?(_EventsSubscription(cancellable: cancellable, receiveRequest: self.receiveRequest))
            self.receiveRequest?(.unlimited)
            guard !ended.value else { return cancellable }
            let link = upstream._subscribe({ value in
                guard !ended.value else { return }
                onOutput?(value)
                receive(value)
            }, { completion in
                guard !ended.value else { return }
                ended.value = true
                onCompletion?(completion)
                complete(completion)
            })
            if ended.value { link.cancel() } else { upstreamLink.value = link }
            return cancellable
        }
    }

    /// A publisher that republishes elements until another publisher emits an element.
    public struct PrefixUntilOutput<Upstream: Publisher, Other: Publisher>: Publisher, _CarriesDemandPolicy {
        public typealias Output = Upstream.Output
        public typealias Failure = Upstream.Failure

        public let upstream: Upstream
        public let other: Other

        public init(upstream: Upstream, other: Other) {
            self.upstream = upstream
            self.other = other
        }

        var _carriedDemandPolicy: _DemandPolicy { upstream._demandPolicy }

        @MainActor public func _subscribe(_ receive: @escaping @MainActor (Output) -> Void,
                                          _ complete: @escaping @MainActor (Subscribers.Completion<Failure>) -> Void) -> AnyCancellable {
            let ended = _State(false)
            let upstreamLink = _State<AnyCancellable?>(nil)
            let otherLink = _State<AnyCancellable?>(nil)
            func end(_ completion: Subscribers.Completion<Failure>) {
                guard !ended.value else { return }
                ended.value = true
                upstreamLink.value?.cancel()
                upstreamLink.value = nil
                otherLink.value?.cancel()
                otherLink.value = nil
                complete(completion)
            }
            let watching = other._subscribe({ _ in end(.finished) }, { _ in })
            if ended.value { watching.cancel() } else { otherLink.value = watching }
            if !ended.value {
                let link = upstream._subscribe({ value in
                    guard !ended.value else { return }
                    receive(value)
                }, { completion in end(completion) })
                if ended.value { link.cancel() } else { upstreamLink.value = link }
            }
            return AnyCancellable {
                MainActor.assumeIsolated {
                    ended.value = true
                    upstreamLink.value?.cancel()
                    upstreamLink.value = nil
                    otherLink.value?.cancel()
                    otherLink.value = nil
                }
            }
        }
    }
}

/// The subscription `handleEvents` hands its `receiveSubscription`: cancelling it cancels the
/// subscription, and a request is reported to `receiveRequest`.
final class _EventsSubscription: Subscription, @unchecked Sendable {
    private let cancellable: AnyCancellable
    private let receiveRequest: (@MainActor (Subscribers.Demand) -> Void)?
    init(cancellable: AnyCancellable, receiveRequest: (@MainActor (Subscribers.Demand) -> Void)?) {
        self.cancellable = cancellable
        self.receiveRequest = receiveRequest
    }
    func request(_ demand: Subscribers.Demand) {
        let report = self.receiveRequest
        MainActor.assumeIsolated { report?(demand) }
    }
    func cancel() { cancellable.cancel() }
}
