// UITableView (Docs/elements/UIKit/TableView.md): rows from a data source in one scrolling
// view, the plain and inset grouped styles, section headers and footers, the default, subtitle
// and value1 cell styles with accessories, selection. Geometry from UIKit on the iPhone SE
// simulator (iOS 26): 56 pt text rows, 73 pt subtitle rows, 1 pt separators 16 in, grouped
// cards 16 in with 26 pt corners.

#if os(WASI)
import FoundationEssentials

/// Foundation's root class does not exist on wasm; data sources and delegates written for UIKit
/// subclass it, so an empty stand-in keeps them compiling.
open class NSObject {
    public init() {}
}
public protocol NSObjectProtocol: AnyObject {}

/// Foundation's index set is not in FoundationEssentials either: the sections a table reloads.
public struct IndexSet: Hashable, Sendable, ExpressibleByArrayLiteral, Sequence {
    public var indices: Set<Int>
    public init() { indices = [] }
    public init(_ indices: some Sequence<Int>) { self.indices = Set(indices) }
    public init(integer: Int) { indices = [integer] }
    public init(integersIn range: Range<Int>) { indices = Set(range) }
    public init(arrayLiteral elements: Int...) { indices = Set(elements) }
    public func makeIterator() -> Set<Int>.Iterator { indices.makeIterator() }
    public var count: Int { indices.count }
    public func contains(_ integer: Int) -> Bool { indices.contains(integer) }
    public mutating func insert(_ integer: Int) { indices.insert(integer) }
}
#else
import Foundation
#endif

extension IndexPath {
    /// A table row's position (UIKit's additions to Foundation's index path).
    public init(row: Int, section: Int) { self.init(indexes: [section, row]) }
    public var row: Int { get { self[1] } set { self[1] = newValue } }
    public var section: Int { get { self[0] } set { self[0] = newValue } }
}

/// The methods that an object adopts to manage data and provide cells for a table view.
@MainActor
public protocol UITableViewDataSource: AnyObject {
    func numberOfSections(in tableView: UITableView) -> Int
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String?
    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String?
    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool
    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath)
}

extension UITableViewDataSource {
    public func numberOfSections(in tableView: UITableView) -> Int { 1 }
    public func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { nil }
    public func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? { nil }
    public func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool { false }
    public func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {}
}

/// Methods for managing selections, configuring section headers and footers, deleting and
/// reordering cells, and performing other actions in a table view.
@MainActor
public protocol UITableViewDelegate: UIScrollViewDelegate {
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat
    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView?
    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView?
    func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath?
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath)
    func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath)
    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath)
    func tableView(_ tableView: UITableView, accessoryButtonTappedForRowWith indexPath: IndexPath)
}

extension UITableViewDelegate {
    public func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat { UITableView.automaticDimension }
    public func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat { UITableView.automaticDimension }
    public func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat { UITableView.automaticDimension }
    public func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? { nil }
    public func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? { nil }
    public func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? { indexPath }
    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {}
    public func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {}
    public func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {}
    public func tableView(_ tableView: UITableView, accessoryButtonTappedForRowWith indexPath: IndexPath) {}
}

/// A view that presents data using rows in a single column.
@MainActor
open class UITableView: UIScrollView {
    public enum Style: Int, Sendable { case plain = 0, grouped, insetGrouped }
    public enum ScrollPosition: Int, Sendable { case none = 0, top, middle, bottom }
    public enum RowAnimation: Int, Sendable { case fade = 0, right, left, top, bottom, none, middle, automatic = 100 }

    public static let automaticDimension: CGFloat = -1

