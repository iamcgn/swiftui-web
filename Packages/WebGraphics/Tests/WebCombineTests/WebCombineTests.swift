// Decision 0021: Combine's publishers without Combine — values, completion and failure through
// the closure subscriptions, the subjects, Future, and the operators apps chain (map, filter,
// removeDuplicates, first, merge, combineLatest, catch, share, collect, zip, scan, prefix).
import Testing
@testable import WebCombine

@MainActor @Suite(.serialized) struct WebCombineTests {
    enum Failure: Error, Equatable { case bad }

    @Test func justAndSubjectsDeliverValuesThenCompletion() {
        var values: [Int] = []
        var completions: [String] = []
        let just = Just(1).sink(receiveCompletion: { completions.append("\($0)") }, receiveValue: { values.append($0) })
        #expect(values == [1] && completions == ["finished"])
        just.cancel()

        let subject = PassthroughSubject<Int, Failure>()
        let a = subject.sink(receiveCompletion: { completions.append("\($0)") }, receiveValue: { values.append($0) })
        subject.send(2)
        subject.send(3)
        a.cancel()
        subject.send(4)                       // cancelled: not delivered
        #expect(values == [1, 2, 3])
        let b = subject.sink(receiveCompletion: { completions.append("\($0)") }, receiveValue: { values.append($0) })
        subject.send(completion: .failure(.bad))
        subject.send(5)                       // after completion: nothing
        #expect(values == [1, 2, 3] && completions == ["finished", "failure(WebCombineTests.WebCombineTests.Failure.bad)"])
        _ = subject.sink(receiveCompletion: { completions.append("late \($0)") }, receiveValue: { _ in })
        #expect(completions.last == "late failure(WebCombineTests.WebCombineTests.Failure.bad)")   // a late subscriber hears the completion
        b.cancel()

        let current = CurrentValueSubject<String, Never>("a")
        var seen: [String] = []
        let c = current.sink { seen.append($0) }
        current.value = "b"
        current.send("c")
        #expect(seen == ["a", "b", "c"] && current.value == "c")
        c.cancel()
    }

    @Test func publishedAndObjectWillChange() {
        final class Model: ObservableObject {
            @Published var count = 0
        }
        let model = Model()
        var changes = 0
        var values: [Int] = []
        let a = model.objectWillChange.sink { changes += 1 }
        let b = model.$count.sink { values.append($0) }
        model.count = 1
        model.count = 2
        #expect(changes == 2 && values.first == 0)   // the current value first; later ones arrive after the change
        a.cancel(); b.cancel()
        var set = Set<AnyCancellable>()
        model.objectWillChange.sink { changes += 1 }.store(in: &set)
        model.count = 3
        set.removeAll()                            // deallocating the cancellable ends the subscription
        model.count = 4
        #expect(changes == 3)
    }

    @Test func transformingAndFilteringOperators() {
        let subject = PassthroughSubject<Int, Never>()
        var out: [String] = []
        var done = false
        let c = subject
            .filter { $0 % 2 == 0 }
            .map { $0 * 10 }
            .removeDuplicates()
            .map(String.init)
            .sink(receiveCompletion: { _ in done = true }, receiveValue: { out.append($0) })
        for n in [1, 2, 2, 3, 4, 4, 6] { subject.send(n) }
        subject.send(completion: .finished)
        #expect(out == ["20", "40", "60"] && done)
        c.cancel()

        var firsts: [Int] = []
        var firstDone = false
        let source = PassthroughSubject<Int, Never>()
        let f = source.first().sink(receiveCompletion: { _ in firstDone = true }, receiveValue: { firsts.append($0) })
        source.send(7); source.send(8)
        #expect(firsts == [7] && firstDone)
        f.cancel()

        var collected: [[Int]] = []
        let g = [1, 2, 3].publisher.scan(0, +).dropFirst().prefix(2).collect().sink { collected.append($0) }
        #expect(collected == [[3, 6]])
        g.cancel()

        var compacted: [Int] = []
        let h = ["1", "x", "3"].publisher.compactMap(Int.init).sink { compacted.append($0) }
        #expect(compacted == [1, 3])
        h.cancel()

        var keyed: [Int] = []
        struct Item { var size: Int }
        let k = [Item(size: 4), Item(size: 5)].publisher.map(\.size).sink { keyed.append($0) }
        #expect(keyed == [4, 5])
        k.cancel()
    }

