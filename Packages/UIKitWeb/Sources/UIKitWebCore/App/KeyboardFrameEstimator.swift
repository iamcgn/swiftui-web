// Where the browser's on-screen keyboard is (decision 0021, uk-app-delegate-adaptor: the
// Countries app's SystemEventsHandler reads `keyboardFrameEndUserInfoKey`). A browser never
// says "the keyboard is up"; what it exposes is the visual viewport — the part of the layout
// viewport the user can see — which the keyboard shrinks from the bottom on phones (iOS Safari
// always; Chrome on Android with `interactive-widget=overlays-content`, and otherwise it
// shrinks the layout viewport itself, so there is nothing over the page to report). The
// estimate takes the reading only in the one state that is the keyboard's:
//
// - a text input has the focus (`document.activeElement` is the canvas's input or textarea):
//   without one, nothing that shrinks the viewport is a keyboard — the URL bar, a find bar;
// - the page is not pinch-zoomed (`visualViewport.scale` is 1): zoom shrinks the visual
//   viewport too, from every side;
// - the part of the window below the visual viewport is at least `minimumHeight` (a keyboard
//   is never a few points tall; the URL bar's collapse is, and is not it);
// - an ordinary resize moves the window and the visual viewport together: the gap stays zero.
//
// The frame is in the scene's point space (the screen): the band at the bottom the keyboard
// covers. `nil` means no keyboard — the notification path then posts will-hide.
import WebFoundation

/// One reading of the browser's viewports, in CSS pixels (the scene's points).
public struct _ViewportReading: Equatable, Sendable {
    /// `window.innerHeight`: the layout viewport's height.
    public var windowHeight: CGFloat
    /// `visualViewport.height`, `.offsetTop` and `.scale`.
    public var visualHeight: CGFloat
    public var visualOffsetTop: CGFloat
    public var scale: CGFloat
    /// Whether `document.activeElement` is a text input (or textarea).
    public var textInputFocused: Bool
    public init(windowHeight: CGFloat, visualHeight: CGFloat, visualOffsetTop: CGFloat = 0, scale: CGFloat = 1, textInputFocused: Bool) {
        self.windowHeight = windowHeight
        self.visualHeight = visualHeight
        self.visualOffsetTop = visualOffsetTop
        self.scale = scale
        self.textInputFocused = textInputFocused
    }
}

public enum _KeyboardFrameEstimator {
    /// Below this the gap is the browser's own chrome moving, not a keyboard.
    public static let minimumHeight: CGFloat = 80

    /// The keyboard's frame over a screen of `screenSize`, or nil.
    public static func frame(for reading: _ViewportReading, screenSize: CGSize) -> CGRect? {
        guard reading.textInputFocused else { return nil }
        guard abs(reading.scale - 1) < 0.01 else { return nil }
        let occluded = (reading.windowHeight - (reading.visualHeight + reading.visualOffsetTop)).rounded()
        guard occluded >= minimumHeight else { return nil }
        // The screen is the scene's size; the keyboard covers its bottom band. A window
        // taller than the screen (a scrolled page) keeps the band at the screen's bottom.
        let height = min(occluded, screenSize.height)
        return CGRect(x: 0, y: screenSize.height - height, width: screenSize.width, height: height)
    }
}
