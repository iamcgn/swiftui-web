// The keyboard frame estimated from the browser's viewports (uk-app-delegate-adaptor): only a
// focused text input with the visual viewport shortened from the bottom at scale 1 is the
// keyboard; a plain resize, a pinch zoom, the URL bar's few points, or a shrink without focus
// is not. These readings are synthetic (what the host would read from `window` and
// `visualViewport`); the phone's own keyboard is a separate piece of evidence (decision 0021).
import Testing
import UIKitWebCore
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif

@Suite struct KeyboardFrameTests {
    let screen = CGSize(width: 390, height: 844)

    @Test func keyboardIsTheBandBelowTheVisualViewportWhileATextInputHasFocus() {
        // iOS Safari with the keyboard up: the window keeps its height, the visual viewport
        // loses the keyboard's.
        let up = _ViewportReading(windowHeight: 844, visualHeight: 844 - 336, textInputFocused: true)
        #expect(_KeyboardFrameEstimator.frame(for: up, screenSize: screen) == CGRect(x: 0, y: 844 - 336, width: 390, height: 336))
        // Scrolled while editing: the visual viewport's top moved down; the band is what is below it.
        let scrolled = _ViewportReading(windowHeight: 844, visualHeight: 844 - 336 - 40, visualOffsetTop: 40, textInputFocused: true)
        #expect(_KeyboardFrameEstimator.frame(for: scrolled, screenSize: screen) == CGRect(x: 0, y: 844 - 336, width: 390, height: 336))
        // Down again: the viewports agree, no frame.
        let down = _ViewportReading(windowHeight: 844, visualHeight: 844, textInputFocused: true)
        #expect(_KeyboardFrameEstimator.frame(for: down, screenSize: screen) == nil)
    }

    @Test func nothingWithoutAFocusedTextInput() {
        // The same shortened viewport with no input focused (a find bar, a browser sheet): not a keyboard.
        let shortened = _ViewportReading(windowHeight: 844, visualHeight: 500, textInputFocused: false)
        #expect(_KeyboardFrameEstimator.frame(for: shortened, screenSize: screen) == nil)
    }

    @Test func aPinchZoomIsNotTheKeyboard() {
        // Zoomed 2×: the visual viewport is half the window on both axes, even with a focused input.
        let zoomed = _ViewportReading(windowHeight: 844, visualHeight: 422, scale: 2, textInputFocused: true)
        #expect(_KeyboardFrameEstimator.frame(for: zoomed, screenSize: screen) == nil)
    }

    @Test func anOrdinaryResizeMovesBothViewportsTogether() {
        // A desktop window resized while a field is focused: window and visual viewport agree.
        let resized = _ViewportReading(windowHeight: 600, visualHeight: 600, textInputFocused: true)
        #expect(_KeyboardFrameEstimator.frame(for: resized, screenSize: CGSize(width: 800, height: 600)) == nil)
        // Chrome Android's default (the layout viewport itself shrinks for the keyboard):
        // the same agreement — there is nothing over the page to report, the page got smaller.
        let layoutResized = _ViewportReading(windowHeight: 500, visualHeight: 500, textInputFocused: true)
        #expect(_KeyboardFrameEstimator.frame(for: layoutResized, screenSize: CGSize(width: 390, height: 500)) == nil)
    }

    @Test func theUrlBarsFewPointsAreNotAKeyboard() {
        let chrome = _ViewportReading(windowHeight: 844, visualHeight: 844 - 50, textInputFocused: true)
        #expect(_KeyboardFrameEstimator.frame(for: chrome, screenSize: screen) == nil)
        let justEnough = _ViewportReading(windowHeight: 844, visualHeight: 844 - _KeyboardFrameEstimator.minimumHeight, textInputFocused: true)
        #expect(_KeyboardFrameEstimator.frame(for: justEnough, screenSize: screen)?.height == _KeyboardFrameEstimator.minimumHeight)
    }

    @Test func theBandNeverExceedsTheScreen() {
        // A page taller than the scene (a scrolled document host): the band stays at the screen's bottom.
        let tall = _ViewportReading(windowHeight: 2000, visualHeight: 1000, textInputFocused: true)
        #expect(_KeyboardFrameEstimator.frame(for: tall, screenSize: screen) == CGRect(x: 0, y: 0, width: 390, height: 844))
    }

    /// The whole path a host drives: a reading into `keyboardFrame`, the notifications out.
    @Test @MainActor func aHostsReadingReachesTheNotifications() {
        let scene = UIKitScene.shared
        scene.keyboardFrame = nil
        var heights: [CGFloat] = []
        let center = NotificationCenter.default
        let tokens = [UIResponder.keyboardWillShowNotification, UIResponder.keyboardWillHideNotification].map { name in
            center.addObserver(forName: name, object: nil, queue: nil) { note in
                // The Countries app's reading of the end frame's height.
                let height = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue.height ?? -1
                let signed = note.name == UIResponder.keyboardWillHideNotification ? -height : height
                MainActor.assumeIsolated { heights.append(signed) }
            }
        }
        defer { for token in tokens { center.removeObserver(token) }; scene.keyboardFrame = nil }
        let screen = UIScreen.main.bounds.size
        scene.keyboardFrame = _KeyboardFrameEstimator.frame(for: _ViewportReading(windowHeight: screen.height, visualHeight: screen.height - 300, textInputFocused: true), screenSize: screen)
        scene.keyboardFrame = _KeyboardFrameEstimator.frame(for: _ViewportReading(windowHeight: screen.height, visualHeight: screen.height - 300, textInputFocused: false), screenSize: screen)
        #expect(heights == [300, -300])
    }
}
