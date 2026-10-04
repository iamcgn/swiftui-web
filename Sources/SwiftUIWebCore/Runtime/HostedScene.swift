#if os(WASI)
import WebFoundation   // never full Foundation on wasm: it links ICU (decisions 0006, 0017)
#else
import Foundation
#endif
// The runtime as the hosts see it (WebGraphics `HostedScene`, decision 0014): the canvas,
// AppKit and headless hosts drive a SwiftUI runtime and a UIKit scene through the same calls.

extension Runtime: HostedScene {
    /// The host's frame request (the scheduler's flush hook).
    public var onNeedsFrame: (@MainActor () -> Void)? {
        get { scheduler.onNeedsFlush }
        set { scheduler.onNeedsFlush = newValue }
    }

    /// Advances scroll momentum and the animation clock before a frame.
    public func advanceFrame(elapsed: Double) -> Bool {
        var animating = advanceScrollAnimations(elapsed: elapsed)
        if advanceAnimations(elapsed: elapsed) { animating = true }
        if !platformHosts.isEmpty, advancePlatformHosts(elapsed: elapsed) { animating = true }
        return animating
    }

    /// The last `navigationTitle` applied in the tree.
    public var windowTitle: String? { navigationTitle }

    /// The host's URL: delivered to the `onOpenURL` handlers.
    public func handleOpenURL(_ url: String) {
        guard let parsed = URL(string: url) else { return }
        openURL(parsed)
    }

    /// The pointer style of the deepest hovered `pointerStyle` view, as a CSS cursor name.
    public var pointerCursor: String? { pointerStyle?.css }
}
