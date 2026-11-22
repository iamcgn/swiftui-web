// Combine's operators over the closure publishers (decision 0021): each one is a `_Pipe`, a
// publisher made of the upstream's subscription with the downstream closures wrapped, so the
// chain costs one closure per stage. Apple's operator types (`Publishers.Map<Upstream, T>` and
// friends) are names for the pipe their operator returns (`Publishers.CompactMap<Just<A?>, A>` is
// `_Pipe<A, Never>`), so code that spells the type an operator returns compiles. Schedulers are accepted and
// ignored: everything already delivers on the main actor.
import WebFoundation

/// A publisher assembled from a subscribe closure: what every operator returns.
public struct _Pipe<Output, Failure: Error>: Publisher {
    /// Called on the main actor (`_subscribe`); nonisolated in type so an operator built off
    /// the main actor can capture its upstream.
    public let subscribe: (_ receive: @escaping @MainActor (Output) -> Void,
                           _ complete: @escaping @MainActor (Subscribers.Completion<Failure>) -> Void) -> AnyCancellable
    /// What a Combine subscriber's subscription does with values it hasn't asked for.
    let _policy: _DemandPolicy
    public init(_ subscribe: @escaping (_ receive: @escaping @MainActor (Output) -> Void,
                                        _ complete: @escaping @MainActor (Subscribers.Completion<Failure>) -> Void) -> AnyCancellable) {
        self.init(policy: .hold, subscribe)
    }
    init(policy: _DemandPolicy,
         _ subscribe: @escaping (_ receive: @escaping @MainActor (Output) -> Void,
                                 _ complete: @escaping @MainActor (Subscribers.Completion<Failure>) -> Void) -> AnyCancellable) {
        self.subscribe = subscribe
        _policy = policy
    }
    @MainActor public func _subscribe(_ receive: @escaping @MainActor (Output) -> Void,
                                      _ complete: @escaping @MainActor (Subscribers.Completion<Failure>) -> Void) -> AnyCancellable {
        subscribe(receive, complete)
    }
}

extension Publisher {
    /// `_subscribe` from a pipe's closure, which runs on the main actor without saying so.
    func _subscribeOnMain(_ receive: @escaping @MainActor (Output) -> Void,
                          _ complete: @escaping @MainActor (Subscribers.Completion<Failure>) -> Void) -> AnyCancellable {
        _subscribeFromAnywhere(receive, complete)
    }
}

extension _Pipe: _CarriesDemandPolicy {
    var _carriedDemandPolicy: _DemandPolicy { _policy }
}

/// A publisher that performs type erasure by wrapping another publisher.
public struct AnyPublisher<Output, Failure: Error>: Publisher, _CarriesDemandPolicy {
    private let pipe: _Pipe<Output, Failure>
    public init<P: Publisher>(_ publisher: P) where P.Output == Output, P.Failure == Failure {
        pipe = _Pipe(policy: publisher._demandPolicy) { receive, complete in publisher._subscribeOnMain(receive, complete) }
    }
    var _carriedDemandPolicy: _DemandPolicy { pipe._policy }
    @MainActor public func _subscribe(_ receive: @escaping @MainActor (Output) -> Void,
                                      _ complete: @escaping @MainActor (Subscribers.Completion<Failure>) -> Void) -> AnyCancellable {
        pipe.subscribe(receive, complete)
    }
}

/// A box for the state an operator keeps per subscription (the main actor owns it).
final class _State<Value>: @unchecked Sendable {
    var value: Value
    init(_ value: Value) { self.value = value }
}

extension Publisher {
    public func eraseToAnyPublisher() -> AnyPublisher<Output, Failure> { AnyPublisher(self) }

    // MARK: Transforming

