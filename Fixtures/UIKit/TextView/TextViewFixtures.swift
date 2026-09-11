// UITextView (Docs/elements/UIKit/TextView.md): a scrolling text view with wrapped body text,
// text views sized to fit (the default insets, custom container insets),
// centred text and a non-editable one on a fill, measured against UIKit on the simulator.
#if canImport(UIKit)
import UIKit
import UIKitFixtureKit

public enum TextViewFixtures {
    public static let all = [basic, heights]

    public static let basic = UIKitFixture("uikit/textview/basic", size: CGSize(width: 320, height: 400)) {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        root.backgroundColor = .white

        let body = UITextView(frame: CGRect(x: 16, y: 16, width: 288, height: 96))
        body.font = .systemFont(ofSize: 17)
        body.text = "The quick brown fox jumps over the lazy dog. Pack my box with five dozen liquor jugs."
        body.backgroundColor = .systemGray6
        root.addSubview(body.probe("body"))

        // `sizeToFit` on a text view: the width is the text's used width plus the insets (no
        // line fragment padding), the height is the text's at the width it had before, so the
        // text re-wraps narrower and is clipped: a UIKit quirk the golden pins.
        let fitted = UITextView(frame: CGRect(x: 16, y: 128, width: 200, height: 10))
        fitted.isScrollEnabled = false
        fitted.font = .systemFont(ofSize: 17)
        fitted.text = "Two lines of\ntext"
        fitted.backgroundColor = .systemGray6
        fitted.sizeToFit()
        root.addSubview(fitted.probe("fitted"))

        // Growing text views: a fixed width, the height `sizeThatFits` gives for it.
        let padded = UITextView(frame: CGRect(x: 16, y: 200, width: 160, height: 10))
        padded.isScrollEnabled = false
        padded.font = .systemFont(ofSize: 15)
        padded.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        padded.text = "Padded"
        padded.backgroundColor = .systemGray6
        padded.frame.size.height = padded.sizeThatFits(CGSize(width: 160, height: CGFloat.greatestFiniteMagnitude)).height
        root.addSubview(padded.probe("padded"))

        let centred = UITextView(frame: CGRect(x: 16, y: 264, width: 200, height: 10))
        centred.isScrollEnabled = false
        centred.font = .systemFont(ofSize: 17)
        centred.textAlignment = .center
        centred.text = "Centred"
        centred.backgroundColor = .systemGray6
        centred.frame.size.height = centred.sizeThatFits(CGSize(width: 200, height: CGFloat.greatestFiniteMagnitude)).height
        root.addSubview(centred.probe("centred"))

        let readOnly = UITextView(frame: CGRect(x: 16, y: 320, width: 288, height: 60))
        readOnly.isEditable = false
        readOnly.font = .systemFont(ofSize: 13)
        readOnly.textColor = .secondaryLabel
        readOnly.text = "Read-only footnote text that wraps onto a second line in this width."
        readOnly.backgroundColor = .clear
        root.addSubview(readOnly.probe("readOnly"))
        return root
    }

    /// One-line text views at the sizes an app uses, each as tall as `sizeThatFits` says.
    public static let heights = UIKitFixture("uikit/textview/heights", size: CGSize(width: 320, height: 400)) {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        root.backgroundColor = .white
        var y: CGFloat = 8
        for size in [11, 12, 13, 14, 15, 16, 17, 20, 24, 28] as [CGFloat] {
            let view = UITextView(frame: CGRect(x: 16, y: y, width: 200, height: 10))
            view.isScrollEnabled = false
            view.font = .systemFont(ofSize: size)
            view.text = "Height \(Int(size))"
            view.backgroundColor = .systemGray6
            view.frame.size.height = view.sizeThatFits(CGSize(width: 200, height: CGFloat.greatestFiniteMagnitude)).height
            root.addSubview(view.probe("h\(Int(size))"))
            y += view.frame.height + 4
        }
        return root
    }
}
#endif
