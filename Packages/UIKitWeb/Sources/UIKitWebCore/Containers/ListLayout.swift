// List layouts (Docs/elements/UIKit/CollectionView.md): `UICollectionViewCompositionalLayout.list(using:)`
// lays list cells out as a table would (the inset grouped appearance's cards 16 in with 26 pt
// corners, 35 pt gaps, rows sized by their list content: 56 for one line, 79.5 with a
// secondary text), and `UICollectionViewListCell` draws the card, the separator and its
// accessories. Measured on the iPhone SE simulator (uikit/collection/list).
#if os(WASI)
import FoundationEssentials
#else
import Foundation
#endif

/// A configuration for a list layout.
public struct UICollectionLayoutListConfiguration: Sendable {
    public enum Appearance: Int, Sendable { case plain = 0, grouped, insetGrouped, sidebar, sidebarPlain }
    public enum HeaderMode: Int, Sendable { case none = 0, supplementary, firstItemInSection }
    public enum FooterMode: Int, Sendable { case none = 0, supplementary }

    public let appearance: Appearance
    public var showsSeparators = true
    public var backgroundColor: UIColor?
    public var headerMode: HeaderMode = .none
    public var footerMode: FooterMode = .none
    public var headerTopPadding: CGFloat?

    public init(appearance: Appearance) { self.appearance = appearance }

    var isGrouped: Bool { appearance == .grouped || appearance == .insetGrouped || appearance == .sidebar }
    var isInset: Bool { appearance == .insetGrouped || appearance == .sidebar }
}

/// An accessory a list cell shows at its trailing edge.
public struct UICellAccessory: Sendable {
    public enum Kind: Sendable { case disclosureIndicator, checkmark, detail, delete, insert, reorder, multiselect, label(String), outlineDisclosure, popUpMenu, custom }
    public enum DisplayedState: Sendable { case always, whenEditing, whenNotEditing }
    public let kind: Kind
    public var displayed: DisplayedState = .always

    public static func disclosureIndicator(displayed: DisplayedState = .always, options: Any? = nil) -> UICellAccessory { UICellAccessory(kind: .disclosureIndicator, displayed: displayed) }
    public static func checkmark(displayed: DisplayedState = .always, options: Any? = nil) -> UICellAccessory { UICellAccessory(kind: .checkmark, displayed: displayed) }
    public static func detail(displayed: DisplayedState = .always, options: Any? = nil, actionHandler: (() -> Void)? = nil) -> UICellAccessory { UICellAccessory(kind: .detail, displayed: displayed) }
    public static func delete(displayed: DisplayedState = .whenEditing, options: Any? = nil, actionHandler: (() -> Void)? = nil) -> UICellAccessory { UICellAccessory(kind: .delete, displayed: displayed) }
    public static func insert(displayed: DisplayedState = .whenEditing, options: Any? = nil, actionHandler: (() -> Void)? = nil) -> UICellAccessory { UICellAccessory(kind: .insert, displayed: displayed) }
    public static func reorder(displayed: DisplayedState = .whenEditing, options: Any? = nil) -> UICellAccessory { UICellAccessory(kind: .reorder, displayed: displayed) }
    public static func multiselect(displayed: DisplayedState = .whenEditing, options: Any? = nil) -> UICellAccessory { UICellAccessory(kind: .multiselect, displayed: displayed) }
    public static func label(text: String, displayed: DisplayedState = .always, options: Any? = nil) -> UICellAccessory { UICellAccessory(kind: .label(text), displayed: displayed) }
    public static func outlineDisclosure(displayed: DisplayedState = .always, options: Any? = nil, actionHandler: (() -> Void)? = nil) -> UICellAccessory { UICellAccessory(kind: .outlineDisclosure, displayed: displayed) }
}

extension UICollectionViewCompositionalLayout {
    /// A list layout: rows sized by their content in the appearance's frame.
    public class func list(using configuration: UICollectionLayoutListConfiguration) -> UICollectionViewCompositionalLayout {
        UICollectionViewListLayout(configuration: configuration)
    }
}