    public let style: Style
    open weak var dataSource: (any UITableViewDataSource)? { didSet { setNeedsReload() } }
    open weak var tableDelegate: (any UITableViewDelegate)?
    open var rowHeight: CGFloat = UITableView.automaticDimension { didSet { setNeedsReload() } }
    open var estimatedRowHeight: CGFloat = 0
    open var sectionHeaderHeight: CGFloat = UITableView.automaticDimension
    open var sectionFooterHeight: CGFloat = UITableView.automaticDimension
    /// The space above the first section's header in the plain style (22 with a header).
    open var sectionHeaderTopPadding: CGFloat = UITableView.automaticDimension
    open var separatorStyle: UITableViewCell.SeparatorStyle = .singleLine { didSet { setNeedsDisplay() } }
    open var separatorColor: UIColor? = .separator
    open var separatorInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 0)
    open var allowsSelection = true
    open var allowsMultipleSelection = false
    open var tableHeaderView: UIView? { didSet { oldValue?.removeFromSuperview(); if let view = tableHeaderView { addSubview(view) }; setNeedsReload() } }
    open var tableFooterView: UIView? { didSet { oldValue?.removeFromSuperview(); if let view = tableFooterView { addSubview(view) }; setNeedsReload() } }
    open var isEditing = false
    open var cellLayoutMarginsFollowReadableWidth = false
    open var insetsContentViewsToSafeArea = true

    /// The delegate is a table view delegate too.
    open override weak var delegate: (any UIScrollViewDelegate)? {
        didSet { tableDelegate = delegate as? any UITableViewDelegate }
    }

    private var registeredCells: [String: () -> UITableViewCell] = [:]
    private var reusePool: [String: [UITableViewCell]] = [:]
    private var visibleCellsByPath: [IndexPath: UITableViewCell] = [:]
    private var headerViews: [Int: UIView] = [:]
    private var footerViews: [Int: UIView] = [:]
    private var needsReload = true
    private var rowFrames: [IndexPath: CGRect] = [:]
    private var selected: Set<IndexPath> = []

    public init(frame: CGRect, style: Style) {
        self.style = style
        super.init(frame: frame)
        // The grouped ground is (242, 242, 247) on the iPhone (uikit/table/grouped).
        backgroundColor = style == .plain ? .systemBackground : UIColor(light: RGBA(r: 242, g: 242, b: 247), dark: .black)
        alwaysBounceVertical = true
        let tap = UITapGestureRecognizer()
        tap.addTarget { [weak self] recognizer in self?.handleTap(recognizer) }
        addGestureRecognizer(tap)
    }

    public override convenience init(frame: CGRect) { self.init(frame: frame, style: .plain) }

    // MARK: Cells

    open func register(_ cellClass: AnyClass?, forCellReuseIdentifier identifier: String) {
        guard let type = cellClass as? UITableViewCell.Type else { return }
        registeredCells[identifier] = { type.init(style: .default, reuseIdentifier: identifier) }
    }

    open func dequeueReusableCell(withIdentifier identifier: String) -> UITableViewCell? {
        if let cell = reusePool[identifier]?.popLast() {
            cell.prepareForReuse()
            return cell
        }
        return registeredCells[identifier]?()
    }

    open func dequeueReusableCell(withIdentifier identifier: String, for indexPath: IndexPath) -> UITableViewCell {
        dequeueReusableCell(withIdentifier: identifier) ?? UITableViewCell(style: .default, reuseIdentifier: identifier)
    }

    open var visibleCells: [UITableViewCell] { visibleCellsByPath.sorted { $0.key < $1.key }.map(\.value) }
    open var indexPathsForVisibleRows: [IndexPath]? { visibleCellsByPath.keys.sorted() }
    open func cellForRow(at indexPath: IndexPath) -> UITableViewCell? { visibleCellsByPath[indexPath] }
    open func indexPath(for cell: UITableViewCell) -> IndexPath? { visibleCellsByPath.first { $0.value === cell }?.key }
    open func rectForRow(at indexPath: IndexPath) -> CGRect { rowFrames[indexPath] ?? .zero }
    open func indexPathForRow(at point: CGPoint) -> IndexPath? { rowFrames.first { $0.value.contains(point) }?.key }
    open var numberOfSections: Int { dataSource?.numberOfSections(in: self) ?? 0 }
    open func numberOfRows(inSection section: Int) -> Int { dataSource?.tableView(self, numberOfRowsInSection: section) ?? 0 }

    // MARK: Selection

    open var indexPathForSelectedRow: IndexPath? { selected.sorted().first }
    open var indexPathsForSelectedRows: [IndexPath]? { selected.isEmpty ? nil : selected.sorted() }

    open func selectRow(at indexPath: IndexPath?, animated: Bool, scrollPosition: ScrollPosition) {
        if !allowsMultipleSelection { for path in selected { visibleCellsByPath[path]?.setSelected(false, animated: false) }; selected.removeAll() }
        guard let indexPath else { setNeedsDisplay(); return }
        selected.insert(indexPath)
        visibleCellsByPath[indexPath]?.setSelected(true, animated: animated)
        if scrollPosition != .none { scrollToRow(at: indexPath, at: scrollPosition, animated: animated) }
        setNeedsDisplay()
    }

    open func deselectRow(at indexPath: IndexPath, animated: Bool) {
        selected.remove(indexPath)
        visibleCellsByPath[indexPath]?.setSelected(false, animated: animated)
        setNeedsDisplay()
    }

    open func scrollToRow(at indexPath: IndexPath, at scrollPosition: ScrollPosition, animated: Bool) {
        guard let frame = rowFrames[indexPath] else { return }
        var offset = contentOffset
        switch scrollPosition {
        case .top: offset.y = frame.minY
        case .middle: offset.y = frame.midY - bounds.height / 2
        case .bottom: offset.y = frame.maxY - bounds.height
        case .none: if frame.minY < offset.y { offset.y = frame.minY } else if frame.maxY > offset.y + bounds.height { offset.y = frame.maxY - bounds.height }
        }
        setContentOffset(offset, animated: animated)
    }

    private func handleTap(_ recognizer: UIGestureRecognizer) {
        guard allowsSelection, recognizer.state == .ended else { return }
        let point = recognizer.location(in: self)
        guard let path = indexPathForRow(at: point) else { return }
        if selected.contains(path), allowsMultipleSelection {
            deselectRow(at: path, animated: false)
            tableDelegate?.tableView(self, didDeselectRowAt: path)
            return
        }
        var target = path
        if let tableDelegate {
            guard let allowed = tableDelegate.tableView(self, willSelectRowAt: path) else { return }
            target = allowed
        }
        let previous = selected
        selectRow(at: target, animated: false, scrollPosition: .none)
        for old in previous where old != target { tableDelegate?.tableView(self, didDeselectRowAt: old) }
        tableDelegate?.tableView(self, didSelectRowAt: target)
    }

    // MARK: Loading

    open func reloadData() { setNeedsReload() }
    open func reloadRows(at indexPaths: [IndexPath], with animation: RowAnimation) { setNeedsReload() }
    open func reloadSections(_ sections: IndexSet, with animation: RowAnimation) { setNeedsReload() }
    open func insertRows(at indexPaths: [IndexPath], with animation: RowAnimation) { setNeedsReload() }
    open func deleteRows(at indexPaths: [IndexPath], with animation: RowAnimation) { setNeedsReload() }
    open func insertSections(_ sections: IndexSet, with animation: RowAnimation) { setNeedsReload() }
    open func deleteSections(_ sections: IndexSet, with animation: RowAnimation) { setNeedsReload() }
    open func beginUpdates() {}
    open func endUpdates() { setNeedsReload() }
    open func performBatchUpdates(_ updates: (() -> Void)?, completion: ((Bool) -> Void)? = nil) {
        updates?()
        setNeedsReload()
        completion?(true)
    }

    private func setNeedsReload() {
        needsReload = true
        setNeedsLayout()
    }

    // MARK: Geometry (measured, Docs/elements/UIKit/TableView.md)

    var isGrouped: Bool { style != .plain }
    /// The inset grouped style's cards sit 16 in.
    var cardInset: CGFloat { style == .insetGrouped ? 16 : 0 }
    static let cardCornerRadius: CGFloat = 26

    open override func layoutSubviews() {
        super.layoutSubviews()
        if needsReload { reload() }
    }

    /// Builds every row (the tables here are short; no recycling of off-screen rows yet).
    private func reload() {
        needsReload = false
        for cell in visibleCellsByPath.values {
            cell.removeFromSuperview()
            if let identifier = cell.reuseIdentifier { reusePool[identifier, default: []].append(cell) }
        }
        visibleCellsByPath.removeAll()
        for view in headerViews.values { view.removeFromSuperview() }
        for view in footerViews.values { view.removeFromSuperview() }
        headerViews.removeAll()
        footerViews.removeAll()
        rowFrames.removeAll()
        guard let dataSource else { contentSize = .zero; return }

        var y: CGFloat = 0
        let width = bounds.width
        let rowWidth = width - 2 * cardInset
        if let header = tableHeaderView {
            header.frame = CGRect(x: 0, y: y, width: width, height: header.frame.height)
            y += header.frame.height
        }
        let sections = dataSource.numberOfSections(in: self)
        for section in 0..<sections {
            let headerTitle = dataSource.tableView(self, titleForHeaderInSection: section)
            let footerTitle = dataSource.tableView(self, titleForFooterInSection: section)
            let customHeader = tableDelegate?.tableView(self, viewForHeaderInSection: section)
            // The header: the plain style pads 22 above a titled first header; grouped sections
            // start under a 55.5 tall header (a first one) or 38 (later ones), untitled grouped
            // sections keep a 35 pt gap.
            if let customHeader {
                var height = tableDelegate?.tableView(self, heightForHeaderInSection: section) ?? Self.automaticDimension
                if height == Self.automaticDimension { height = customHeader.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height }
                customHeader.frame = CGRect(x: 0, y: y, width: width, height: height)
                addSubview(customHeader)
                headerViews[section] = customHeader
                y += height
            } else if isGrouped {
                let view = UITableViewHeaderFooterView(reuseIdentifier: nil)
                view.textLabel?.text = headerTitle
                view.isHeader = true
                view.style = style
                let height: CGFloat = headerTitle == nil ? (section == 0 ? 35 : 35) : (section == 0 ? 55.5 : 38)
                view.frame = CGRect(x: 0, y: y, width: width, height: height)
                view.inset = cardInset
                addSubview(view)
                headerViews[section] = view
                y += height
            } else if let headerTitle {
                if section == 0 { y += sectionHeaderTopPadding == Self.automaticDimension ? 22 : sectionHeaderTopPadding }
                let view = UITableViewHeaderFooterView(reuseIdentifier: nil)
                view.textLabel?.text = headerTitle
                view.isHeader = true
                view.style = style
                view.frame = CGRect(x: 0, y: y, width: width, height: 28)
                addSubview(view)
                headerViews[section] = view
                y += 28
            }
            let rows = dataSource.tableView(self, numberOfRowsInSection: section)
            for row in 0..<rows {
                let path = IndexPath(row: row, section: section)
                let cell = dataSource.tableView(self, cellForRowAt: path)
                cell.tableStyle = style
                cell.isFirstInSection = row == 0
                cell.isLastInSection = row == rows - 1
                var height = tableDelegate?.tableView(self, heightForRowAt: path) ?? rowHeight
                if height == Self.automaticDimension { height = rowHeight == Self.automaticDimension ? cell.preferredHeight : rowHeight }
                cell.frame = CGRect(x: cardInset, y: y, width: rowWidth, height: height)
                cell.setSelected(selected.contains(path), animated: false)
                tableDelegate?.tableView(self, willDisplay: cell, forRowAt: path)
                addSubview(cell)
                visibleCellsByPath[path] = cell
                rowFrames[path] = cell.frame
                y += height
            }
            if let footerTitle, isGrouped {
                let view = UITableViewHeaderFooterView(reuseIdentifier: nil)
                view.textLabel?.text = footerTitle
                view.isHeader = false
                view.style = style
                view.inset = cardInset
                // 4.5 above and below the label, which is 21 tall for one 13 pt line (uikit/table/grouped).
                let text = view.textLabel?.sizeThatFits(CGSize(width: rowWidth - 32, height: .greatestFiniteMagnitude)).height ?? 0
                let height = max(21, text) + 9
                view.frame = CGRect(x: 0, y: y, width: width, height: height)
                addSubview(view)
                footerViews[section] = view
                y += height
            } else if let footerTitle {
                let view = UITableViewHeaderFooterView(reuseIdentifier: nil)
                view.textLabel?.text = footerTitle
                view.isHeader = false
                view.style = style
                view.frame = CGRect(x: 0, y: y, width: width, height: 28)
                addSubview(view)
                footerViews[section] = view
                y += 28
            }
        }
        if let footer = tableFooterView {
            footer.frame = CGRect(x: 0, y: y, width: width, height: footer.frame.height)
            y += footer.frame.height
        }
        contentSize = CGSize(width: width, height: y)
    }
}

