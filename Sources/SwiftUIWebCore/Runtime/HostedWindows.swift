// Real windows (pf-native-text): a host that can open windows of its own (the native macOS
// host) shows each `.window` presentation in one — the runtime lays the presentation out in
// its virtual root space, paints its content for the host's window through
// `render(hostedWindow:scale:)`, takes pointer events the host converts into root
// coordinates, and hears of the window closing or resizing. Hosts without windows (the
// browser, headless) keep the painted windows inside the main view.

/// A window presentation as the host shows it.
public struct _HostedWindow: Sendable, Equatable {
    public let id: Int
    public let title: String?
    /// The content's size (the real window's own title bar is above it).
    public let contentSize: CGSize
    /// Where the content sits in the runtime's root space: what the host adds to a point in
    /// its window to reach the runtime.
    public let contentOrigin: CGPoint
    public let resizable: Bool
    public let hidesTitleBar: Bool
}

/// What the native host does with the window presentations: opens, retitles, resizes and
/// closes real windows to match the list it is given after every layout.
@MainActor
public protocol _RealWindowHosting: AnyObject {
    func syncWindows(_ windows: [_HostedWindow])
}

extension Runtime {
    /// The host that shows window presentations as windows of its own (SwiftUIWebNative
    /// installs one); nil keeps them painted inside the main view.
    public var realWindowHost: (any _RealWindowHosting)? {
        get { realWindowHostStorage }
        set { realWindowHostStorage = newValue; requestLayout() }
    }

    /// The window presentations as the host should show them, in their order.
    public func hostedWindows() -> [_HostedWindow] {
        presentations.compactMap { presentation in
            guard presentation.isHostedWindow, case .window(let title, _) = presentation.kind else { return nil }
            let bar = presentation.titleBarHeight
            return _HostedWindow(id: presentation.hostedWindowIdentifier, title: title ?? windowTitle,
                                 contentSize: CGSize(width: presentation.panel.width, height: presentation.panel.height - bar),
                                 contentOrigin: CGPoint(x: presentation.panel.minX, y: presentation.panel.minY + bar),
                                 resizable: presentation.windowOptions.resizable, hidesTitleBar: presentation.windowOptions.hidesTitleBar)
        }
    }

    /// The content of the hosted window `id`, painted with its content origin at zero.
    public func render(hostedWindow id: Int, scale: CGFloat) -> DisplayList {
        var list = DisplayList()
        guard let presentation = presentations.first(where: { $0.hostedWindowIdentifier == id }), presentation.isHostedWindow else { return list }
        let previousMetrics = PlatformMetrics.select(rootEnvironment.platformProfile)
        defer { PlatformMetrics.current = previousMetrics }
        let origin = CGPoint(x: -presentation.panel.minX, y: -(presentation.panel.minY + presentation.titleBarHeight))
        presentation.paintHostedWindowContent(into: &list, context: PaintContext(origin: origin, scale: scale))
        paintFocusRing(into: &list, context: PaintContext(origin: origin, scale: scale))
        return list
    }

    /// The host's window for the presentation closed: the presentation is dismissed.
    public func hostedWindowDidClose(_ id: Int) {
        guard let presentation = presentations.first(where: { $0.hostedWindowIdentifier == id }) else { return }
        presentation.dismiss()
        requestLayout()
    }

    /// The host's window was resized to `size` (its content): the presentation follows.
    public func hostedWindow(_ id: Int, didResizeTo size: CGSize) {
        guard let presentation = presentations.first(where: { $0.hostedWindowIdentifier == id }) else { return }
        guard presentation.windowSize != size else { return }
        presentation.windowSize = size
        requestLayout()
    }

    /// The host's window came to the front: its presentation is the topmost (it takes keys).
    public func hostedWindowDidBecomeKey(_ id: Int) {
        guard let index = presentations.firstIndex(where: { $0.hostedWindowIdentifier == id }), index != presentations.count - 1 else { return }
        let presentation = presentations.remove(at: index)
        presentations.append(presentation)
        setNeedsDisplay()
    }

    /// After a layout: the host's windows follow the presentations.
    package func syncHostedWindows() {
        guard let host = realWindowHost else { return }
        host.syncWindows(hostedWindows())
    }
}

extension PresentationNode {
    /// The identity the host keeps its window under.
    package var hostedWindowIdentifier: Int { ObjectIdentifier(self).hashValue }
}
