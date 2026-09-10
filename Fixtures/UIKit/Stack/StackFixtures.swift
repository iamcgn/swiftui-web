// UIStackView (Docs/elements/UIKit/UIStackView.md): vertical and horizontal stacks of labels
// and buttons, the fill and fill-equally distributions, alignments.
#if canImport(UIKit)
import UIKit
import UIKitFixtureKit

public enum StackFixtures {
    public static let all = [basic]

    public static let basic = UIKitFixture("uikit/stack/basic", size: CGSize(width: 320, height: 300)) {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 300))
        @MainActor func label(_ text: String, _ id: String) -> UILabel {
            let label = UILabel()
            label.text = text
            return label.probe(id)
        }
        // A vertical stack sized to its content, leading-aligned.
        let column = UIStackView(arrangedSubviews: [label("First", "first"), label("Second line", "second"), label("Third", "third")])
        column.axis = .vertical
        column.spacing = 8
        column.alignment = .leading
        let columnSize = column.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        column.frame = CGRect(x: 16, y: 16, width: columnSize.width, height: columnSize.height)
        root.addSubview(column.probe("column"))
        // A horizontal stack filling the width with equal columns.
        let minus = UIButton(type: .system)
        minus.setTitle("−", for: .normal)
        let plus = UIButton(type: .system)
        plus.setTitle("+", for: .normal)
        let row = UIStackView(arrangedSubviews: [minus.probe("minus"), plus.probe("plus")])
        row.axis = .horizontal
        row.distribution = .fillEqually
        row.spacing = 8
        row.frame = CGRect(x: 16, y: 120, width: 288, height: 34)
        root.addSubview(row.probe("row"))
        // A centred column whose width is the widest label's.
        let centred = UIStackView(arrangedSubviews: [label("Count: 0", "count"), label("A longer caption", "caption")])
        centred.axis = .vertical
        centred.spacing = 12
        centred.alignment = .center
        let centredSize = centred.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        centred.frame = CGRect(x: (320 - centredSize.width) / 2, y: 180, width: centredSize.width, height: centredSize.height)
        root.addSubview(centred.probe("centred"))
        return root
    }
}
#endif
