// `VideoPlayer` (sw-frameworks): the host's `<video>` element over a painted black stand-in
// with a play glyph (what goldens and hosts without elements show). Playback state comes
// from the `AVPlayer`; the stand-in and the element follow it every frame.
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif
import SwiftUI
@_exported import AVFoundation

/// A view that displays content from a player and a native user interface to control playback.
public struct VideoPlayer<VideoOverlay: View>: View {
    let player: AVPlayer?
    let overlay: VideoOverlay

    public init(player: AVPlayer?, @ViewBuilder videoOverlay: () -> VideoOverlay) {
        self.player = player
        overlay = videoOverlay()
    }

    public var body: some View {
        ZStack {
            Color.black
            _PlayGlyph()
            if let player, let item = player.currentItem {
                _HostElementAnchor(kind: .video(url: item.url.absoluteString, playing: player.rate != 0, muted: player.isMuted, loops: player.loops,
                                                controls: player.showsControls, rate: Double(player.rate)), identity: ObjectIdentifier(player))
            }
            overlay
        }
        .clipped()
    }
}

extension VideoPlayer where VideoOverlay == EmptyView {
    public init(player: AVPlayer?) {
        self.init(player: player) { EmptyView() }
    }
}

/// The stand-in's play triangle: 44 pt, white at 90 %, centred.
struct _PlayGlyph: View {
    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: 6, y: 0))
            path.addLine(to: CGPoint(x: 44, y: 22))
            path.addLine(to: CGPoint(x: 6, y: 44))
            path.closeSubpath()
        }
        .fill(Color.white.opacity(0.9))
        .frame(width: 44, height: 44)
    }
}

/// The player view controller's SwiftUI stand-in is the same view.
public typealias AVPlayerView = VideoPlayer<EmptyView>
