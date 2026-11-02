// Apple's SafariServices for the web (decision 0021, the Ember app's in-app reader):
// `SFSafariViewController`, the view controller an app presents to show a web page inside
// itself. Its view is a `WKWebView` over the page — in the browser the host's `<iframe>` at
// the view's frame, with the host's Open link over its corner for a site that refuses to be
// framed — under a bar with the dismiss button the app configured, which dismisses the
// controller (and the SwiftUI sheet around it) as Safari's does. Only the wasm SDK lacks the
// module; the Apps package links this for wasm alone.
#if os(WASI)
import WebFoundation
import SwiftUI
import WebKit

/// An object that provides a visible standard interface for browsing the web.
@preconcurrency @MainActor
open class SFSafariViewController: UIViewController {
    /// No archive to decode on the web: nil, as for an archive this class cannot read.
    public required init?(coder: NSCoder) { return nil }

    /// The configuration of a Safari view controller.
    open class Configuration {
        public var entersReaderIfAvailable = false
        public var barCollapsingEnabled = true
        public var activityButton: Any?
        public var eventAttribution: Any?
        public init() {}
    }

    /// The style of the dismiss button.
    public enum DismissButtonStyle: Int, Sendable {
        case done = 0
        case close = 1
        case cancel = 2
    }

    public let configuration: Configuration
    public private(set) var initialURL: URL
    open weak var delegate: (any SFSafariViewControllerDelegate)?
    open var preferredBarTintColor: UIColor? { didSet { bar.backgroundColor = preferredBarTintColor ?? .systemBackground } }
    open var preferredControlTintColor: UIColor? { didSet { dismissButton.setTitleColor(preferredControlTintColor ?? .systemBlue, for: .normal) } }
    open var dismissButtonStyle: DismissButtonStyle = .done { didSet { dismissButton.setTitle(dismissButtonStyle.title, for: .normal) } }

    private let bar = UIView()
    private let dismissButton = UIButton(type: .system)
    private let hostLabel = UILabel()
    private let webView: WKWebView

    public init(url URL: URL, configuration: Configuration) {
        initialURL = URL
        self.configuration = configuration
        webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
    }

    public convenience init(url URL: URL) {
        self.init(url: URL, configuration: Configuration())
    }

    open override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        bar.backgroundColor = preferredBarTintColor ?? .systemBackground
        hostLabel.text = initialURL.host ?? initialURL.absoluteString
        hostLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        hostLabel.textAlignment = .center
        hostLabel.textColor = .label
        dismissButton.setTitle(dismissButtonStyle.title, for: .normal)
        dismissButton.setTitleColor(preferredControlTintColor ?? .systemBlue, for: .normal)
        dismissButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        dismissButton.addAction(UIAction { [weak self] _ in self?.finish() }, for: .touchUpInside)
        bar.addSubview(hostLabel)
        bar.addSubview(dismissButton)
        view.addSubview(bar)
        view.addSubview(webView)
        webView.load(URLRequest(url: initialURL))
    }

    open override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let barHeight: CGFloat = 44
        let top = view.safeAreaInsets.top
        bar.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: top + barHeight)
        dismissButton.sizeToFit()
        dismissButton.frame = CGRect(x: 16, y: top + (barHeight - dismissButton.bounds.height) / 2, width: dismissButton.bounds.width, height: dismissButton.bounds.height)
        let labelInset = dismissButton.frame.maxX + 8
        hostLabel.frame = CGRect(x: labelInset, y: top, width: view.bounds.width - 2 * labelInset, height: barHeight)
        webView.frame = CGRect(x: 0, y: bar.frame.maxY, width: view.bounds.width, height: view.bounds.height - bar.frame.maxY)
    }

    /// Done: the delegate hears, then the controller dismisses — through UIKit's presenter when
    /// it has one, else through the SwiftUI presentation hosting it (Ember's reader sheet).
    private func finish() {
        delegate?.safariViewControllerDidFinish(self)
        dismiss(animated: true)
    }
}

extension SFSafariViewController.DismissButtonStyle {
    var title: String {
        switch self {
        case .done: return "Done"
        case .close: return "Close"
        case .cancel: return "Cancel"
        }
    }
}

/// Methods a delegate implements to react to the user's actions.
@preconcurrency @MainActor
public protocol SFSafariViewControllerDelegate: AnyObject {
    func safariViewControllerDidFinish(_ controller: SFSafariViewController)
    func safariViewController(_ controller: SFSafariViewController, didCompleteInitialLoad didLoadSuccessfully: Bool)
    func safariViewController(_ controller: SFSafariViewController, initialLoadDidRedirectTo URL: URL)
}

extension SFSafariViewControllerDelegate {
    public func safariViewControllerDidFinish(_ controller: SFSafariViewController) {}
    public func safariViewController(_ controller: SFSafariViewController, didCompleteInitialLoad didLoadSuccessfully: Bool) {}
    public func safariViewController(_ controller: SFSafariViewController, initialLoadDidRedirectTo URL: URL) {}
}
#endif
