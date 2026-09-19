// UIActivityIndicatorView (Controls/MoreControls.swift): the spokes' pattern turns on the
// scene's clock while animating, a step every 1/8 s, and stopping hides the view.
import Testing
import UIKit
@testable import UIKitWebCore

@Suite @MainActor struct ActivityIndicatorTests {
    private func spokes() -> [String] {
        UIKitScene.shared.layout(in: CGSize(width: 100, height: 100))
        return UIKitScene.shared.render(scale: 2, background: false).commands.map(\.description).filter { $0.hasPrefix("strokePath") }
    }

    @Test func spinsWhileAnimatingAndHidesWhenStopped() {
        UIKitScene.shared.removeAllWindows()
        UIKitScene.shared.configureScreen(size: CGSize(width: 100, height: 100), scale: 2)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        window.makeKeyAndVisible()
        let spinner = UIActivityIndicatorView(style: .medium)
        window.addSubview(spinner)
        #expect(spinner.isHidden)
        #expect(spokes().isEmpty)
        spinner.startAnimating()
        #expect(!spinner.isHidden && UIKitScene.shared.isAnimating)
        let start = spokes()
        #expect(start.count == 8)
        // An eighth of a second turns the pattern by a spoke; a whole second brings it back.
        #expect(UIKitScene.shared.advanceFrame(elapsed: 0.125))
        let turned = spokes()
        #expect(turned != start && Set(turned) == Set(start))
        #expect(UIKitScene.shared.advanceFrame(elapsed: 0.875))
        #expect(spokes() == start)
        spinner.stopAnimating()
        #expect(spinner.isHidden && !UIKitScene.shared.isAnimating)
        #expect(!UIKitScene.shared.advanceFrame(elapsed: 0.125))
        #expect(spokes().isEmpty)
    }
}