/// The header or footer of a table section: a 17 pt semibold title (plain: 16 in, 2 down in
/// 28; grouped: 32 in, 27 down in a 55.5 first header, 9.5 in a 38 pt later one) or a 13 pt
/// footer 4.5 down.
@MainActor
open class UITableViewHeaderFooterView: UIView {
    public let reuseIdentifier: String?
    public private(set) var textLabel: UILabel?
    public private(set) var detailTextLabel: UILabel?
    public let contentView = UIView()
    var isHeader = true {
        didSet {
            // The fonts before the first layout, so the table can measure the title.
            textLabel?.font = isHeader ? .systemFont(ofSize: 17, weight: .semibold) : .systemFont(ofSize: 13)
            textLabel?.textColor = isHeader ? .label : .secondaryLabel
        }
    }
    var style: UITableView.Style = .plain
    var inset: CGFloat = 0

    public init(reuseIdentifier: String?) {
        self.reuseIdentifier = reuseIdentifier
        super.init(frame: .zero)
        let label = UILabel()
        label.numberOfLines = 0
        label.font = .systemFont(ofSize: 17, weight: .semibold)
        textLabel = label
        addSubview(contentView)
        contentView.addSubview(label)
    }

    public override convenience init(frame: CGRect) { self.init(reuseIdentifier: nil) }

