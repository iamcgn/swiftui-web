// The table's section index (Docs/elements/UIKit/TableView.md): the column of titles at the
// right edge that scrolls to a section when touched or dragged. Measured on the iPhone SE
// simulator (uikit/table/indexed).
#if os(WASI)
import FoundationEssentials
#else
import Foundation
#endif

/// The strip of index titles: 11 pt semibold letters in the tint, centred as a column.
@MainActor
final class SectionIndexView: UIView {
    static let width: CGFloat = 15
    static let font = UIFont.systemFont(ofSize: 11, weight: .semibold)
    /// The pitch of the titles' column (uikit/table/indexed: cap tops 14 apart, the column centred).
    static let pitch: CGFloat = 14
    var titles: [String] = [] { didSet { setNeedsDisplay() } }
    weak var table: UITableView?
    private var tracking = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = false
    }

    private var columnTop: CGFloat { ((bounds.height - Self.pitch * CGFloat(titles.count)) / 2).rounded() }

    override func drawContent(into list: inout DisplayList, context: PaintContext, style: UIUserInterfaceStyle) {
        guard !titles.isEmpty else { return }
        if let background = table?.sectionIndexBackgroundColor {
            list.append(.fillRRect(context.absoluteRect(CGRect(origin: .zero, size: bounds.size)), cornerRadius: Self.width / 2, background.rgba(for: style)))
        }
        let color = (table?.sectionIndexColor ?? tintColor).rgba(for: style)
        let font = Self.font
        let displayFont = DisplayFont(font.resolved)
        var y = columnTop
        for title in titles {
            let width = UILabel.measuredWidth(of: title, font: font)
            let baseline = context.origin.y + y + ((Self.pitch - font.lineHeight) / 2) + font.ascender
            list.append(.drawText(title, displayFont, origin: CGPoint(x: context.origin.x + (((bounds.width - width) / 2) * context.scale).rounded() / context.scale, y: baseline), color))
            y += Self.pitch
        }
    }

    private func jump(at point: CGPoint) {
        guard !titles.isEmpty else { return }
        let index = min(titles.count - 1, max(0, Int((point.y - columnTop) / Self.pitch)))
        table?.jumpToIndexTitle(titles[index], at: index)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        tracking = true
        jump(at: touch.location(in: self))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard tracking, let touch = touches.first else { return }
        jump(at: touch.location(in: self))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { tracking = false }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { tracking = false }
}
