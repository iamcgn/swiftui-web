// `AsyncImage` (API/AsyncImage.swift): the node asks the runtime's loader for the URL's state,
// mounts the content for that phase, and re-evaluates when the host reports a finished load.
#if os(WASI)
import FoundationEssentials
#else
import Foundation
#endif

@MainActor
package final class AsyncImageNode<Content: View>: TypedNode<AsyncImage<Content>>, _AsyncImageReloading {
    package private(set) var child: TypedNode<Content>!
    package private(set) var phase: AsyncImagePhase = .empty
    private var lastState: _ImageLoadState?

    package init(_ context: _NodeContext<AsyncImage<Content>>) {
        super.init(view: context.view, parent: context.parent, runtime: context.runtime, environment: context.environment)
        phase = currentPhase()
        child = Content._makeNode(_NodeContext(view: view.content(phase), parent: self, environment: environment))
        runtime.register(asyncImage: self)
    }

    /// The phase for the view's URL as the loader knows it now.
    private func currentPhase() -> AsyncImagePhase {
        // A nil URL stays in the empty phase (measured: SwiftUI never reports a failure for it).
        guard let url = view.url else {
            lastState = nil
            return .empty
        }
        let state = runtime.imageLoader?.state(for: url.absoluteString) ?? .loading
        lastState = state
        switch state {
        case .loading: return .empty
        case .failed: return .failure(AsyncImageLoadingError(url: url))
        case .loaded(let pixelSize):
            return .success(Image(source: .url(url.absoluteString, pixelSize: pixelSize, scale: view.scale), label: url.lastPathComponent))
        }
    }

    package func reload() {
        let before = lastState
        let phase = currentPhase()
        guard lastState != before else { return }
        self.phase = phase
        child.update(view: view.content(phase), environment: environment, force: true)
        runtime.requestLayout()
    }

    override package func update(view: AsyncImage<Content>, environment: EnvironmentValues, force: Bool) {
        let urlChanged = self.view.url != view.url
        self.view = view
        self.environment = environment
        clearNeedsUpdate()
        if urlChanged { phase = currentPhase() }
        child.update(view: view.content(phase), environment: environment, force: force || urlChanged)
    }

    override package func unmount() {
        child.unmount()
        super.unmount()
    }

    override package var structuralChildren: [ViewNode] { [child] }
    override package var layoutChildren: [ViewNode] { child.layoutChildren }
    override package var nodeDescription: String { "AsyncImage" }
}
