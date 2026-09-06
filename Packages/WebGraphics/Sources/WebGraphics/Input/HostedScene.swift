// The seam between a host (a canvas in a page, an AppKit window, a headless driver) and what it
// shows (a SwiftUI runtime, a UIKit window scene; decision 0014). The host owns the frame
// loop, the pixels and the platform's input and accessibility; the scene owns layout, painting
// into a display list, and what the input means.

/// What a host drives: installs its services, asks for frames, forwards input, and mirrors the
/// semantics tree into the platform's accessibility and text-input facilities.
@MainActor
public protocol HostedScene: AnyObject {
    // MARK: What the host installs

    /// Measures and breaks text. Installed before the first layout.
    var textEngine: any TextEngine { get set }
    /// The app's asset catalogs (images and colours by name).
    var assetCatalog: AssetCatalog { get set }
    /// The host's image fetcher for URLs (`_ImageLoading`).
    var imageLoader: (any _ImageLoading)? { get set }
    /// The system appearance, now and whenever it changes.
    var hostColorScheme: ColorScheme { get set }
    /// Writes text to the system clipboard, when the host may.
    var clipboardWriter: ((String) -> Void)? { get set }
    /// Called when the scene needs a frame without the host having asked for one (a state
    /// change, a layout request); the host coalesces calls into its next frame.
    var onNeedsFrame: (@MainActor () -> Void)? { get set }

    // MARK: Frames

    /// Whether the scene has pending work that needs another frame.
    var needsFrame: Bool { get }
    /// Whether animations are in flight (frames keep coming while true).
    var isAnimating: Bool { get }
    /// Advances the scene's clocks by `elapsed` seconds before a frame; returns whether an
    /// animation is still running.
    func advanceFrame(elapsed: Double) -> Bool
    /// Lays the scene out into `size` (points).
    func layout(in size: CGSize)
    /// Paints the laid-out scene into a display list at `scale` pixels per point.
    func render(scale: CGFloat) -> DisplayList
    /// An image the loader was asked for has arrived (or failed).
    func imageLoadDidFinish()
    /// The title the window or document should show, if the scene sets one.
    var windowTitle: String? { get }
    /// Frames recorded by probes during the most recent layout (test bridges).
    var probeFrames: [String: CGRect] { get }

    // MARK: Input, in points from the top left

    func pointerDown(at point: CGPoint, type: PointerType, time: Double)
    func pointerMoved(to point: CGPoint, time: Double)
    func pointerLeft()
    func pointerUp(at point: CGPoint, time: Double)
    /// A secondary (right) button press: context menus.
    func secondaryPointerDown(at point: CGPoint)
    /// A wheel or trackpad scroll by `delta` points (positive moves content up and left).
    func scrollWheel(by delta: CGSize, at point: CGPoint)
    /// A key press; returns whether the scene consumed it.
    func keyDown(_ event: KeyEvent) -> Bool
    /// The CSS cursor name the pointer should show, or nil for the default.
    var pointerCursor: String? { get }

    // MARK: Semantics and text input

    /// The accessibility tree after the most recent layout.
    func semanticsTree() -> [SemanticsNode]
    func activate(semanticsIdentifier: Int)
    func adjust(semanticsIdentifier: Int, increment: Bool)
    func setValue(semanticsIdentifier: Int, value: Double)
    /// Keyboard focus moved to an element (`keyboard` tells whether a focus ring should show).
    func focus(semanticsIdentifier: Int?, keyboard: Bool)
    func blur(semanticsIdentifier: Int)
    /// The element with keyboard focus, and the text field with it (which sets both).
    var focusedIdentifier: Int? { get }
    var focusedTextFieldIdentifier: Int? { get }
    /// The host's input element for a text field changed, submitted, or changed focus.
    func textField(_ semanticsIdentifier: Int, didChange text: String)
    func textFieldDidSubmit(_ semanticsIdentifier: Int)
    func textField(_ semanticsIdentifier: Int, focused: Bool)
}