    public func map<T>(_ transform: @escaping @MainActor (Output) -> T) -> _Pipe<T, Failure> {
        _Pipe(policy: _demandPolicy) { receive, complete in self._subscribeOnMain({ receive(transform($0)) }, complete) }
    }
    public func map<T>(_ keyPath: KeyPath<Output, T>) -> _Pipe<T, Failure> {
        nonisolated(unsafe) let keyPath = keyPath
        return map { $0[keyPath: keyPath] }
    }
    public func tryMap<T>(_ transform: @escaping @MainActor (Output) throws -> T) -> _Pipe<T, any Error> {
        _Pipe { receive, complete in
            let done = _State(false)
            let upstream = self._subscribeOnMain({ value in
                guard !done.value else { return }
                do { receive(try transform(value)) } catch { done.value = true; complete(.failure(error)) }
            }, { completion in
                guard !done.value else { return }
                switch completion {
                case .finished: complete(.finished)
                case .failure(let error): complete(.failure(error))
                }
            })
            return AnyCancellable { upstream.cancel() }
        }
    }
    /// Decodes each value with a top-level decoder (`JSONDecoder` over `Data`); a value that
    /// fails to decode ends the stream with the decoder's error.
    public func decode<Item: Decodable, Coder: TopLevelDecoder>(type: Item.Type, decoder: Coder) -> _Pipe<Item, any Error> where Output == Coder.Input {
        nonisolated(unsafe) let decoder = decoder
        return tryMap { try decoder.decode(Item.self, from: $0) }
    }
    /// Encodes each value with a top-level encoder (`JSONEncoder` to `Data`).
    public func encode<Coder: TopLevelEncoder>(encoder: Coder) -> _Pipe<Coder.Output, any Error> where Output: Encodable {
        nonisolated(unsafe) let encoder = encoder
        return tryMap { try encoder.encode($0) }
    }
    public func compactMap<T>(_ transform: @escaping @MainActor (Output) -> T?) -> _Pipe<T, Failure> {
        _Pipe(policy: _demandPolicy) { receive, complete in self._subscribeOnMain({ if let value = transform($0) { receive(value) } }, complete) }
    }
    public func scan<T>(_ initial: T, _ nextPartial: @escaping @MainActor (T, Output) -> T) -> _Pipe<T, Failure> {
        _Pipe { receive, complete in
            let accumulated = _State(initial)
            return self._subscribeOnMain({ accumulated.value = nextPartial(accumulated.value, $0); receive(accumulated.value) }, complete)
        }
    }
    public func replaceNil<T>(with output: T) -> _Pipe<T, Failure> where Output == T? {
        nonisolated(unsafe) let output = output
        return map { $0 ?? output }
    }
    public func replaceEmpty(with output: Output) -> _Pipe<Output, Failure> {
        nonisolated(unsafe) let output = output
        return _Pipe { receive, complete in
            let any = _State(false)
            return self._subscribeOnMain({ any.value = true; receive($0) }, { completion in
                if case .finished = completion, !any.value { receive(output) }
                complete(completion)
            })
        }
    }
    public func flatMap<P: Publisher>(maxPublishers: Int = .max, _ transform: @escaping @MainActor (Output) -> P) -> _Pipe<P.Output, Failure> where P.Failure == Failure {
        _Pipe { receive, complete in
            let inner = _State<[AnyCancellable]>([])
            let upstream = self._subscribeOnMain({ value in
                inner.value.append(transform(value)._subscribeOnMain(receive, { completion in
                    if case .failure = completion { complete(completion) }
                }))
            }, complete)
            return AnyCancellable { upstream.cancel(); inner.value.forEach { $0.cancel() } }
        }
    }
    public func switchToLatest() -> _Pipe<Output.Output, Failure> where Output: Publisher, Output.Failure == Failure {
        _Pipe { receive, complete in
            let current = _State<AnyCancellable?>(nil)
            let upstream = self._subscribeOnMain({ publisher in
                current.value?.cancel()
                current.value = publisher._subscribeOnMain(receive, { if case .failure = $0 { complete($0) } })
            }, complete)
            return AnyCancellable { upstream.cancel(); current.value?.cancel() }
        }
    }

    // MARK: Filtering

