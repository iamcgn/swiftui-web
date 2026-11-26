// `AVPlayerLayer`: a player's picture where the layer is, as the host's `<video>` element
// (`VideoPlayer`'s element, without its controls). OldOS's photo viewer and Mlem's NukeVideo
// make it a view's `layerClass`; the SwiftUI hosting tree shows the element in the view's frame
// (`_UIHostElementProviding`), and the layer asks for a repaint whenever the player's state
// that the element follows changes (the player is `@Observable`).
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif
#if canImport(CoreGraphics) && !os(WASI)
import CoreGraphics
#endif
import Observation
import UIKitWebCore

/// A layer that shows a player's video.
open class AVPlayerLayer: CALayer, _UIHostElementProviding {
    private var shown: AVPlayer?
    /// The player whose current item the layer shows.
    open var player: AVPlayer? {
        get { shown }
        set {
            shown = newValue
            follow()
            setNeedsDisplay()
        }
    }
    /// How the picture fills the layer (the element's `object-fit`).
    open var videoGravity: AVLayerVideoGravity = .resizeAspect { didSet { setNeedsDisplay() } }
    /// Whether there is a picture to show: the player has an item.
    open var isReadyForDisplay: Bool { shown?.currentItem != nil }
    /// The picture's rectangle in the layer: its bounds, as the picture's size isn't known here.
    open var videoRect: CGRect { bounds }
    /// Accepted for the frames the layer would hand out (the element draws them).
    open var pixelBufferAttributes: [String: Any]?

    public required init() { super.init() }
    public override init(layer: Any) {
        super.init(layer: layer)
        if let other = layer as? AVPlayerLayer {
            videoGravity = other.videoGravity
            player = other.player
        }
    }

    public convenience init(player: AVPlayer?) {
        self.init()
        self.player = player
    }

    /// Watches what the element follows, asking for a repaint when it changes (once per change,
    /// then again for the next one, while the layer still shows that player).
    private func follow() {
        guard let watched = shown else { return }
        withObservationTracking {
            _ = self._hostElementKind
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.shown === watched else { return }
                self.setNeedsDisplay()
                self.follow()
            }
        }
    }

    public var _hostElementKind: HostElement.Kind? {
        guard let player = shown, let item = player.currentItem else { return nil }
        return .video(url: item.url.absoluteString, playing: player.rate != 0, muted: player.isMuted, loops: player.loops,
                      controls: false, rate: Double(player.rate), seek: item.currentTime().seconds, seeks: item.seeks,
                      gravity: videoGravity.rawValue)
    }
}