/// The layout `list(using:)` makes: full-width rows, the inset grouped appearance's cards 16 in,
/// 35 above each section (uikit/collection/list), rows as tall as their list content.
@MainActor
final class UICollectionViewListLayout: UICollectionViewCompositionalLayout {
    let listConfiguration: UICollectionLayoutListConfiguration
    private var rows: [IndexPath: UICollectionViewLayoutAttributes] = [:]
    private var supplementary: [String: [Int: UICollectionViewLayoutAttributes]] = [:]
    private var size = CGSize.zero
    private var appliedBackground = false

    init(configuration: UICollectionLayoutListConfiguration) {
        listConfiguration = configuration
        let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(56)))
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(56)), subitems: [item])
        super.init(section: NSCollectionLayoutSection(group: group))
    }

    override var collectionViewContentSize: CGSize { size }

    override func prepare() {
        rows.removeAll()
        supplementary.removeAll()
        guard let collection = collectionView, let dataSource = collection.dataSource else { size = .zero; return }
        if !appliedBackground {
            appliedBackground = true
            collection.backgroundColor = listConfiguration.backgroundColor ?? (listConfiguration.isGrouped ? .systemGroupedBackground : .systemBackground)
        }
        let width = collection.bounds.width
        let inset: CGFloat = listConfiguration.isInset ? 16 : 0
        var y: CGFloat = 0
        let sections = dataSource.numberOfSections(in: collection)
        for section in 0..<sections {
            let count = dataSource.collectionView(collection, numberOfItemsInSection: section)
            // A supplementary header replaces the 35 pt gap above a grouped section
            // (uikit/collection/listheaders: 44.5 tall for a headline, rows right under it).
            if listConfiguration.headerMode == .supplementary {
                let path = IndexPath(item: 0, section: section)
                let height = collection.selfSizedSupplementary(ofKind: UICollectionView.elementKindSectionHeader, at: path, estimated: CGSize(width: width - 2 * inset, height: 44.5)).height
                let attribute = UICollectionViewLayoutAttributes(forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, with: path)
                attribute.frame = CGRect(x: inset, y: y, width: width - 2 * inset, height: height)
                supplementary[UICollectionView.elementKindSectionHeader, default: [:]][section] = attribute
                y += height
            } else if listConfiguration.isGrouped {
                y += listConfiguration.headerTopPadding ?? 35
            }
            for item in 0..<count {
                let path = IndexPath(item: item, section: section)
                let height = collection.selfSizedItem(at: path, estimated: CGSize(width: width - 2 * inset, height: 56)).height
                let attribute = UICollectionViewLayoutAttributes(forCellWith: path)
                attribute.frame = CGRect(x: inset, y: y, width: width - 2 * inset, height: height)
                attribute.listPosition = (first: item == 0, last: item == count - 1)
                attribute.listAppearance = listConfiguration.appearance
                rows[path] = attribute
                y += height
            }
            if listConfiguration.footerMode == .supplementary {
                let path = IndexPath(item: 0, section: section)
                let height = collection.selfSizedSupplementary(ofKind: UICollectionView.elementKindSectionFooter, at: path, estimated: CGSize(width: width - 2 * inset, height: 35)).height
                let attribute = UICollectionViewLayoutAttributes(forSupplementaryViewOfKind: UICollectionView.elementKindSectionFooter, with: path)
                attribute.frame = CGRect(x: inset, y: y, width: width - 2 * inset, height: height)
                supplementary[UICollectionView.elementKindSectionFooter, default: [:]][section] = attribute
                y += height
            }
        }
        size = CGSize(width: width, height: y)
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        let items = rows.values.filter { $0.frame.intersects(rect) }.sorted { $0.indexPath < $1.indexPath }
        let extras = supplementary.values.flatMap { $0.values }.filter { $0.frame.intersects(rect) }.sorted { $0.indexPath < $1.indexPath }
        return items + extras
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? { rows[indexPath] }
    override func layoutAttributesForSupplementaryView(ofKind kind: String, at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? { supplementary[kind]?[indexPath.section] }
}

/// A collection view cell that provides list features and default styling.
@MainActor
open class UICollectionViewListCell: UICollectionViewCell {
    open var accessories: [UICellAccessory] = [] { didSet { setNeedsLayout(); setNeedsDisplay() } }
    open var indentationLevel = 0 { didSet { setNeedsLayout() } }
    open var indentationWidth: CGFloat = 10
    open var indentsAccessories = true
    var listPosition: (first: Bool, last: Bool) = (true, true)
    var listAppearance: UICollectionLayoutListConfiguration.Appearance = .plain

    public required init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
    }

    /// The list content configuration a list cell starts from: body text over subheadline
    /// secondary text on the list's metrics (`UIListContentConfiguration.listMetrics`).
    open func defaultContentConfiguration() -> UIListContentConfiguration {
        switch supplementaryKind {
        case UICollectionView.elementKindSectionHeader?: return .groupedHeader()
        case UICollectionView.elementKindSectionFooter?: return .groupedFooter()
        default:
            var configuration = UIListContentConfiguration.subtitleCell()
            configuration.listMetrics = true
            return configuration
        }
    }

    open override func apply(_ layoutAttributes: UICollectionViewLayoutAttributes) {
        super.apply(layoutAttributes)
        if let position = layoutAttributes.listPosition { listPosition = position }
        if let appearance = layoutAttributes.listAppearance { listAppearance = appearance }
        setNeedsLayout()
        setNeedsDisplay()
    }

    /// The accessory's box: the disclosure chevron 10.5 × 14 in a 14 pt box ending 16 from the
    /// trailing edge, the checkmark 19 × 18 ending 18.5 in.
    private var accessorySize: CGSize {
        guard let accessory = accessories.first(where: { $0.displayed != .whenEditing }) else { return .zero }
        switch accessory.kind {
        case .disclosureIndicator, .outlineDisclosure: return CGSize(width: 14, height: 14)
        case .checkmark: return CGSize(width: 19, height: 18)
        case .detail: return CGSize(width: 22, height: 22)
        case .label(let text): return CGSize(width: UILabel.measuredWidth(of: text, font: .preferredFont(forTextStyle: .body)), height: 24.5)
        default: return .zero
        }
    }

    private var accessoryTrailingInset: CGFloat {
        guard let accessory = accessories.first(where: { $0.displayed != .whenEditing }) else { return 0 }
        if case .checkmark = accessory.kind { return 18.5 }
        return 16
    }

    open override func layoutSubviews() {
        super.layoutSubviews()
        let accessory = accessorySize
        let contentWidth = accessory.width > 0 ? bounds.width - accessory.width - accessoryTrailingInset : bounds.width
        contentView.frame = CGRect(x: CGFloat(indentationLevel) * indentationWidth, y: 0, width: contentWidth - CGFloat(indentationLevel) * indentationWidth, height: bounds.height)
    }

    open override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        // The row is as tall as its content view's fit for the width less the accessory.
        let attributes = UICollectionViewLayoutAttributes(forCellWith: layoutAttributes.indexPath)
        let accessory = accessorySize
        let contentWidth = accessory.width > 0 ? layoutAttributes.frame.width - accessory.width - accessoryTrailingInset : layoutAttributes.frame.width
        let height = configuredContent?.view.sizeThatFits(CGSize(width: contentWidth, height: .greatestFiniteMagnitude)).height ?? 44
        // Rows are at least 44; headers and footers are exactly their content (a footer is 35).
        let floor: CGFloat = supplementaryKind == nil ? 44 : 0
        attributes.frame = CGRect(origin: layoutAttributes.frame.origin, size: CGSize(width: layoutAttributes.frame.width, height: max(floor, height)))
        return attributes
    }

    override func drawContent(into list: inout DisplayList, context: PaintContext, style userStyle: UIUserInterfaceStyle) {
        guard supplementaryKind == nil else { return }   // headers and footers: text on the ground, no card
        let rect = context.absoluteRect(CGRect(origin: .zero, size: bounds.size))
        let inset = listAppearance == .insetGrouped || listAppearance == .sidebar
        // The card (or the plain row) in the cell's grouped background colour, selected in grey.
        let fill = (isSelected || isHighlighted) ? UIColor.systemGray4.rgba(for: userStyle) : (backgroundConfiguration?.backgroundColor ?? (inset || listAppearance == .grouped ? UIColor.secondarySystemGroupedBackground : UIColor.systemBackground)).rgba(for: userStyle)
        if inset {
            let radius = UITableView.cardCornerRadius
            list.append(.fillPath(Path(roundedRect: rect, cornerRadii: RectangleCornerRadii(
                topLeading: listPosition.first ? radius : 0, bottomLeading: listPosition.last ? radius : 0,
                bottomTrailing: listPosition.last ? radius : 0, topTrailing: listPosition.first ? radius : 0), style: .continuous), fill))
        } else {
            list.append(.fillRect(rect, fill))
        }
        let ink = UIColor.tertiaryLabel.rgba(for: userStyle)
        let contentRight = contentView.frame.maxX
        if let accessory = accessories.first(where: { $0.displayed != .whenEditing }) {
            switch accessory.kind {
            case .disclosureIndicator, .outlineDisclosure:
                let box = context.absoluteRect(CGRect(x: contentRight + 2, y: ((bounds.height - 14) / 2).rounded(), width: 10.5, height: 14))
                var chevron = Path()
                chevron.move(to: CGPoint(x: box.minX + 2, y: box.minY + 1.5))
                chevron.addLine(to: CGPoint(x: box.maxX - 1.5, y: box.midY))
                chevron.addLine(to: CGPoint(x: box.minX + 2, y: box.maxY - 1.5))
                list.append(.strokePath(chevron, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round), ink))
            case .checkmark:
                let box = context.absoluteRect(CGRect(x: contentRight + 2.5, y: ((bounds.height - 18) / 2 * 2).rounded() / 2, width: 19, height: 18))
                var mark = Path()
                mark.move(to: CGPoint(x: box.minX + 1.5, y: box.midY + 1))
                mark.addLine(to: CGPoint(x: box.minX + 7, y: box.maxY - 2))
                mark.addLine(to: CGPoint(x: box.maxX - 1.5, y: box.minY + 2))
                list.append(.strokePath(mark, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round), tintColor.rgba(for: userStyle)))
            case .label(let text):
                let font = UIFont.preferredFont(forTextStyle: .body)
                let layout = UIKitScene.shared.textEngine.layout([StyledRun(text, font: font.resolved)], options: TextLayoutOptions(lineLimit: 1), width: nil)
                if let line = layout.lines.first {
                    let baseline = context.origin.y + ((bounds.height - font.lineHeight) / 2).rounded() + font.ascender
                    for fragment in line.fragments {
                        list.append(.drawText(fragment.text, DisplayFont(font.resolved), origin: CGPoint(x: context.origin.x + contentRight + fragment.x, y: baseline), UIColor.secondaryLabel.rgba(for: userStyle)))
                    }
                }
            default: break
            }
        }
        // The separator: 1 pt at the bottom, 16 in from both edges of the card, between rows only.
        if !listPosition.last {
            let line = context.absoluteRect(CGRect(x: 16, y: bounds.height - 1, width: bounds.width - 32, height: 1))
            list.append(.fillRect(line, UIColor.separator.rgba(for: userStyle)))
        }
    }
}

extension UILabel {
    /// The width of `text` in `font` on the scene's engine, rounded up to the pixel.
    static func measuredWidth(of text: String, font: UIFont) -> CGFloat {
        let layout = UIKitScene.shared.textEngine.layout([StyledRun(text, font: font.resolved)], options: TextLayoutOptions(lineLimit: 1), width: nil)
        return layout.size.width.roundedUp(to: UIScreen.main.scale)
    }
}
