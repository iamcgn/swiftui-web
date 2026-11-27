// UIKit members GistHub's packages call: KeyboardToolbar's custom-view bar items, toolbar
// background images and content size limits, StyledTextKit's font descriptors as keys, the
// standard font sizes and a layout manager drawing its text and backgrounds, and Kingfisher's
// image alignment insets and right-to-left mirroring.
import Testing
import UIKit
@testable import UIKitWebCore
import WebGraphics

@Suite(.serialized) @MainActor struct GistHubMembersTests {
    private func window() -> UIViewController {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        scene.textEngine = SyntheticTextEngine()
        scene.configureScreen(size: CGSize(width: 320, height: 500), scale: 2)
        let root = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 500))
        window.rootViewController = root
        window.makeKeyAndVisible()
        scene.layout(in: CGSize(width: 320, height: 500))
        return root
    }

    @Test func aCustomViewItemShowsItsViewInTheBar() throws {
        let root = window()
        let scene = UIKitScene.shared
        let tool = UIView(frame: CGRect(x: 0, y: 0, width: 30, height: 20))
        let item = UIBarButtonItem(customView: tool)
        #expect(item.customView === tool)
        let toolbar = UIToolbar(frame: CGRect(x: 0, y: 452, width: 320, height: 48))
        toolbar.items = [item, .flexibleSpace(), UIBarButtonItem(barButtonSystemItem: .add)]
        root.view.addSubview(toolbar)
        scene.layout(in: CGSize(width: 320, height: 500))
        // The view sits where a platter would start, at its own size, centred down the bar.
        let holder = try #require(tool.superview)
        #expect(holder.superview === toolbar)
        #expect(holder.frame == CGRect(x: 16, y: 0, width: 30, height: 48))
        #expect(tool.frame == CGRect(x: 0, y: 14, width: 30, height: 20))
        // Only the system item is a button; the custom view speaks for itself.
        #expect(scene.semanticsTree().filter { $0.role == .button }.map(\.label) == ["plus"])
        // Replacing the view rebuilds the bar with the new one.
        let wider = UIView(frame: CGRect(x: 0, y: 0, width: 44, height: 30))
        item.customView = wider
        scene.layout(in: CGSize(width: 320, height: 500))
        #expect(wider.superview?.frame == CGRect(x: 16, y: 0, width: 44, height: 48))
        #expect(wider.frame.minY == 9)
    }

    @Test func aCustomViewWithoutAFrameTakesItsIntrinsicSize() {
        let root = window()
        let label = UILabel()
        label.text = "Tools"
        label.font = .systemFont(ofSize: 17)
        let toolbar = UIToolbar(frame: CGRect(x: 0, y: 452, width: 320, height: 48))
        toolbar.items = [UIBarButtonItem(customView: label)]
        root.view.addSubview(toolbar)
        UIKitScene.shared.layout(in: CGSize(width: 320, height: 500))
        // Five 8.5 pt characters, centred in the bar as one item (138.75, on the pixel grid).
        #expect(label.frame.width == 42.5)
        #expect(label.superview?.frame.minX == 139)
    }

    @Test func toolbarBackgroundImagesFallBackToAnyPosition() {
        let toolbar = UIToolbar()
        let clear = UIImage()
        toolbar.setBackgroundImage(clear, forToolbarPosition: .any, barMetrics: .default)
        #expect(toolbar.backgroundImage(forToolbarPosition: .any, barMetrics: .default) === clear)
        #expect(toolbar.backgroundImage(forToolbarPosition: .bottom, barMetrics: .default) === clear)
        #expect(toolbar.backgroundImage(forToolbarPosition: .bottom, barMetrics: .compact) == nil)
        let bottom = UIImage()
        toolbar.setBackgroundImage(bottom, forToolbarPosition: .bottom, barMetrics: .default)
        #expect(toolbar.backgroundImage(forToolbarPosition: .bottom, barMetrics: .default) === bottom)
        toolbar.setShadowImage(clear, forToolbarPosition: .any)
        #expect(toolbar.shadowImage(forToolbarPosition: .top) === clear)
        #expect(UIBarPosition.topAttached.rawValue == 3)
    }

    @Test func contentSizeLimitsHoldTheSubtreesCategory() {
        let root = window()
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let child = UIView()
        container.addSubview(child)
        root.view.addSubview(container)
        root.view.traitOverrides.preferredContentSizeCategory = .accessibilityLarge
        #expect(child.traitCollection.preferredContentSizeCategory == .accessibilityLarge)
        container.maximumContentSizeCategory = .extraExtraLarge
        #expect(container.traitCollection.preferredContentSizeCategory == .extraExtraLarge)
        #expect(child.traitCollection.preferredContentSizeCategory == .extraExtraLarge)
        #expect(container.appliedContentSizeCategoryLimitsDescription.contains("maximum"))
        root.view.traitOverrides.preferredContentSizeCategory = .extraSmall
        container.minimumContentSizeCategory = .medium
        #expect(child.traitCollection.preferredContentSizeCategory == .medium)
        container.minimumContentSizeCategory = nil
        container.maximumContentSizeCategory = nil
        #expect(child.traitCollection.preferredContentSizeCategory == .extraSmall)
        #expect(container.appliedContentSizeCategoryLimitsDescription.isEmpty)
        // A button and an image view take the image-size flag.
        let button = UIButton(type: .system)
        button.adjustsImageSizeForAccessibilityContentSizeCategory = true
        let adjusting: [any UIAccessibilityContentSizeCategoryImageAdjusting] = [button, UIImageView()]
        #expect(adjusting.map { $0.adjustsImageSizeForAccessibilityContentSizeCategory } == [true, false])
    }

    @Test func standardFontSizesAndDescriptorsAsKeys() {
        #expect(UIFont.systemFontSize == 14 && UIFont.smallSystemFontSize == 12)
        #expect(UIFont.labelFontSize == 17 && UIFont.buttonFontSize == 18)
        let body = UIFont.systemFont(ofSize: 17).fontDescriptor
        let same = UIFont.systemFont(ofSize: 17).fontDescriptor
        let bigger = body.withSize(20)
        #expect(body == same && body != bigger)
        #expect(body.hashValue == same.hashValue)
        #expect(Set([body, same, bigger]).count == 2)
    }

    @Test func imagesCarryAlignmentInsetsAndMirroring() {
        let image = UIImage(drawing: UIImageDrawing(commands: [], size: CGSize(width: 10, height: 4), scale: 2))
        #expect(image.alignmentRectInsets == .zero && !image.flipsForRightToLeftLayoutDirection)
        let insets = UIEdgeInsets(top: 1, left: 2, bottom: 3, right: 4)
        let inset = image.withAlignmentRectInsets(insets)
        #expect(inset.alignmentRectInsets == insets && inset.size == image.size)
        #expect(image.alignmentRectInsets == .zero)
        let mirrored = inset.imageFlippedForRightToLeftLayoutDirection()
        #expect(mirrored.flipsForRightToLeftLayoutDirection && mirrored.alignmentRectInsets == insets)
        // Copies made from it keep both.
        let tinted = mirrored.withTintColor(.red).withRenderingMode(.alwaysTemplate)
        #expect(tinted.flipsForRightToLeftLayoutDirection && tinted.alignmentRectInsets == insets)
    }

    @Test func aLayoutManagerDrawsItsTextAndBackgrounds() throws {
        _ = window()
        let manager = NSLayoutManager()
        #expect(manager.hyphenationFactor == 0)
        manager.hyphenationFactor = 1
        let container = NSTextContainer(size: CGSize(width: 60, height: 100))
        container.lineFragmentPadding = 0
        manager.addTextContainer(container)
        let text = NSMutableAttributedString(string: "Tap here please", attributes: [.font: UIFont.systemFont(ofSize: 17)])
        text.addAttribute(.backgroundColor, value: UIColor.red, range: NSRange(location: 4, length: 4))
        let storage = NSTextStorage(attributedString: text)
        storage.addLayoutManager(manager)
        let all = NSRange(location: 0, length: storage.length)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 80))
        let image = renderer.image { _ in
            manager.drawBackground(forGlyphRange: all, at: CGPoint(x: 5, y: 7))
            manager.drawGlyphs(forGlyphRange: all, at: CGPoint(x: 5, y: 7))
        }
        let commands = try #require(image.drawing?.commands)
        // "here" (34 wide) on the second line, 20.5 down, under the text.
        let fills = commands.compactMap { command -> CGRect? in
            if case .fillPath(let path, _, _) = command { return path.boundingRect }
            if case .fillRect(let rect, _) = command { return rect }
            return nil
        }
        #expect(fills == [CGRect(x: 5, y: 27.5, width: 34, height: 20.5)])
        // Each line's text, from the container's left edge, a line apart.
        let texts = commands.compactMap { command -> (String, CGPoint)? in
            if case .drawText(let text, _, let origin, _) = command { return (text, origin) }
            return nil
        }
        #expect(texts.map { $0.0.trimmingCharacters(in: .whitespaces) } == ["Tap", "here", "please"], "\(texts)")
        #expect(texts.allSatisfy { $0.1.x == 5 })
        if texts.count == 3 {
            #expect(texts[1].1.y - texts[0].1.y == 20.5 && texts[2].1.y - texts[1].1.y == 20.5)
        }
        // Part of a line starts where its first glyph is.
        let part = renderer.image { _ in manager.drawGlyphs(forGlyphRange: NSRange(location: 6, length: 2), at: .zero) }
        let partTexts = (part.drawing?.commands ?? []).compactMap { command -> (String, CGPoint)? in
            if case .drawText(let text, _, let origin, _) = command { return (text, origin) }
            return nil
        }
        #expect(partTexts.map(\.0) == ["re"] && partTexts.first?.1.x == 17)
    }
}