    public func filter(_ isIncluded: @escaping @MainActor (Output) -> Bool) -> _Pipe<Output, Failure> {
        _Pipe(policy: _demandPolicy) { receive, complete in self._subscribeOnMain({ if isIncluded($0) { receive($0) } }, complete) }
    }
    /// Apple's takes a plain closure, which TCA's `ViewStore` hands it from nonisolated code; it
    /// runs on the main actor with the rest of the pipe.
    public func removeDuplicates(by predicate: @escaping (Output, Output) -> Bool) -> _Pipe<Output, Failure> {
        nonisolated(unsafe) let predicate = predicate
        return _Pipe { receive, complete in
            let last = _State<Output?>(nil)
            return self._subscribeOnMain({ value in
                if let previous = last.value, predicate(previous, value) { return }
                last.value = value
                receive(value)
            }, complete)
        }
    }
    public func removeDuplicates() -> _Pipe<Output, Failure> where Output: Equatable { removeDuplicates(by: { $0 == $1 }) }
    public func first() -> _Pipe<Output, Failure> { prefix(1) }
    public func first(where predicate: @escaping @MainActor (Output) -> Bool) -> _Pipe<Output, Failure> { filter(predicate).prefix(1) }
    public func last() -> _Pipe<Output, Failure> {
        _Pipe { receive, complete in
            let kept = _State<Output?>(nil)
            return self._subscribeOnMain({ kept.value = $0 }, { completion in
                if case .finished = completion, let value = kept.value { receive(value) }
                complete(completion)
            })
        }
    }
    public func dropFirst(_ count: Int = 1) -> _Pipe<Output, Failure> {
        _Pipe { receive, complete in
            let seen = _State(0)
            return self._subscribeOnMain({ seen.value += 1; if seen.value > count { receive($0) } }, complete)
        }
    }
    public func drop(while predicate: @escaping @MainActor (Output) -> Bool) -> _Pipe<Output, Failure> {
        _Pipe { receive, complete in
            let dropping = _State(true)
            return self._subscribeOnMain({ if dropping.value && predicate($0) { return }; dropping.value = false; receive($0) }, complete)
        }
    }
    /// The first `count` values, then finished (the upstream subscription is cancelled).
    public func prefix(_ count: Int) -> _Pipe<Output, Failure> {
        _Pipe { receive, complete in
            let seen = _State(0)
            let upstream = _State<AnyCancellable?>(nil)
            guard count > 0 else { MainActor.assumeIsolated { complete(.finished) }; return AnyCancellable {} }
            upstream.value = self._subscribeOnMain({ value in
                guard seen.value < count else { return }
                seen.value += 1
                receive(value)
                if seen.value == count { upstream.value?.cancel(); upstream.value = nil; complete(.finished) }
            }, { completion in if seen.value < count { complete(completion) } })
            if seen.value >= count { upstream.value?.cancel(); upstream.value = nil }
            return AnyCancellable { upstream.value?.cancel() }
        }
    }
    public func prefix(while predicate: @escaping @MainActor (Output) -> Bool) -> _Pipe<Output, Failure> {
        _Pipe { receive, complete in
            let done = _State(false)
            let upstream = _State<AnyCancellable?>(nil)
            upstream.value = self._subscribeOnMain({ value in
                guard !done.value else { return }
                if predicate(value) { receive(value) } else { done.value = true; upstream.value?.cancel(); complete(.finished) }
            }, { if !done.value { complete($0) } })
            return AnyCancellable { upstream.value?.cancel() }
        }
    }
    public func collect() -> _Pipe<[Output], Failure> {
        _Pipe { receive, complete in
            let values = _State<[Output]>([])
            return self._subscribeOnMain({ values.value.append($0) }, { completion in
                if case .finished = completion { receive(values.value) }
                complete(completion)
            })
        }
    }

    // MARK: Errors

    public func mapError<E: Error>(_ transform: @escaping @MainActor (Failure) -> E) -> _Pipe<Output, E> {
        _Pipe(policy: _demandPolicy) { receive, complete in
            self._subscribeOnMain(receive) { completion in
                switch completion {
                case .finished: complete(.finished)
                case .failure(let error): complete(.failure(transform(error)))
                }
            }
        }
    }
    public func setFailureType<E: Error>(to failureType: E.Type) -> _Pipe<Output, E> where Failure == Never {
        _Pipe(policy: _demandPolicy) { receive, complete in self._subscribeOnMain(receive) { _ in complete(.finished) } }
    }
    public func assertNoFailure(_ prefix: String = "") -> _Pipe<Output, Never> {
        _Pipe { receive, complete in
            self._subscribeOnMain(receive) { completion in
                if case .failure(let error) = completion { fatalError("\(prefix)\(error)") }
                complete(.finished)
            }
        }
    }
    public func `catch`<P: Publisher>(_ handler: @escaping @MainActor (Failure) -> P) -> _Pipe<Output, P.Failure> where P.Output == Output {
        _Pipe { receive, complete in
            let fallback = _State<AnyCancellable?>(nil)
            let upstream = self._subscribeOnMain(receive) { completion in
                switch completion {
                case .finished: complete(.finished)
                case .failure(let error): fallback.value = handler(error)._subscribeOnMain(receive, complete)
                }
            }
            return AnyCancellable { upstream.cancel(); fallback.value?.cancel() }
        }
    }
    public func replaceError(with output: Output) -> _Pipe<Output, Never> {
        nonisolated(unsafe) let output = output
        return _Pipe { receive, complete in
            self._subscribeOnMain(receive) { completion in
                if case .failure = completion { receive(output) }
                complete(.finished)
            }
        }
    }
    public func retry(_ retries: Int) -> _Pipe<Output, Failure> {
        nonisolated(unsafe) let upstream = self
        return _Pipe { receive, complete in
            let current = _State<AnyCancellable?>(nil)
            @MainActor func attempt(_ remaining: Int) {
                current.value = upstream._subscribeOnMain(receive) { completion in
                    if case .failure = completion, remaining > 0 { attempt(remaining - 1) } else { complete(completion) }
                }
            }
            MainActor.assumeIsolated { attempt(retries) }
            return AnyCancellable { current.value?.cancel() }
        }
    }

