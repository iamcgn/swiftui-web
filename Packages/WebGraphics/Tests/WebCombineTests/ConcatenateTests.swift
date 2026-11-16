// `append` and `prepend`: the suffix starts once the prefix finishes, and a downstream cancel
// stops it even when the suffix publishes synchronously.
import Testing
#if !canImport(Darwin)
import WebFoundation
#endif
@testable import WebCombine

@MainActor @Suite struct ConcatenateTests {
    @Test func appendsAfterThePrefixFinishes() {
        let subject = PassthroughSubject<Int, Never>()
        var values: [Int] = []
        var completions = 0
        let token = subject.append([2, 3].publisher).sink(receiveCompletion: { _ in completions += 1 }, receiveValue: { values.append($0) })
        subject.send(1)
        subject.send(completion: .finished)
        #expect(values == [1, 2, 3] && completions == 1)
        token.cancel()
    }

    @Test func cancellingDuringASynchronousSuffixStopsIt() {
        let subject = PassthroughSubject<Int, Never>()
        var values: [Int] = []
        var completions = 0
        var token: AnyCancellable?
        token = subject.append([1, 2, 3].publisher).sink(receiveCompletion: { _ in completions += 1 }, receiveValue: { value in
            values.append(value)
            if value == 1 { token?.cancel() }
        })
        subject.send(completion: .finished)
        #expect(values == [1])
        #expect(completions == 0)
        _ = token
    }
}
