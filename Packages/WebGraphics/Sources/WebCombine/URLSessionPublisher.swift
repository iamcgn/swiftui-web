// `URLSession.dataTaskPublisher(for:)`: a request's data and response as one value, or its
// `URLError`. The request starts when a subscriber arrives and is cancelled with the
// subscription, as Combine's does. Apple's Foundation declares its own with Combine.
#if !canImport(Darwin)
import WebFoundation
#if canImport(FoundationNetworking)
import FoundationNetworking   // Linux keeps URLSession here
#endif

extension URLSession {
    /// A publisher that loads the request and delivers its data and response.
    public struct DataTaskPublisher: Publisher {
        public typealias Output = (data: Data, response: URLResponse)
        public typealias Failure = URLError

        public let request: URLRequest
        public let session: URLSession

        public init(request: URLRequest, session: URLSession) {
            self.request = request
            self.session = session
        }

        @MainActor public func _subscribe(_ receive: @escaping @MainActor (Output) -> Void,
                                          _ complete: @escaping @MainActor (Subscribers.Completion<URLError>) -> Void) -> AnyCancellable {
            let session = self.session
            let request = self.request
            let task = Task { @MainActor in
                do {
                    let (data, response) = try await session.data(for: request)
                    guard !Task.isCancelled else { return }
                    receive((data: data, response: response))
                    complete(.finished)
                } catch {
                    guard !Task.isCancelled else { return }
                    complete(.failure(error as? URLError ?? URLError(.unknown)))
                }
            }
            return AnyCancellable { task.cancel() }
        }
    }

    public func dataTaskPublisher(for request: URLRequest) -> DataTaskPublisher {
        DataTaskPublisher(request: request, session: self)
    }

    public func dataTaskPublisher(for url: URL) -> DataTaskPublisher {
        DataTaskPublisher(request: URLRequest(url: url), session: self)
    }
}
#endif
