/// What a host's loader knows about a URL.
public enum _ImageLoadState: Equatable, Sendable {
    case loading
    case loaded(pixelSize: CGSize)
    case failed
}

/// A host's image fetcher: `state(for:)` starts a load the first time a URL is asked for and
/// answers from then on; the host calls `Runtime.imageLoadDidFinish` when a load completes.
@MainActor
public protocol _ImageLoading: AnyObject {
    func state(for url: String) -> _ImageLoadState
    /// Stops a load no view needs any more (the last `AsyncImage` of the URL unmounted while
    /// it was loading); a later request starts it again.
    func cancel(_ url: String)
}

extension _ImageLoading {
    public func cancel(_ url: String) {}
}
