// Built in the Swift 5 language mode, as OldOS is: a model with no actor of its own that makes a
// player and reads a web view, as OldOS's YouTube player model and Safari store do. Over Apple's
// frameworks these calls warn (their isolation comes from Objective-C, so it is pre-concurrency);
// `AVPlayer` and `WKWebView` are `@preconcurrency` here so they warn too, rather than fail.
import AVFoundation
import WebKit

public final class NonisolatedPlayerModel {
    public var player = AVPlayer()

    public init() {}

    public var isPlaying: Bool { player.timeControlStatus == .playing }

    public func restart() {
        player.seek(to: CMTime.zero)
        player.play()
    }

    public func address(of webView: WKWebView) -> String {
        webView.url?.absoluteString ?? ""
    }
}
