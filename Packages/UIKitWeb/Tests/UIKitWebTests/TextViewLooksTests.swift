// UITextView looks (uk-textview): attributed runs and links, detected links and tapping them,
// the painted selection, exclusion paths, the Helvetica default font, the indicator after a
// scroll. Sizes against the simulator are in UIKitGoldenFrameTests (uikit/textview/looks).
import Testing
import UIKit
@testable import UIKitWebCore

@Suite @MainActor struct TextViewLooksTests {
    private func window() -> (UIKitScene, UIViewController) {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        scene.textEngine = try! Goldens.textEngine()
        scene.configureScreen(size: CGSize(width: 320, height: 500), scale: 2)
        let root = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 500))
        window.rootViewController = root
        window.overrideUserInterfaceStyle = .light   // a dark fixture test may run in between
        window.makeKeyAndVisible()
        scene.layout(in: CGSize(width: 320, height: 500))
        return (scene, root)
    }

    private func texts(_ list: DisplayList) -> [(String, CGPoint, RGBA, CGFloat)] {
        list.commands.compactMap { command in
            if case .drawText(let text, let font, let origin, let color) = command { return (text, origin, color, font.size) } else { return nil }
        }
    }

    final class Listener: UITextViewDelegate {
        var opened: [URL] = []
        var allows = true
        var selections = 0
        func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
            opened.append(URL)
            return allows
        }
        func textViewDidChangeSelection(_ textView: UITextView) { selections += 1 }
    }

    @Test func attributedRunsKeepTheirFontsColoursAndLinks() {
        let (scene, root) = window()
        let view = UITextView(frame: CGRect(x: 16, y: 16, width: 288, height: 10))
        view.isScrollEnabled = false
        let text = NSMutableAttributedString(string: "Bold start, ", attributes: [.font: UIFont.boldSystemFont(ofSize: 17)])
        text.append(NSAttributedString(string: "regular middle, ", attributes: [.font: UIFont.systemFont(ofSize: 17)]))
        text.append(NSAttributedString(string: "red end, ", attributes: [.font: UIFont.systemFont(ofSize: 15), .foregroundColor: UIColor.systemRed]))
        text.append(NSAttributedString(string: "a link", attributes: [.font: UIFont.systemFont(ofSize: 17), .link: URL(string: "https://example.com/attributed")!]))
        view.attributedText = text
        #expect(view.text == "Bold start, regular middle, red end, a link")
        #expect(view.font?.pointSize == 17 && view.font?.weight == .semibold)
        #expect(view.runs.count == 4 && view.runs[3].link?.absoluteString == "https://example.com/attributed")
        view.frame.size.height = view.sizeThatFits(CGSize(width: 288, height: CGFloat.greatestFiniteMagnitude)).height
        #expect(view.frame.height == 57)
        root.view.addSubview(view)
        let drawn = texts(scene.render(scale: 2))
        #expect(drawn.map(\.0) == ["Bold start, ", "regular middle, ", "red end, ", "a link"])
        #expect(drawn[2].3 == 15 && drawn[2].2 == UIColor.systemRed.rgba(for: .light))
        #expect(drawn[3].2 == RGBA(r: 0, g: 136, b: 255))
        let baselines: [CGFloat] = drawn.map { $0.1.y }
        #expect(baselines.allSatisfy { $0 == 40.5 })   // one baseline for mixed runs
        // Setting plain text drops the attributes.
        view.text = "Plain"
        #expect(view.runs.count == 1 && view.runs[0].font.pointSize == 17)
    }

    @Test func detectedLinksSplitRunsAndOpenOnTap() {
        let (scene, root) = window()
        var opened: [String] = []
        scene.openURL = { opened.append($0) }
        let view = UITextView(frame: CGRect(x: 16, y: 96, width: 288, height: 60))
        view.isEditable = false
        view.dataDetectorTypes = [.link]
        view.font = .systemFont(ofSize: 17)
        view.text = "Visit https://example.com or www.apple.com today."
        #expect(view.runs.map(\.text) == ["Visit ", "https://example.com", " or ", "www.apple.com", " today."])
        #expect(view.runs[1].link?.absoluteString == "https://example.com")
        #expect(view.runs[3].link?.absoluteString == "https://www.apple.com")
        root.view.addSubview(view)
        scene.layout(in: CGSize(width: 320, height: 500))
        let listener = Listener()
        view.delegate = listener
        // "Visit " is 43 wide at 17 pt: the first link starts 48 in from the view.
        #expect(view.link(at: CGPoint(x: 60, y: 18))?.0.absoluteString == "https://example.com")
        #expect(view.link(at: CGPoint(x: 60, y: 18))?.1 == NSRange(location: 6, length: 19))
        #expect(view.link(at: CGPoint(x: 20, y: 18)) == nil)
        scene.pointerDown(at: CGPoint(x: 16 + 60, y: 96 + 18), type: .touch, time: 0)
        scene.pointerUp(at: CGPoint(x: 16 + 60, y: 96 + 18), time: 0.05)
        #expect(opened == ["https://example.com"])
        #expect(listener.opened.count == 1)
        listener.allows = false
        scene.pointerDown(at: CGPoint(x: 16 + 60, y: 96 + 18), type: .touch, time: 1)
        scene.pointerUp(at: CGPoint(x: 16 + 60, y: 96 + 18), time: 1.05)
        #expect(opened.count == 1 && listener.opened.count == 2)
        // An editable view does not detect.
        view.isEditable = true
        #expect(view.runs.count == 1)
    }

    @Test func theSelectionPaintsWhileEditing() {
        let (scene, root) = window()
        let view = UITextView(frame: CGRect(x: 16, y: 340, width: 288, height: 60))
        view.font = .systemFont(ofSize: 17)
        view.text = "Select some of this text"
        let listener = Listener()
        view.delegate = listener
        root.view.addSubview(view)
        view.selectedRange = NSRange(location: 7, length: 4)
        #expect(listener.selections == 1)
        #expect(view.selectionRects().isEmpty == false)
        var list = scene.render(scale: 2)
        #expect(!list.commands.contains { if case .fillRect(_, let color) = $0 { return color == UITextView.selectionColor } else { return false } })
        view.becomeFirstResponder()
        list = scene.render(scale: 2)
        let highlights = list.commands.compactMap { command -> CGRect? in
            if case .fillRect(let rect, let color) = command, color == UITextView.selectionColor { return rect } else { return nil }
        }
        // "Select " is 52.5 wide, "Select some" 94: the highlight spans 41.5 from 57.5 in.
        #expect(highlights.count == 1)
        #expect(highlights.first?.minX == 16 + 5 + 52.5 && highlights.first?.width == 41.5)
        #expect(highlights.first?.minY == 340 + 8 - 1 && highlights.first?.height == 21.5)
        let knobs = list.commands.filter { if case .fillPath(_, let color, _) = $0 { return color == UITextView.selectionHandleColor } else { return false } }
        #expect(knobs.count == 2)
        view.text = "Short"
        #expect(view.selectedRange == NSRange(location: 5, length: 0))
    }

    @Test func textFlowsAroundExclusionPaths() {
        let (scene, root) = window()
        let view = UITextView(frame: CGRect(x: 16, y: 168, width: 288, height: 110))
        view.isEditable = false
        view.font = .systemFont(ofSize: 17)
        view.textContainer.exclusionPaths = [UIBezierPath(rect: CGRect(x: 0, y: 0, width: 80, height: 50))]
        view.text = "Wraps around\nthe box on\nthe left side\nand then\ncontinues below"
        root.view.addSubview(view)
        let drawn = texts(scene.render(scale: 2))
        #expect(drawn.map(\.0) == ["Wraps around", "the box on", "the left side", "and then", "continues below"])
        // The box crosses the first three 20.5 pt bands: those lines start after it (80 + 5).
        let xs: [CGFloat] = drawn.map { $0.1.x }
        let ys: [CGFloat] = drawn.map { $0.1.y }
        #expect(xs == [101, 101, 101, 21, 21])
        #expect(ys == [192.5, 213, 233.5, 254, 274.5])
        #expect(view.contentHeight(for: 288) == 101.5 + 16)
    }

    @Test func theDefaultFontIsHelveticaTwelve() {
        let (scene, root) = window()
        let view = UITextView(frame: CGRect(x: 16, y: 290, width: 288, height: 10))
        view.isScrollEnabled = false
        view.text = "Default font text"
        #expect(view.resolvedFont.familyName == "Helvetica" && view.resolvedFont.pointSize == 12)
        #expect(abs(view.resolvedFont.ascender - 11.04) < 0.01 && abs(view.resolvedFont.lineHeight - 13.8) < 0.01)
        view.frame.size.height = view.sizeThatFits(CGSize(width: 288, height: CGFloat.greatestFiniteMagnitude)).height
        #expect(view.frame.height == 30)
        root.view.addSubview(view)
        let drawn = texts(scene.render(scale: 2))
        #expect(drawn.first?.3 == 12 && drawn.first?.1.y == 290 + 19.5)
    }

    @Test func theIndicatorShowsAfterAScroll() {
        let (scene, root) = window()
        let view = UITextView(frame: CGRect(x: 16, y: 16, width: 288, height: 40))
        view.font = .systemFont(ofSize: 17)
        view.text = "The quick brown fox jumps over the lazy dog. Pack my box with five dozen liquor jugs."
        root.view.addSubview(view)
        scene.layout(in: CGSize(width: 320, height: 500))
        // Three lines (77 with the insets) in a 40 pt view: it scrolls, its indicator faded out.
        #expect(view.contentSize.height == 77)
        #expect(!view.verticalIndicator.isHidden && view.verticalIndicator.alpha == 0)
        scene.pointerDown(at: CGPoint(x: 100, y: 50), type: .touch, time: 0)
        scene.pointerMoved(to: CGPoint(x: 100, y: 30), time: 0.05)
        scene.pointerMoved(to: CGPoint(x: 100, y: 10), time: 0.1)
        #expect(view.verticalIndicator.alpha == 1)
        #expect(view.contentOffset.y > 0)
    }
}

#if canImport(AppKit)
import WebGraphicsNative

@Suite @MainActor struct TextViewLineBreakTests {
    /// The simulator fits "…red end, a" on the first line of uikit/textview/looks (268 wide in
    /// 278); the layouter must break the mixed-font line at the same place.
    @Test func mixedRunsBreakWhereTheSimulatorDoes() {
        let engine = CoreTextEngine()
        let runs = [StyledRun("Bold start, ", font: UIFont.boldSystemFont(ofSize: 17).resolved),
                    StyledRun("regular middle, ", font: UIFont.systemFont(ofSize: 17).resolved),
                    StyledRun("red end, ", font: UIFont.systemFont(ofSize: 15).resolved),
                    StyledRun("a link", font: UIFont.systemFont(ofSize: 17).resolved)]
        let layout = engine.layout(runs, options: UITextView.layoutOptions(lineLimit: nil), width: 278)
        #expect(layout.lines.count == 2)
        #expect(layout.lines.first?.fragments.last?.text == "a")
        // SwiftUI's text balances the two lines instead.
        #expect(engine.layout(runs, options: .default, width: 278).lines.first?.fragments.last?.text == "red end,")
    }
}
#endif
