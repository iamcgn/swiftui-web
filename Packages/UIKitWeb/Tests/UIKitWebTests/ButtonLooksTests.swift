// UIButton looks (uk-button): custom titles, image placements, subtitles, the button sizes,
// the pressed and disabled looks and configuration update handlers. Sizes against the
// simulator are in UIKitGoldenFrameTests (uikit/button/looks).
import Testing
import UIKit
@testable import UIKitWebCore

@Suite @MainActor struct ButtonLooksTests {
    private func scene() -> UIKitScene {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        scene.configureScreen(size: CGSize(width: 320, height: 400), scale: 2)
        scene.textEngine = try! Goldens.textEngine()
        return scene
    }

    @Test func customAndSystemButtonsSizeToTheirTitles() {
        _ = scene()
        let custom = UIButton(type: .custom)
        custom.setTitle("Custom", for: .normal)
        #expect(custom.titleLabel?.font.pointSize == 18)
        #expect(custom.intrinsicContentSize == CGSize(width: 63, height: 34))
        let heart = UIButton(type: .system)
        heart.setImage(UIImage(systemName: "heart"), for: .normal)
        heart.setTitle("Heart", for: .normal)
        heart.sizeToFit()
        #expect(heart.frame.size == CGSize(width: 65.5, height: 23.5))
        heart.layoutSubviews()
        #expect(heart.imageView?.frame.minX == 2 + 0.75 && heart.titleLabel?.frame.minX == 27)
    }

    @Test func imagePlacementsAndSubtitles() {
        _ = scene()
        var configuration = UIButton.Configuration.gray()
        configuration.title = "Star"
        configuration.image = UIImage(systemName: "star")
        configuration.imagePadding = 6
        let leading = UIButton(configuration: configuration)
        leading.sizeToFit()
        leading.layoutSubviews()
        #expect(leading.frame.size == CGSize(width: 89.5, height: 40.5))
        #expect(leading.imageView!.frame.minX < leading.titleLabel!.frame.minX)
        configuration.imagePlacement = .trailing
        let trailing = UIButton(configuration: configuration)
        trailing.sizeToFit()
        trailing.layoutSubviews()
        #expect(trailing.frame.size == CGSize(width: 89.5, height: 40.5) && trailing.imageView!.frame.minX > trailing.titleLabel!.frame.maxX)
        configuration.imagePlacement = .top
        let top = UIButton(configuration: configuration)
        top.sizeToFit()
        top.layoutSubviews()
        #expect(top.frame.size == CGSize(width: 55.5, height: 66.5) && top.imageView!.frame.maxY <= top.titleLabel!.frame.minY)
        configuration.imagePlacement = .bottom
        let bottom = UIButton(configuration: configuration)
        bottom.sizeToFit()
        bottom.layoutSubviews()
        #expect(bottom.imageView!.frame.minY >= bottom.titleLabel!.frame.maxY)
        // A subtitle in the footnote under a leading-aligned title.
        var filled = UIButton.Configuration.filled()
        filled.title = "Title"
        filled.subtitle = "Subtitle"
        let subtitled = UIButton(configuration: filled)
        subtitled.sizeToFit()
        subtitled.layoutSubviews()
        #expect(subtitled.frame.size == CGSize(width: 71, height: 62.5))
        #expect(subtitled.titleLabel?.frame.minX == 12 && subtitled.subtitleLabel.frame.minX == 12)
        #expect(subtitled.subtitleLabel.font.pointSize == 13 && subtitled.subtitleLabel.text == "Subtitle")
    }

    @Test func buttonSizesChangeFontsAndInsets() {
        _ = scene()
        func button(_ size: UIButton.Configuration.Size, _ title: String) -> UIButton {
            var configuration = UIButton.Configuration.gray()
            configuration.title = title
            configuration.buttonSize = size
            let button = UIButton(configuration: configuration)
            button.sizeToFit()
            return button
        }
        #expect(button(.mini, "Mini").frame.size == CGSize(width: 48.5, height: 33))
        #expect(button(.small, "Small").frame.size == CGSize(width: 57.5, height: 33))
        #expect(button(.medium, "Small").frame.size == CGSize(width: 65.5, height: 40.5))
        #expect(button(.large, "Large").frame.size == CGSize(width: 83.5, height: 56.5))
        #expect(button(.small, "Small").titleLabel?.font.pointSize == 15 && button(.large, "Large").titleLabel?.font.pointSize == 17)
    }

    @Test func pressedDisabledAndUpdateHandlers() {
        _ = scene()
        var configuration = UIButton.Configuration.filled()
        configuration.title = "Go"
        let button = UIButton(configuration: configuration)
        var updates: [String] = []
        button.configurationUpdateHandler = { button in updates.append(button.isHighlighted ? "pressed" : button.isEnabled ? "normal" : "disabled") }
        #expect(updates == ["normal"])
        button.isHighlighted = true
        #expect(updates.last == "pressed" && button.currentTitleColor == .white)
        button.isHighlighted = false
        button.isEnabled = false
        #expect(updates.last == "disabled" && button.currentTitleColor == .tertiaryLabel)
        button.automaticallyUpdatesConfiguration = false
        button.isEnabled = true
        #expect(updates.last == "disabled")
        button.setNeedsUpdateConfiguration()
        #expect(updates.last == "normal")
        // The gray style's title is the label colour; a base foreground colour wins.
        var gray = UIButton.Configuration.gray()
        gray.title = "Gray"
        #expect(UIButton(configuration: gray).currentTitleColor == .label)
        gray.baseForegroundColor = .systemRed
        #expect(UIButton(configuration: gray).currentTitleColor == .systemRed)
        #expect(gray.updated(for: button).title == "Gray")
    }
}