    // MARK: Combining

    public func merge<P: Publisher>(with other: P) -> _Pipe<Output, Failure> where P.Output == Output, P.Failure == Failure {
        Publishers.Merge(self, other).pipe
    }
    public func combineLatest<P: Publisher>(_ other: P) -> _Pipe<(Output, P.Output), Failure> where P.Failure == Failure {
        Publishers.CombineLatest(self, other).pipe
    }
    public func combineLatest<P: Publisher, T>(_ other: P, _ transform: @escaping @MainActor (Output, P.Output) -> T) -> _Pipe<T, Failure> where P.Failure == Failure {
        combineLatest(other).map(transform)
    }
    public func zip<P: Publisher>(_ other: P) -> _Pipe<(Output, P.Output), Failure> where P.Failure == Failure {
        _Pipe { receive, complete in
            let a = _State<[Output]>([]), b = _State<[P.Output]>([])
            let ended = _State(false)
            @MainActor func drain() { while !a.value.isEmpty && !b.value.isEmpty { receive((a.value.removeFirst(), b.value.removeFirst())) } }
            @MainActor func end(_ completion: Subscribers.Completion<Failure>) { if !ended.value { ended.value = true; complete(completion) } }
            let x = self._subscribeOnMain({ a.value.append($0); drain() }, end)
            let y = other._subscribeOnMain({ b.value.append($0); drain() }, end)
            return AnyCancellable { x.cancel(); y.cancel() }
        }
    }
    public func prepend(_ elements: Output...) -> _Pipe<Output, Failure> {
        nonisolated(unsafe) let elements = elements
        return _Pipe { receive, complete in
            MainActor.assumeIsolated { for element in elements { receive(element) } }
            return self._subscribeOnMain(receive, complete)
        }
    }
    public func append(_ elements: Output...) -> _Pipe<Output, Failure> {
        nonisolated(unsafe) let elements = elements
        return _Pipe { receive, complete in
            self._subscribeOnMain(receive) { completion in
                if case .finished = completion { for element in elements { receive(element) } }
                complete(completion)
            }
        }
    }

    // MARK: Time

