// UITextView looks (uk-textview): attributed text runs with a link, data-detected links, text
// wrapping around an exclusion path, the default (Helvetica 12) font, and a selection painted
// while editing (the "edit" step focuses the selected view).
#if canImport(UIKit)
import UIKit
import UIKitFixtureKit

extension TextViewFixtures {
    @MainActor
    public final class LooksModel {
        public let selected = UITextView()
        public init() {}
    }

    public static let looks = UIKitFixture("uikit/textview/looks", size: CGSize(width: 320, height: 420), model: { LooksModel() }, steps: [
        UIKitFixtureStep("edit") { model in
            model.selected.becomeFirstResponder()
            model.selected.selectedRange = NSRange(location: 7, length: 4)
        },
    ]) { model in
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 420))
        root.backgroundColor = .white

        let attributed = UITextView(frame: CGRect(x: 16, y: 16, width: 288, height: 10))
        attributed.isScrollEnabled = false
        attributed.backgroundColor = .systemGray6
        let text = NSMutableAttributedString(string: "Bold start, ", attributes: [.font: UIFont.boldSystemFont(ofSize: 17)])
        text.append(NSAttributedString(string: "regular middle, ", attributes: [.font: UIFont.systemFont(ofSize: 17)]))
        text.append(NSAttributedString(string: "red end, ", attributes: [.font: UIFont.systemFont(ofSize: 15), .foregroundColor: UIColor.systemRed]))
        text.append(NSAttributedString(string: "a link", attributes: [.font: UIFont.systemFont(ofSize: 17), .link: URL(string: "https://example.com/attributed")!]))
        attributed.attributedText = text
        attributed.frame.size.height = attributed.sizeThatFits(CGSize(width: 288, height: CGFloat.greatestFiniteMagnitude)).height
        root.addSubview(attributed.probe("attributed"))

        let links = UITextView(frame: CGRect(x: 16, y: 96, width: 288, height: 60))
        links.isEditable = false
        links.dataDetectorTypes = [.link]
        links.font = .systemFont(ofSize: 17)
        links.text = "Visit https://example.com or www.apple.com today."
        links.backgroundColor = .systemGray6
        root.addSubview(links.probe("links"))

        let excluded = UITextView(frame: CGRect(x: 16, y: 168, width: 288, height: 110))
        excluded.isEditable = false
        excluded.font = .systemFont(ofSize: 17)
        excluded.textContainer.exclusionPaths = [UIBezierPath(rect: CGRect(x: 0, y: 0, width: 80, height: 50))]
        excluded.text = "Wraps around\nthe box on\nthe left side\nand then\ncontinues below"
        excluded.backgroundColor = .systemGray6
        let box = UIView(frame: CGRect(x: 0, y: 8, width: 80, height: 50))
        box.backgroundColor = .systemBlue
        excluded.addSubview(box)
        root.addSubview(excluded.probe("excluded"))

        let defaultFont = UITextView(frame: CGRect(x: 16, y: 290, width: 288, height: 10))
        defaultFont.isScrollEnabled = false
        defaultFont.text = "Default font text"
        defaultFont.backgroundColor = .systemGray6
        defaultFont.frame.size.height = defaultFont.sizeThatFits(CGSize(width: 288, height: CGFloat.greatestFiniteMagnitude)).height
        root.addSubview(defaultFont.probe("defaultFont"))

        let selected = model.selected
        selected.frame = CGRect(x: 16, y: 340, width: 288, height: 60)
        selected.font = .systemFont(ofSize: 17)
        selected.text = "Select some of this text"
        selected.backgroundColor = .systemGray6
        root.addSubview(selected.probe("selected"))
        return root
    }
}
#endif