    open func prepareForReuse() {}

    open override func layoutSubviews() {
        super.layoutSubviews()
        contentView.frame = CGRect(x: inset, y: 0, width: bounds.width - 2 * inset, height: bounds.height)
        guard let label = textLabel else { return }
        if isHeader {
            label.font = .systemFont(ofSize: 17, weight: .semibold)
            label.textColor = .label
            let size = label.sizeThatFits(CGSize(width: contentView.bounds.width - 32, height: .greatestFiniteMagnitude))
            let y: CGFloat = style == .plain ? 2 : (bounds.height > 40 ? 27 : 9.5)
            label.frame = CGRect(x: 16, y: y, width: size.width, height: style == .plain ? 25 : 24.5)
        } else {
            label.font = .systemFont(ofSize: 13)
            label.textColor = .secondaryLabel
            let size = label.sizeThatFits(CGSize(width: contentView.bounds.width - 32, height: .greatestFiniteMagnitude))
            label.frame = CGRect(x: 16, y: 4.5, width: size.width, height: size.height)
        }
    }
}

/// The visual representation of a single row in a table view.
@MainActor
open class UITableViewCell: UIView {
    public enum CellStyle: Int, Sendable { case `default` = 0, value1, value2, subtitle }
    public enum AccessoryType: Int, Sendable { case none = 0, disclosureIndicator, detailDisclosureButton, checkmark, detailButton }
    public enum SelectionStyle: Int, Sendable { case none = 0, blue, gray, `default` }
    public enum SeparatorStyle: Int, Sendable { case none = 0, singleLine }
    public enum EditingStyle: Int, Sendable { case none = 0, delete, insert }

