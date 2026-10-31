// `ImageRenderer` (Docs/coverage.md: 3 apps, sharing a chart or a card as an image): the
// content is mounted in a runtime of its own, sized to the proposal (its ideal size when the
// proposal is unspecified) and drawn; `uiImage` (SwiftUIWebUIKit) keeps the drawing as a
// UIImage recording, which an `Image`, a `ShareLink` or `pngData()` takes as any other. The
// runtime measures text with the engine and reads images from the catalog the host installed.
// Not here: `cgImage` (there is no CGImage type on the web), `render(rasterizationScale:renderer:)`
// and observing the renderer (it is no `ObservableObject`).
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif

/// An object that creates images from SwiftUI views.
@MainActor
public final class ImageRenderer<Content: View> {
    /// The view the renderer draws.
    public var content: Content
    /// The size proposed to the content; unspecified gives its ideal size.
    public var proposedSize: ProposedViewSize = .unspecified
    /// The scale of the image (the recording is drawn at any scale; this is the image's own).
    public var scale: CGFloat = 1
    /// Whether the image is opaque.
    public var isOpaque = false
    /// The working colour space and storage format.
    public var colorMode: ColorRenderingMode = .nonLinear

    /// Creates a renderer for the view.
    public init(content view: Content) {
        content = view
    }

    /// The content's drawing in points and its size: nothing when it has no size.
    package func _draw() -> (commands: [DisplayCommand], size: CGSize) {
        let runtime = Runtime()
        if let engine = Runtime.hostTextEngine { runtime.textEngine = engine }
        _ = runtime.mount(content)
        if let catalog = Runtime.hostAssetCatalog { runtime.assetCatalog = catalog }
        runtime.flushForMeasurement()
        guard let node = runtime.root.layoutChildren.first else { return ([], .zero) }
        let size = node.sizeThatFits(proposedSize)
        guard size.width > 0, size.height > 0, size.width.isFinite, size.height.isFinite else { return ([], .zero) }
        runtime.layout(in: size)
        return (runtime.render(scale: scale).commands, size)
    }
}
