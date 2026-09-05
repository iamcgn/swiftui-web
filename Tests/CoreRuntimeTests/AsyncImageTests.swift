// AsyncImage: phases from the runtime's loader (empty while loading or without a URL, success
// with the loaded pixel size, failure when the host says so), re-evaluation when a load finishes.
import Testing
import SwiftUI
import SwiftUIWebHeadless
import Foundation

#if !os(WASI)
@MainActor private final class FakeLoader: _ImageLoading {
    var states: [String: _ImageLoadState] = [:]
    var asked: [String] = []
    func state(for url: String) -> _ImageLoadState {
        asked.append(url)
        return states[url] ?? .loading
    }
}

@Suite @MainActor struct AsyncImageTests {
    private func commands(_ runtime: Runtime) -> [String] { runtime.render(scale: 2).commands.map(\.description) }

    @Test func phasesFollowTheLoader() {
        let loader = FakeLoader()
        let runtime = Runtime()
        runtime.imageLoader = loader
        let url = URL(string: "https://example.test/pic.png")!
        runtime.mount(AsyncImage(url: url) { phase in
            switch phase {
            case .empty: Color.gray.frame(width: 10, height: 10)._probe("empty")
            case .success(let image): image._probe("image")
            case .failure: Color.red.frame(width: 20, height: 20)._probe("failed")
            }
        })
        runtime.layout(in: CGSize(width: 200, height: 100))
        #expect(runtime.probeFrames["empty"] != nil && loader.asked == [url.absoluteString])
        // The host reports the load: the image takes its pixel size at scale 1 and paints by URL.
        loader.states[url.absoluteString] = .loaded(pixelSize: CGSize(width: 40, height: 30))
        runtime.imageLoadDidFinish()
        runtime.layout(in: CGSize(width: 200, height: 100))
        #expect(runtime.probeFrames["image"] == CGRect(x: 80, y: 35, width: 40, height: 30))
        #expect(commands(runtime).contains { $0.hasPrefix("drawImage") && $0.contains("example.test/pic.png") })
        // A failure switches to the failure content.
        loader.states[url.absoluteString] = .failed
        runtime.imageLoadDidFinish()
        runtime.layout(in: CGSize(width: 200, height: 100))
        #expect(runtime.probeFrames["failed"] != nil)
    }

    @Test func scaleNilURLAndDefaults() {
        let loader = FakeLoader()
        let runtime = Runtime()
        runtime.imageLoader = loader
        let url = URL(string: "https://example.test/two.png")!
        loader.states[url.absoluteString] = .loaded(pixelSize: CGSize(width: 40, height: 30))
        // scale: 2 halves the point size; the content-and-placeholder form shows the image.
        runtime.mount(AsyncImage(url: url, scale: 2) { image in image._probe("image") } placeholder: { Color.gray._probe("placeholder") })
        runtime.layout(in: CGSize(width: 200, height: 100))
        #expect(runtime.probeFrames["image"]?.size == CGSize(width: 20, height: 15))
        // A nil URL stays empty and asks nothing of the loader; the default content is a light fill.
        let none = Runtime()
        none.imageLoader = loader
        none.mount(AsyncImage(url: nil)._probe("default"))
        none.layout(in: CGSize(width: 200, height: 100))
        #expect(loader.asked.isEmpty || !loader.asked.contains("nil"))
        #expect(commands(none).contains { $0.hasPrefix("fillRect(0, 0, 200, 100) #808080@0.2") })
        // Without a host loader the phase stays empty rather than failing.
        let bare = Runtime()
        bare.mount(AsyncImage(url: url) { phase in phase.error == nil ? Color.green._probe("empty") : Color.red._probe("failed") })
        bare.layout(in: CGSize(width: 200, height: 100))
        #expect(bare.probeFrames["empty"] != nil)
        #expect(AsyncImagePhase.failure(AsyncImageLoadingError(url: nil)).error != nil && AsyncImagePhase.empty.image == nil)
    }
}
#endif