    @Test func combiningOperators() {
        let a = PassthroughSubject<Int, Never>(), b = PassthroughSubject<Int, Never>()
        var merged: [Int] = []
        var mergedDone = false
        let m = Publishers.Merge(a, b).sink(receiveCompletion: { _ in mergedDone = true }, receiveValue: { merged.append($0) })
        a.send(1); b.send(2); a.send(3)
        a.send(completion: .finished)
        #expect(!mergedDone)
        b.send(completion: .finished)
        #expect(merged == [1, 2, 3] && mergedDone)
        m.cancel()

        let x = CurrentValueSubject<String, Never>("x"), y = PassthroughSubject<Int, Never>()
        var latest: [String] = []
        let l = x.combineLatest(y) { "\($0)\($1)" }.sink { latest.append($0) }
        y.send(1); x.send("z"); y.send(2)
        #expect(latest == ["x1", "z1", "z2"])
        l.cancel()

        var zipped: [String] = []
        let p = PassthroughSubject<Int, Never>(), q = PassthroughSubject<String, Never>()
        let z = p.zip(q).map { "\($0)\($1)" }.sink { zipped.append($0) }
        p.send(1); p.send(2); q.send("a"); q.send("b"); q.send("c")
        #expect(zipped == ["1a", "2b"])
        z.cancel()

        var pre: [Int] = []
        let r = [3].publisher.prepend(1, 2).append(4).sink { pre.append($0) }
        #expect(pre == [1, 2, 3, 4])
        r.cancel()
    }

    @Test func errorsFuturesAndSharing() {
        var out: [Int] = []
        var ends: [String] = []
        let failing = PassthroughSubject<Int, Failure>()
        let c = failing
            .tryMap { value -> Int in if value < 0 { throw Failure.bad }; return value }
            .catch { _ in Just(-1) }
            .sink(receiveCompletion: { ends.append("\($0)") }, receiveValue: { out.append($0) })
        failing.send(1); failing.send(-5); failing.send(2)
        #expect(out == [1, -1] && ends == ["finished"])
        c.cancel()

        var replaced: [Int] = []
        let d = Fail<Int, Failure>(error: .bad).replaceError(with: 9).sink { replaced.append($0) }
        #expect(replaced == [9])
        d.cancel()

        var mapped: [String] = []
        let e = Fail<Int, Failure>(error: .bad).mapError { _ in NSErrorLike(code: 3) }.sink(receiveCompletion: { mapped.append("\($0)") }, receiveValue: { _ in })
        #expect(mapped == ["failure(WebCombineTests.NSErrorLike(code: 3))"])
        e.cancel()

        var promise: Future<Int, Never>.Promise?
        let future = Future<Int, Never> { promise = $0 }
        var got: [Int] = []
        let f = future.sink { got.append($0) }
        promise?(.success(42))
        promise?(.success(43))                      // a future resolves once
        let g = future.sink { got.append($0) }      // a later subscriber gets the value
        #expect(got == [42, 42])
        f.cancel(); g.cancel()

        var upstreamSubscriptions = 0
        let shared = Deferred { () -> Just<Int> in upstreamSubscriptions += 1; return Just(5) }.share()
        var values: [Int] = []
        let s1 = shared.sink { values.append($0) }
        let s2 = shared.sink { values.append($0) }
        #expect(upstreamSubscriptions == 1 && values == [5])   // one upstream; Just finished before the second came
        s1.cancel(); s2.cancel()

        var erased: [Int] = []
        let any: AnyPublisher<Int, Never> = [1, 2].publisher.eraseToAnyPublisher()
        let h = any.sink { erased.append($0) }
        #expect(erased == [1, 2])
        h.cancel()
    }
}

struct NSErrorLike: Error { var code: Int }