    /// Delivers a value after `interval` of silence (the last one of a burst).
    public func debounce(for interval: Double, scheduler: Any? = nil, options: Any? = nil) -> _Pipe<Output, Failure> {
        _Pipe { receive, complete in
            let pending = _State<Task<Void, Never>?>(nil)
            let upstream = self._subscribeOnMain({ value in
                pending.value?.cancel()
                pending.value = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: UInt64(max(0, interval) * 1_000_000_000))
                    if !Task.isCancelled { receive(value) }
                }
            }, { completion in pending.value?.cancel(); complete(completion) })
            return AnyCancellable { upstream.cancel(); pending.value?.cancel() }
        }
    }
    /// Delivers every value `interval` later.
    public func delay(for interval: Double, tolerance: Double? = nil, scheduler: Any? = nil, options: Any? = nil) -> _Pipe<Output, Failure> {
        _Pipe { receive, complete in
            let tasks = _State<[Task<Void, Never>]>([])
            let upstream = self._subscribeOnMain({ value in
                tasks.value.append(Task { @MainActor in
                    try? await Task.sleep(nanoseconds: UInt64(max(0, interval) * 1_000_000_000))
                    if !Task.isCancelled { receive(value) }
                })
            }, { completion in
                tasks.value.append(Task { @MainActor in
                    try? await Task.sleep(nanoseconds: UInt64(max(0, interval) * 1_000_000_000))
                    if !Task.isCancelled { complete(completion) }
                })
            })
            return AnyCancellable { upstream.cancel(); tasks.value.forEach { $0.cancel() } }
        }
    }
    /// Delivers at most one value per `interval` (the first or the latest of the window).
    public func throttle(for interval: Double, scheduler: Any? = nil, latest: Bool) -> _Pipe<Output, Failure> {
        _Pipe { receive, complete in
            let window = _State<(task: Task<Void, Never>, latest: Output?)?>(nil)
            let upstream = self._subscribeOnMain({ value in
                if let open = window.value {
                    if latest { window.value = (open.task, value) }
                    return
                }
                receive(value)
                window.value = (Task { @MainActor in
                    try? await Task.sleep(nanoseconds: UInt64(max(0, interval) * 1_000_000_000))
                    let held = window.value?.latest
                    window.value = nil
                    if !Task.isCancelled, let held { receive(held) }
                }, nil)
            }, complete)
            return AnyCancellable { upstream.cancel(); window.value?.task.cancel() }
        }
    }
    /// Fails with `error` (or finishes) when no value arrives within `interval`.
    public func timeout<E: Error>(_ interval: Double, scheduler: Any? = nil, options: Any? = nil, customError: (() -> E)? = nil) -> _Pipe<Output, E> where Failure == E {
        nonisolated(unsafe) let customError = customError
        return _Pipe { receive, complete in
            let timer = _State<Task<Void, Never>?>(nil)
            let upstream = _State<AnyCancellable?>(nil)
            let done = _State(false)
            @MainActor func arm() {
                timer.value?.cancel()
                timer.value = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: UInt64(max(0, interval) * 1_000_000_000))
                    guard !Task.isCancelled, !done.value else { return }
                    done.value = true
                    upstream.value?.cancel()
                    if let customError { complete(.failure(customError())) } else { complete(.finished) }
                }
            }
            upstream.value = self._subscribeOnMain({ value in guard !done.value else { return }; receive(value); arm() },
                                             { completion in guard !done.value else { return }; done.value = true; timer.value?.cancel(); complete(completion) })
            MainActor.assumeIsolated { arm() }
            return AnyCancellable { upstream.value?.cancel(); timer.value?.cancel() }
        }
    }

    // MARK: Schedulers, sharing, side effects

    /// The values delivered on the main actor (every delivery already is).
    public func receive(on scheduler: Any, options: Any? = nil) -> Self { self }
    public func subscribe(on scheduler: Any, options: Any? = nil) -> Self { self }

    /// One upstream subscription shared by every subscriber, made on the first.
    public func share() -> _Pipe<Output, Failure> {
        let subject = PassthroughSubject<Output, Failure>()
        let upstream = _State<AnyCancellable?>(nil)
        let count = _State(0)
        return _Pipe { receive, complete in
            let subscription = subject._subscribeOnMain(receive, complete)
            count.value += 1
            if upstream.value == nil {
                upstream.value = self._subscribeOnMain({ subject.send($0) }, { subject.send(completion: $0) })
            }
            return AnyCancellable {
                subscription.cancel()
                count.value -= 1
                if count.value == 0 { upstream.value?.cancel(); upstream.value = nil }
            }
        }
    }
    /// Runs the closures as the subscription's events happen, then passes each one on. The
    /// subscription handed to `receiveSubscription` cancels this one; the closure publishers
    /// deliver without counting demand, so `receiveRequest` hears one `.unlimited`, as a
    /// `sink`'s request would be.
    public func handleEvents(receiveSubscription: (@MainActor (any Subscription) -> Void)? = nil,
                             receiveOutput: (@MainActor (Output) -> Void)? = nil,
                             receiveCompletion: (@MainActor (Subscribers.Completion<Failure>) -> Void)? = nil,
                             receiveCancel: (@MainActor () -> Void)? = nil,
                             receiveRequest: (@MainActor (Subscribers.Demand) -> Void)? = nil) -> Publishers.HandleEvents<Self> {
        Publishers.HandleEvents(upstream: self, receiveSubscription: receiveSubscription, receiveOutput: receiveOutput,
                                receiveCompletion: receiveCompletion, receiveCancel: receiveCancel, receiveRequest: receiveRequest)
    }
    public func print(_ prefix: String = "", to stream: Any? = nil) -> _Pipe<Output, Failure> {
        let label = prefix.isEmpty ? "" : prefix + ": "
        let events = handleEvents(receiveSubscription: { _ in Swift.print("\(label)receive subscription") },
                                  receiveOutput: { Swift.print("\(label)receive value: (\($0))") },
                                  receiveCompletion: { Swift.print("\(label)receive \($0)") },
                                  receiveCancel: { Swift.print("\(label)receive cancel") })
        return _Pipe(policy: _demandPolicy) { receive, complete in events._subscribeOnMain(receive, complete) }
    }
    /// Passes the values on until `other` publishes one, then finishes (`other` ending without a
    /// value changes nothing).
    public func prefix<P: Publisher>(untilOutputFrom other: P) -> Publishers.PrefixUntilOutput<Self, P> {
        Publishers.PrefixUntilOutput(upstream: self, other: other)
    }

    /// The values as an asynchronous sequence that ends by throwing the failure
    /// (`for try await value in publisher.values`).
    public var values: AsyncThrowingPublisher<Self> { AsyncThrowingPublisher(self) }

    /// A stream of the values: subscribed on the main actor, cancelled when the loop ends.
    func _valueStream() -> AsyncThrowingStream<Output, any Error> {
        nonisolated(unsafe) let publisher = self
        return AsyncThrowingStream { continuation in
            let subscription = _State<AnyCancellable?>(nil)
            Task { @MainActor in
                subscription.value = publisher._subscribeOnMain({ value in nonisolated(unsafe) let value = value; continuation.yield(value) }, { completion in
                    switch completion {
                    case .finished: continuation.finish()
                    case .failure(let error): continuation.finish(throwing: error)
                    }
                })
            }
            continuation.onTermination = { _ in subscription.value?.cancel() }
        }
    }
}

