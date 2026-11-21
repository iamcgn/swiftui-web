// `Result.publisher`, which Combine declares beside `Just` and `Fail` (Alamofire's response
// publishers map each result through it): a success publishes its value and finishes, a failure
// fails. On Apple platforms the type is Combine's, so these run where WebCombine declares it.
import Testing
#if !canImport(Darwin)
import WebFoundation
@testable import WebCombine

private enum Failure: Error, Equatable { case offline }

@MainActor @Suite struct ResultPublisherTests {
    @Test func aSuccessPublishesItsValueAndFinishes() {
        var values: [Int] = []
        var finished = false
        let success: Result<Int, Failure> = .success(7)
        let subscription = success.publisher.map { $0 * 2 }.sink(receiveCompletion: { completion in
            if case .finished = completion { finished = true }
        }, receiveValue: { values.append($0) })
        #expect(values == [14] && finished)
        subscription.cancel()
    }

    @Test func aFailureFailsWithItsError() {
        var values: [Int] = []
        var failure: Failure?
        let subscription = Result<Int, Failure>.Publisher(.offline).sink(receiveCompletion: { completion in
            if case .failure(let error) = completion { failure = error }
        }, receiveValue: { values.append($0) })
        #expect(values.isEmpty && failure == .offline)
        subscription.cancel()
        #expect(Result<Int, Failure>.Publisher(3).result == .success(3))
    }
}
#endif
