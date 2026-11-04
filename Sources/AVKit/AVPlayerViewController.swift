// AVPlayerViewController for UIKit code and `UIViewControllerRepresentable` wrappers: its view
// hosts a `VideoPlayer` for the controller's player, so playback is the host's `<video>` element
// as in SwiftUI. Picture in picture and full-screen presentation are accepted and not shown.
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif
import SwiftUI

/// How a video fills the bounds of the view that shows it.
public struct AVLayerVideoGravity: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let resizeAspect = AVLayerVideoGravity(rawValue: "AVLayerVideoGravityResizeAspect")
    public static let resizeAspectFill = AVLayerVideoGravity(rawValue: "AVLayerVideoGravityResizeAspectFill")
    public static let resize = AVLayerVideoGravity(rawValue: "AVLayerVideoGravityResize")
}

/// Methods a player view controller calls on its delegate; each has a do-nothing default.
@MainActor
public protocol AVPlayerViewControllerDelegate: AnyObject {
    func playerViewControllerWillStartPictureInPicture(_ playerViewController: AVPlayerViewController)
    func playerViewControllerDidStopPictureInPicture(_ playerViewController: AVPlayerViewController)
}

extension AVPlayerViewControllerDelegate {
    public func playerViewControllerWillStartPictureInPicture(_ playerViewController: AVPlayerViewController) {}
    public func playerViewControllerDidStopPictureInPicture(_ playerViewController: AVPlayerViewController) {}
}

/// A view controller that displays content from a player and presents a native user interface
/// to control playback.
@MainActor
open class AVPlayerViewController: UIViewController {
    /// No archive to decode on the web: nil, as for an archive this class cannot read.
    public required init?(coder: NSCoder) { return nil }

    public override init(nibName: String? = nil, bundle: Any? = nil) {
        super.init(nibName: nibName, bundle: bundle)
    }

    open var player: AVPlayer? {
        didSet { applyPlayer() }
    }
    open var showsPlaybackControls = true {
        didSet { applyPlayer() }
    }
    open var videoGravity: AVLayerVideoGravity = .resizeAspect
    open var allowsPictureInPicturePlayback = true
    open var canStartPictureInPictureAutomaticallyFromInline = false
    open var entersFullScreenWhenPlaybackBegins = false
    open var exitsFullScreenWhenPlaybackEnds = false
    open var updatesNowPlayingInfoCenter = true
    open var showsTimecodes = false
    open var requiresLinearPlayback = false
    open weak var delegate: AVPlayerViewControllerDelegate?
    /// Overlay views are kept and not drawn over the video yet.
    open private(set) lazy var contentOverlayView: UIView? = UIView(frame: .zero)
    open var isReadyForDisplay: Bool { player?.currentItem != nil }

    private var hosting: UIHostingController<AnyView>?

    override open func viewDidLoad() {
        super.viewDidLoad()
        let hosting = UIHostingController(rootView: content)
        addChild(hosting)
        hosting.view.frame = view.bounds
        hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(hosting.view)
        hosting.didMove(toParent: self)
        self.hosting = hosting
    }

    private var content: AnyView {
        if let player { AnyView(VideoPlayer(player: player)) } else { AnyView(Color.black) }
    }

    private func applyPlayer() {
        player?.showsControls = showsPlaybackControls
        hosting?.rootView = content
    }
}