extension Publisher where Failure == Never {
    /// The values as an asynchronous sequence that can't fail (`for await value in publisher.values`).
    public var values: AsyncPublisher<Self> { AsyncPublisher(self) }

    func _neverValueStream() -> AsyncStream<Output> {
        nonisolated(unsafe) let publisher = self
        return AsyncStream { continuation in
            let subscription = _State<AnyCancellable?>(nil)
            Task { @MainActor in
                subscription.value = publisher._subscribeOnMain({ value in nonisolated(unsafe) let value = value; continuation.yield(value) }, { _ in
                    continuation.finish()
                })
            }
            continuation.onTermination = { _ in subscription.value?.cancel() }
        }
    }
}

/// A never-failing publisher's values as an asynchronous sequence (`Publisher.values`). Each
/// iterator subscribes once; ending the loop cancels the subscription.
public struct AsyncPublisher<P: Publisher>: AsyncSequence where P.Failure == Never {
    public typealias Element = P.Output
    public typealias Failure = Never
    let publisher: P
    public init(_ publisher: P) { self.publisher = publisher }

    public struct Iterator: AsyncIteratorProtocol {
        public typealias Element = P.Output
        public typealias Failure = Never
        final class Box: @unchecked Sendable {
            var base: AsyncStream<P.Output>.Iterator
            init(_ base: AsyncStream<P.Output>.Iterator) { self.base = base }
        }
        let box: Box
        public mutating func next() async -> P.Output? { await box.base.next() }
    }
    public func makeAsyncIterator() -> Iterator { Iterator(box: .init(publisher._neverValueStream().makeAsyncIterator())) }
}

/// A publisher's values as an asynchronous sequence that throws the publisher's failure
/// (`Publisher.values`).
public struct AsyncThrowingPublisher<P: Publisher>: AsyncSequence {
    public typealias Element = P.Output
    public typealias Failure = any Error
    let publisher: P
    public init(_ publisher: P) { self.publisher = publisher }

    public struct Iterator: AsyncIteratorProtocol {
        public typealias Element = P.Output
        public typealias Failure = any Error
        final class Box: @unchecked Sendable {
            var base: AsyncThrowingStream<P.Output, any Error>.Iterator
            init(_ base: AsyncThrowingStream<P.Output, any Error>.Iterator) { self.base = base }
        }
        let box: Box
        public mutating func next() async throws -> P.Output? { try await box.base.next() }
    }
    public func makeAsyncIterator() -> Iterator { Iterator(box: .init(publisher._valueStream().makeAsyncIterator())) }
}

// MARK: - Publishers

// Apple's names for the operators' publishers, each the pipe its operator returns here
// (TCA's `Effect.cancel(id:)` returns `Publishers.CompactMap<Just<Action?>, Action>`).
extension Publishers {
    public typealias Map<Upstream: Publisher, Output> = _Pipe<Output, Upstream.Failure>
    public typealias TryMap<Upstream: Publisher, Output> = _Pipe<Output, any Error>
    public typealias CompactMap<Upstream: Publisher, Output> = _Pipe<Output, Upstream.Failure>
    public typealias Scan<Upstream: Publisher, Output> = _Pipe<Output, Upstream.Failure>
    public typealias Filter<Upstream: Publisher> = _Pipe<Upstream.Output, Upstream.Failure>
    public typealias RemoveDuplicates<Upstream: Publisher> = _Pipe<Upstream.Output, Upstream.Failure>
    public typealias DropFirst<Upstream: Publisher> = _Pipe<Upstream.Output, Upstream.Failure>
    public typealias Collect<Upstream: Publisher> = _Pipe<[Upstream.Output], Upstream.Failure>
    public typealias MapError<Upstream: Publisher, Failure: Error> = _Pipe<Upstream.Output, Failure>
    public typealias SetFailureType<Upstream: Publisher, Failure: Error> = _Pipe<Upstream.Output, Failure>
    public typealias ReplaceError<Upstream: Publisher> = _Pipe<Upstream.Output, Never>
    public typealias FlatMap<NewPublisher: Publisher, Upstream: Publisher> = _Pipe<NewPublisher.Output, Upstream.Failure>
    public typealias SwitchToLatest<P: Publisher, Upstream: Publisher> = _Pipe<P.Output, Upstream.Failure>
    public typealias Share<Upstream: Publisher> = _Pipe<Upstream.Output, Upstream.Failure>
}


