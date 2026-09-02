import SwiftUIWebCore

/// Drives a `Runtime` without a host: mount, lay out at a size, and record the display list.
/// Tests use it directly; the browser Tier B job compares its output with the canvas painter's.
@MainActor
public final class HeadlessRenderer {
    public let runtime: Runtime
    public var size: CGSize
    public var scale: CGFloat

    public init(size: CGSize, scale: CGFloat = 2, textEngine: (any TextEngine)? = nil, assets: AssetCatalog = .empty) {
        runtime = Runtime()
        self.size = size
        self.scale = scale
        if let textEngine { runtime.textEngine = textEngine }
        runtime.assetCatalog = assets
    }

    /// Mounts (or updates) the root view.
    public func mount<V: View>(_ view: V) {
        runtime.mount(view)
    }

    /// Applies pending state changes, lays out and paints one frame.
    @discardableResult
    public func renderFrame() -> DisplayList {
        runtime.layout(in: size)
        return runtime.render(scale: scale)
    }

    /// Frames recorded by `_probe` modifiers in the last frame.
    public var probeFrames: [String: CGRect] { runtime.probeFrames }
}
