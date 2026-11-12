// UILabel's `font` and `textColor` are implicitly unwrapped, as UIKit declares them: an app may
// assign an optional (CVCalendar's `delegate?.dayLabelColor?(...) ?? color`), and nil sets the
// default.
import Testing
import UIKit
@testable import UIKitWebCore

@Suite @MainActor struct LabelOptionalStyleTests {
    @Test func optionalsAssignAndNilRestoresTheDefaults() {
        let label = UILabel()
        let custom: UIColor? = .red
        label.textColor = custom
        #expect(label.textColor == .red)
        label.textColor = nil
        #expect(label.textColor == .label)

        let font: UIFont? = .boldSystemFont(ofSize: 20)
        label.font = font
        #expect(label.font.pointSize == 20)
        label.font = nil
        #expect(label.font == .systemFont(ofSize: 17))
    }

    @Test func aChangedFontStillMeasuresAgain() {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        scene.configureScreen(size: CGSize(width: 320, height: 400), scale: 2)
        scene.textEngine = try! Goldens.textEngine()
        let label = UILabel()
        label.text = "Hello"
        let small = label.intrinsicContentSize
        label.font = .systemFont(ofSize: 34)
        #expect(label.intrinsicContentSize.height > small.height)
    }
}
