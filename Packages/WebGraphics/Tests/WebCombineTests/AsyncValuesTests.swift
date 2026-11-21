// `Publisher.values`: a never-failing publisher's values are an `AsyncPublisher` that loops with
// plain `for await` (EmojiText's timer loop), and any other's an `AsyncThrowingPublisher` that
// ends by throwing the failure.
import Testing
#if !canImport(Darwin)
import WebFoundation
#endif
@testable import WebCombine

private struct Boom: Error, Equatable {}

@MainActor @Suite struct AsyncValuesTests {
    @Test func aNeverFailingPublishersValuesLoopWithoutTry() async {
        let values: AsyncPublisher<AnyPublisher<Int, Never>> = [1, 2, 3].publisher.eraseToAnyPublisher().values
        var seen: [Int] = []
        for await value in values { seen.append(value) }
        #expect(seen == [1, 2, 3])
    }

    @Test func aSubjectsValuesEndWhenItFinishes() async {
        let subject = PassthroughSubject<String, Never>()
        let task = Task { @MainActor in
            var seen: [String] = []
            for await value in subject.values { seen.append(value) }
            return seen
        }
        for _ in 0..<50 { await Task.yield() }
        subject.send("a")
        subject.send("b")
        subject.send(completion: .finished)
        #expect(await task.value == ["a", "b"])
    }

    @Test func aFailingPublishersValuesThrowTheFailure() async {
        let values: AsyncThrowingPublisher<AnyPublisher<Int, Boom>> = Fail<Int, Boom>(error: Boom()).eraseToAnyPublisher().values
        var thrown: (any Error)?
        do {
            for try await _ in values {}
        } catch {
            thrown = error
        }
        #expect(thrown as? Boom == Boom())
    }
}