public enum Publishers {
    /// A publisher created by applying the merge function to two upstream publishers.
    public struct Merge<A: Publisher, B: Publisher>: Publisher where A.Output == B.Output, A.Failure == B.Failure {
        public typealias Output = A.Output
        public typealias Failure = A.Failure
        public let a: A
        public let b: B
        public init(_ a: A, _ b: B) { self.a = a; self.b = b }
        var pipe: _Pipe<Output, Failure> { MergeMany<AnyPublisher<Output, Failure>>([a.eraseToAnyPublisher(), b.eraseToAnyPublisher()]).pipe }
        @MainActor public func _subscribe(_ receive: @escaping @MainActor (Output) -> Void,
                                          _ complete: @escaping @MainActor (Subscribers.Completion<Failure>) -> Void) -> AnyCancellable {
            pipe.subscribe(receive, complete)
        }
    }

    /// A publisher created by applying the merge function to an arbitrary number of upstream publishers.
    public struct MergeMany<Upstream: Publisher>: Publisher {
        public typealias Output = Upstream.Output
        public typealias Failure = Upstream.Failure
        public let publishers: [Upstream]
        public init(_ upstream: Upstream...) { publishers = upstream }
        public init<S: Swift.Sequence>(_ upstream: S) where S.Element == Upstream { publishers = Array(upstream) }
        var pipe: _Pipe<Output, Failure> {
            let publishers = self.publishers
            return _Pipe { receive, complete in
                let remaining = _State(publishers.count)
                let ended = _State(false)
                let subscriptions = publishers.map { publisher in
                    publisher._subscribeOnMain(receive) { completion in
                        guard !ended.value else { return }
                        switch completion {
                        case .failure: ended.value = true; complete(completion)
                        case .finished: remaining.value -= 1; if remaining.value == 0 { ended.value = true; complete(.finished) }
                        }
                    }
                }
                if publishers.isEmpty { MainActor.assumeIsolated { complete(.finished) } }
                return AnyCancellable { subscriptions.forEach { $0.cancel() } }
            }
        }
        @MainActor public func _subscribe(_ receive: @escaping @MainActor (Output) -> Void,
                                          _ complete: @escaping @MainActor (Subscribers.Completion<Failure>) -> Void) -> AnyCancellable {
            pipe.subscribe(receive, complete)
        }
    }

    /// A publisher that receives and combines the latest elements from two publishers.
    public struct CombineLatest<A: Publisher, B: Publisher>: Publisher where A.Failure == B.Failure {
        public typealias Output = (A.Output, B.Output)
        public typealias Failure = A.Failure
        public let a: A
        public let b: B
        public init(_ a: A, _ b: B) { self.a = a; self.b = b }
        var pipe: _Pipe<Output, Failure> {
            _Pipe { receive, complete in
                let latestA = _State<A.Output?>(nil), latestB = _State<B.Output?>(nil)
                let remaining = _State(2), ended = _State(false)
                @MainActor func emit() { if let x = latestA.value, let y = latestB.value { receive((x, y)) } }
                @MainActor func end(_ completion: Subscribers.Completion<Failure>) {
                    guard !ended.value else { return }
                    switch completion {
                    case .failure: ended.value = true; complete(completion)
                    case .finished: remaining.value -= 1; if remaining.value == 0 { ended.value = true; complete(.finished) }
                    }
                }
                let x = a._subscribeOnMain({ latestA.value = $0; emit() }, end)
                let y = b._subscribeOnMain({ latestB.value = $0; emit() }, end)
                return AnyCancellable { x.cancel(); y.cancel() }
            }
        }
        @MainActor public func _subscribe(_ receive: @escaping @MainActor (Output) -> Void,
                                          _ complete: @escaping @MainActor (Subscribers.Completion<Failure>) -> Void) -> AnyCancellable {
            pipe.subscribe(receive, complete)
        }
    }

    /// A publisher that publishes a given sequence of elements.
    public struct Sequence<Elements: Swift.Sequence, Failure: Error>: Publisher {
        public typealias Output = Elements.Element
        public let sequence: Elements
        public init(sequence: Elements) { self.sequence = sequence }
        @MainActor public func _subscribe(_ receive: @escaping @MainActor (Output) -> Void,
                                          _ complete: @escaping @MainActor (Subscribers.Completion<Failure>) -> Void) -> AnyCancellable {
            for element in sequence { receive(element) }
            complete(.finished)
            return AnyCancellable {}
        }
    }

