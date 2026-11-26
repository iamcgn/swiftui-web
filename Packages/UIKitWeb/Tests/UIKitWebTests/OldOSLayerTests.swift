// OldOS's keyboard: a view's layer has the view as its delegate, a window's layer renders into
// an image context for the magnifier, and legacy buttons keep their image-adjusting flags.
import Testing
import UIKit
@testable import UIKitWebCore

@Suite @MainActor struct OldOSLayerTests {
    @Test func layerDelegateIsTheView() {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        #expect(view.layer.delegate === view)
        #expect(CALayer().delegate == nil)
    }

    @Test func layerRendersIntoAContext() {
        let view = UIView(frame: CGRect(x: 40, y: 30, width: 20, height: 10))
        view.backgroundColor = .red
        let image = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 10)).image { context in
            view.layer.render(in: context.cgContext)
        }
        #expect(!(image.drawing?.commands.isEmpty ?? true))
    }

    @Test func legacyButtonFlags() {
        let button = UIButton(type: .custom)
        #expect(button.adjustsImageWhenHighlighted && button.adjustsImageWhenDisabled)
        button.adjustsImageWhenHighlighted = false
        #expect(!button.adjustsImageWhenHighlighted)
    }
}
