// Swipe actions and editing controls (Docs/elements/UIKit/TableView.md): the contextual
// actions a row reveals when swiped, and the delete / insert controls and reorder grip of a
// table in editing mode. Measured on the iPhone SE simulator (uikit/table/editing).
#if os(WASI)
import FoundationEssentials
#else
import Foundation
#endif

/// An action a swiped row shows as a button.
@MainActor
open class UIContextualAction {
    public enum Style: Int, Sendable { case normal = 0, destructive }
    public typealias Handler = (UIContextualAction, UIView, @escaping (Bool) -> Void) -> Void
    public let style: Style
    open var title: String?
    open var image: UIImage?
    open var backgroundColor: UIColor?
    let handler: Handler
    public init(style: Style, title: String?, handler: @escaping Handler) {
        self.style = style
        self.title = title
        self.handler = handler
        backgroundColor = style == .destructive ? .systemRed : .systemGray
    }
}

/// The actions a row shows on one side.
@MainActor
open class UISwipeActionsConfiguration {
    public let actions: [UIContextualAction]
    open var performsFirstActionWithFullSwipe = true
    public init(actions: [UIContextualAction]) { self.actions = actions }
}

/// A revealed action's button: its colour behind a 17 pt white title, at least 74 wide.
@MainActor
final class SwipeActionButton: UIControl {
    let action: UIContextualAction
    static let font = UIFont.systemFont(ofSize: 17)
    static let minimumWidth: CGFloat = 74
    init(action: UIContextualAction) {
        self.action = action
        super.init(frame: .zero)
        accessibilityLabel = action.title
    }
    var preferredWidth: CGFloat {
        let text = action.title.map { UILabel.measuredWidth(of: $0, font: Self.font) } ?? 0
        return max(Self.minimumWidth, text + 32)
    }
    override func drawContent(into list: inout DisplayList, context: PaintContext, style: UIUserInterfaceStyle) {
        let rect = context.absoluteRect(CGRect(origin: .zero, size: bounds.size))
        list.append(.fillRect(rect, (action.backgroundColor ?? .systemGray).rgba(for: style)))
        guard let title = action.title, !title.isEmpty else { return }
        let font = Self.font
        let width = UILabel.measuredWidth(of: title, font: font)
        let baseline = context.origin.y + ((bounds.height - font.lineHeight) / 2).rounded() + font.ascender
        list.append(.drawText(title, DisplayFont(font.resolved), origin: CGPoint(x: context.origin.x + ((bounds.width - width) / 2).rounded(), y: baseline), RGBA(r: 255, g: 255, b: 255)))
    }
}