    /// A publisher that emits all of one publisher's elements before those from another.
    public struct Concatenate<Prefix: Publisher, Suffix: Publisher>: Publisher
    where Prefix.Output == Suffix.Output, Prefix.Failure == Suffix.Failure {
        public typealias Output = Suffix.Output
        public typealias Failure = Suffix.Failure
        public let prefix: Prefix
        public let suffix: Suffix
        public init(prefix: Prefix, suffix: Suffix) { self.prefix = prefix; self.suffix = suffix }
        @MainActor public func _subscribe(_ receive: @escaping @MainActor (Output) -> Void,
                                          _ complete: @escaping @MainActor (Subscribers.Completion<Failure>) -> Void) -> AnyCancellable {
            let suffix = self.suffix
            let current = _State<AnyCancellable?>(nil)
            let cancelled = _State(false)
            // A suffix that publishes synchronously (a sequence) runs to its end before its token
            // exists, so a cancel from downstream mid-way is honoured by dropping what follows.
            let forward: @MainActor (Output) -> Void = { if !cancelled.value { receive($0) } }
            let finish: @MainActor (Subscribers.Completion<Failure>) -> Void = { if !cancelled.value { complete($0) } }
            let first = prefix._subscribeOnMain(forward) { completion in
                guard case .finished = completion else { return finish(completion) }
                guard !cancelled.value else { return }
                current.value = suffix._subscribeOnMain(forward, finish)
            }
            if current.value == nil { current.value = first }
            return AnyCancellable { cancelled.value = true; current.value?.cancel() }
        }
    }
}

extension Publisher {
    /// This publisher's elements, then the other's once this one finishes.
    public func append<P: Publisher>(_ publisher: P) -> Publishers.Concatenate<Self, P> where P.Output == Output, P.Failure == Failure {
        Publishers.Concatenate(prefix: self, suffix: publisher)
    }
    /// The other publisher's elements, then this one's once the other finishes.
    public func prepend<P: Publisher>(_ publisher: P) -> Publishers.Concatenate<P, Self> where P.Output == Output, P.Failure == Failure {
        Publishers.Concatenate(prefix: publisher, suffix: self)
    }
}

extension Sequence {
    /// A publisher of the sequence's elements.
    public var publisher: Publishers.Sequence<Self, Never> { Publishers.Sequence(sequence: self) }
}

/// A publisher that eventually produces a single value and then finishes or fails.
public final class Future<Output, Failure: Error>: Publisher, @unchecked Sendable {
    public typealias Promise = (Result<Output, Failure>) -> Void
    private var result: Result<Output, Failure>?
    private let subscribers = _Subscribers<Output, Failure>()

    public init(_ attemptToFulfill: @escaping (@escaping Promise) -> Void) {
        attemptToFulfill { [weak self] result in
            guard let self, self.result == nil else { return }
            self.result = result
            switch result {
            case .success(let value): self.subscribers.send(value); self.subscribers.send(completion: .finished)
            case .failure(let error): self.subscribers.send(completion: .failure(error))
            }
        }
    }

    @MainActor public func _subscribe(_ receive: @escaping @MainActor (Output) -> Void,
                                      _ complete: @escaping @MainActor (Subscribers.Completion<Failure>) -> Void) -> AnyCancellable {
        if let result {
            switch result {
            case .success(let value): receive(value); complete(.finished)
            case .failure(let error): complete(.failure(error))
            }
            return AnyCancellable {}
        }
        return subscribers.add(receive, complete)
    }
}

/// A publisher that awaits subscription before running the supplied closure to create a publisher for the new subscriber.
public struct Deferred<DeferredPublisher: Publisher>: Publisher {
    public typealias Output = DeferredPublisher.Output
    public typealias Failure = DeferredPublisher.Failure
    public let createPublisher: @MainActor () -> DeferredPublisher
    public init(createPublisher: @escaping @MainActor () -> DeferredPublisher) { self.createPublisher = createPublisher }
    @MainActor public func _subscribe(_ receive: @escaping @MainActor (Output) -> Void,
                                      _ complete: @escaping @MainActor (Subscribers.Completion<Failure>) -> Void) -> AnyCancellable {
        createPublisher()._subscribeOnMain(receive, complete)
    }
}

// MARK: - Top-level coders (decision 0021: `decode(type:decoder:)` on a publisher of data)

/// A type that defines methods for decoding (Combine's; `JSONDecoder` conforms).
public protocol TopLevelDecoder {
    associatedtype Input
    func decode<T: Decodable>(_ type: T.Type, from: Input) throws -> T
}

/// A type that defines methods for encoding (Combine's; `JSONEncoder` conforms).
public protocol TopLevelEncoder {
    associatedtype Output
    func encode<T: Encodable>(_ value: T) throws -> Output
}

extension JSONDecoder: TopLevelDecoder {}
extension JSONEncoder: TopLevelEncoder {}
