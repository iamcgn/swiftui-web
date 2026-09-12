// UILabel (Docs/elements/UIKit/UILabel.md): sizes to fit at the system and text-style fonts,
// alignment inside a fixed frame, wrapping and truncation.
#if canImport(UIKit)
import UIKit
import UIKitFixtureKit

public enum LabelFixtures {
    public static let all = [basic, wrapping, tabular]

    /// Labels sized to fit: the default 17 pt system font, text styles, weights.
    public static let basic = UIKitFixture("uikit/label/basic", size: CGSize(width: 320, height: 300)) {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 300))
        @MainActor @discardableResult func label(_ text: String, _ font: UIFont, y: CGFloat, id: String) -> UILabel {
            let label = UILabel()
            label.text = text
            label.font = font
            label.sizeToFit()
            label.frame.origin = CGPoint(x: 16, y: y)
            root.addSubview(label.probe(id))
            return label
        }
        label("Hello, UIKit", .systemFont(ofSize: 17), y: 16, id: "system17")
        label("Title", .preferredFont(forTextStyle: .title1), y: 48, id: "title1")
        label("Headline", .preferredFont(forTextStyle: .headline), y: 96, id: "headline")
        label("Body", .preferredFont(forTextStyle: .body), y: 124, id: "body")
        label("Footnote", .preferredFont(forTextStyle: .footnote), y: 152, id: "footnote")
        label("Bold 13", .boldSystemFont(ofSize: 13), y: 176, id: "bold13")
        label("Semibold 20", .systemFont(ofSize: 20, weight: .semibold), y: 200, id: "semibold20")
        // A centred label in a fixed frame.
        let centred = UILabel(frame: CGRect(x: 16, y: 240, width: 288, height: 30))
        centred.text = "Centred"
        centred.textAlignment = .center
        centred.backgroundColor = UIColor.systemGray5
        root.addSubview(centred.probe("centred"))
        return root
    }

    /// Wrapping at a width, and truncation in a narrow one-line frame.
    public static let wrapping = UIKitFixture("uikit/label/wrapping", size: CGSize(width: 320, height: 200)) {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 200))
        let wrapped = UILabel()
        wrapped.text = "The quick brown fox jumps over the lazy dog"
        wrapped.numberOfLines = 0
        let size = wrapped.sizeThatFits(CGSize(width: 200, height: CGFloat.greatestFiniteMagnitude))
        wrapped.frame = CGRect(x: 16, y: 16, width: 200, height: size.height)
        root.addSubview(wrapped.probe("wrapped"))
        let twoLines = UILabel()
        twoLines.text = "The quick brown fox jumps over the lazy dog"
        twoLines.numberOfLines = 2
        let two = twoLines.sizeThatFits(CGSize(width: 200, height: CGFloat.greatestFiniteMagnitude))
        twoLines.frame = CGRect(x: 16, y: 100, width: 200, height: two.height)
        root.addSubview(twoLines.probe("twoLines"))
        let truncated = UILabel(frame: CGRect(x: 16, y: 160, width: 120, height: 21))
        truncated.text = "The quick brown fox jumps over the lazy dog"
        root.addSubview(truncated.probe("truncated"))
        return root
    }

    /// Tabular figures: the same digit strings in the proportional system font and in
    /// `monospacedDigitSystemFont`, where every digit takes the same advance.
    public static let tabular = UIKitFixture("uikit/label/tabular", size: CGSize(width: 320, height: 220)) {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 220))
        @MainActor @discardableResult func label(_ text: String, _ font: UIFont, x: CGFloat, y: CGFloat, id: String) -> UILabel {
            let label = UILabel()
            label.text = text
            label.font = font
            label.sizeToFit()
            label.frame.origin = CGPoint(x: x, y: y)
            root.addSubview(label.probe(id))
            return label
        }
        label("1111", .systemFont(ofSize: 17), x: 16, y: 16, id: "ones")
        label("1111", .monospacedDigitSystemFont(ofSize: 17, weight: .regular), x: 160, y: 16, id: "tabularOnes")
        label("0000", .systemFont(ofSize: 17), x: 16, y: 48, id: "zeros")
        label("0000", .monospacedDigitSystemFont(ofSize: 17, weight: .regular), x: 160, y: 48, id: "tabularZeros")
        label("12:34:56", .systemFont(ofSize: 17), x: 16, y: 80, id: "time")
        label("12:34:56", .monospacedDigitSystemFont(ofSize: 17, weight: .regular), x: 160, y: 80, id: "tabularTime")
        label("Total 1,234.56", .systemFont(ofSize: 15, weight: .semibold), x: 16, y: 112, id: "total")
        label("Total 1,234.56", .monospacedDigitSystemFont(ofSize: 15, weight: .semibold), x: 160, y: 112, id: "tabularTotal")
        label("Score 71 / 99", .monospacedDigitSystemFont(ofSize: 22, weight: .bold), x: 16, y: 150, id: "tabularScore")
        return root
    }
}
#endif