    public let style: CellStyle
    public let reuseIdentifier: String?
    public let contentView = UIView()
    public private(set) var textLabel: UILabel?
    public private(set) var detailTextLabel: UILabel?
    public private(set) var imageView: UIImageView?
    open var accessoryType: AccessoryType = .none { didSet { setNeedsLayout() } }
    open var accessoryView: UIView? { didSet { oldValue?.removeFromSuperview(); if let view = accessoryView { addSubview(view) }; setNeedsLayout() } }
    open var selectionStyle: SelectionStyle = .default
    open private(set) var isSelected = false
    open private(set) var isHighlighted = false
    open var backgroundView: UIView?
    open var selectedBackgroundView: UIView?
    open var indentationLevel = 0
    open var separatorInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 0)
    var tableStyle: UITableView.Style = .plain
    var isFirstInSection = false
    var isLastInSection = false

    public required init(style: CellStyle, reuseIdentifier: String?) {
        self.style = style
        self.reuseIdentifier = reuseIdentifier
        super.init(frame: .zero)
        backgroundColor = .systemBackground
        addSubview(contentView)
        let title = UILabel()
        title.font = .systemFont(ofSize: 17)
        textLabel = title
        contentView.addSubview(title)
        if style != .default {
            let detail = UILabel()
            detail.font = .systemFont(ofSize: style == .subtitle ? 15 : 17)
            detail.textColor = .secondaryLabel
            detailTextLabel = detail
            contentView.addSubview(detail)
        }
        let image = UIImageView()
        imageView = image
        contentView.addSubview(image)
        isAccessibilityElement = false
    }

    public override convenience init(frame: CGRect) { self.init(style: .default, reuseIdentifier: nil) }

    open func prepareForReuse() {
        isSelected = false
        isHighlighted = false
        accessoryType = .none
        accessoryView = nil
    }

    open func setSelected(_ selected: Bool, animated: Bool) {
        isSelected = selected
        setNeedsDisplay()
    }

    open func setHighlighted(_ highlighted: Bool, animated: Bool) {
        isHighlighted = highlighted
        setNeedsDisplay()
    }

    /// The row height UIKit gives the cell's content: 56 for a text row (the default and
    /// value1 styles), 73 for a subtitle row.
    var preferredHeight: CGFloat { style == .subtitle ? 73 : 56 }

    /// The accessory's size: the disclosure chevron 10.5 × 14, the checkmark 19 × 18.
    private var accessorySize: CGSize {
        switch accessoryType {
        case .disclosureIndicator, .detailDisclosureButton: return CGSize(width: 10.5, height: 14)
        case .checkmark: return CGSize(width: 19, height: 18)
        case .detailButton: return CGSize(width: 22, height: 22)
        case .none: return accessoryView?.frame.size ?? .zero
        }
    }

    open override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        // The content view ends where the accessory starts (16 from the right for a chevron,
        // 18.5 for a checkmark), else spans the row.
        let accessory = accessorySize
        let accessoryRight: CGFloat = accessoryType == .checkmark ? 18.5 : 16
        let contentWidth = accessory.width > 0 ? width - accessoryRight - accessory.width : width
        contentView.frame = CGRect(x: 0, y: 0, width: contentWidth, height: bounds.height)
        if let accessoryView {
            accessoryView.frame = CGRect(x: contentWidth, y: (bounds.height - accessoryView.frame.height) / 2, width: accessoryView.frame.width, height: accessoryView.frame.height)
        }
        var x: CGFloat = 16
        if let imageView, let image = imageView.image {
            imageView.frame = CGRect(x: 16, y: (bounds.height - image.size.height) / 2, width: image.size.width, height: image.size.height)
            x += image.size.width + 16
        } else {
            imageView?.frame = .zero
        }
        guard let title = textLabel else { return }
        switch style {
        case .default:
            title.frame = CGRect(x: x, y: 0, width: contentWidth - x - 16, height: bounds.height)
        case .subtitle:
            let titleWidth = title.intrinsicContentSize.width
            title.frame = CGRect(x: x, y: 11, width: min(titleWidth, contentWidth - x - 16), height: 24.5)
            if let detail = detailTextLabel {
                let detailWidth = detail.intrinsicContentSize.width
                detail.frame = CGRect(x: x, y: 38.5, width: min(detailWidth, contentWidth - x - 16), height: 21)
            }
        case .value1, .value2:
            let titleWidth = title.intrinsicContentSize.width
            title.frame = CGRect(x: x, y: 16, width: min(titleWidth, contentWidth - x - 16), height: 24.5)
            if let detail = detailTextLabel {
                let detailWidth = detail.intrinsicContentSize.width
                // The detail ends 16 from the row's right, or 8 before the accessory.
                let right = accessory.width > 0 ? contentWidth - 8 : contentWidth - 16
                detail.frame = CGRect(x: right - detailWidth, y: 16, width: detailWidth, height: 24.5)
                detail.textAlignment = .right
            }
        }
    }

    override func drawContent(into list: inout DisplayList, context: PaintContext, style userStyle: UIUserInterfaceStyle) {
        let rect = context.absoluteRect(CGRect(origin: .zero, size: bounds.size))
        // The selection: a grey fill over the row (the default selection style).
        if isSelected || isHighlighted, selectionStyle != .none {
            let fill = UIColor.systemGray4.rgba(for: userStyle)
            if tableStyle == .insetGrouped {
                list.append(.fillPath(cardPath(rect), fill))
            } else {
                list.append(.fillRect(rect, fill))
            }
        }
        let ink = UIColor.tertiaryLabel.rgba(for: userStyle)
        let contentWidth = contentView.bounds.width
        switch accessoryType {
        case .disclosureIndicator, .detailDisclosureButton:
            // The chevron: 10.5 × 14 at the content view's right, centred; a 2 pt stroke.
            let box = context.absoluteRect(CGRect(x: contentWidth, y: (bounds.height - 14) / 2, width: 10.5, height: 14))
            var chevron = Path()
            chevron.move(to: CGPoint(x: box.minX + 2, y: box.minY + 1.5))
            chevron.addLine(to: CGPoint(x: box.maxX - 1.5, y: box.midY))
            chevron.addLine(to: CGPoint(x: box.minX + 2, y: box.maxY - 1.5))
            list.append(.strokePath(chevron, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round), ink))
        case .checkmark:
            let box = context.absoluteRect(CGRect(x: contentWidth, y: (bounds.height - 18) / 2, width: 19, height: 18))
            var mark = Path()
            mark.move(to: CGPoint(x: box.minX + 1.5, y: box.midY + 1))
            mark.addLine(to: CGPoint(x: box.minX + 7, y: box.maxY - 2))
            mark.addLine(to: CGPoint(x: box.maxX - 1.5, y: box.minY + 2))
            list.append(.strokePath(mark, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round), tintColor.rgba(for: userStyle)))
        default:
            break
        }
        // The separator: 1 pt at the bottom, from the content's leading inset (16) to the row's
        // right (the plain style keeps 16 on the right too); a grouped section's last row has none.
        if !(tableStyle != .plain && isLastInSection) {
            let separatorColor = UIColor.separator.rgba(for: userStyle)
            let left = separatorInset.left
            let right: CGFloat = tableStyle == .plain ? 16 : (accessorySize.width > 0 ? 16 : 0)
            let line = context.absoluteRect(CGRect(x: left, y: bounds.height - 1, width: bounds.width - left - right, height: 1))
            list.append(.fillRect(line, separatorColor))
        }
    }

    /// The card corners of an inset grouped row: 26 pt on the section's first row's top and its
    /// last row's bottom.
    func cardPath(_ rect: CGRect) -> Path {
        let radius = UITableView.cardCornerRadius
        return Path(roundedRect: rect, cornerRadii: RectangleCornerRadii(
            topLeading: isFirstInSection ? radius : 0, bottomLeading: isLastInSection ? radius : 0,
            bottomTrailing: isLastInSection ? radius : 0, topTrailing: isFirstInSection ? radius : 0), style: .continuous)
    }

    /// Grouped rows paint their background as a card slice (the layer's background stays clear).
    open override var backgroundColor: UIColor? {
        didSet { if tableStyle != .plain { layer.backgroundColor = nil } }
    }
}

