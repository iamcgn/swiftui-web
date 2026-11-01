// List layouts (Docs/elements/UIKit/CollectionView.md): `UICollectionViewCompositionalLayout.list(using:)`
// lays list cells out as a table would (the inset grouped appearance's cards 16 in with 26 pt
// corners, 35 pt gaps, rows sized by their list content: 56 for one line, 79.5 with a
// secondary text), and `UICollectionViewListCell` draws the card, the separator and its
// accessories. Measured on the iPhone SE simulator (uikit/collection/list).
#if os(WASI)
import WebFoundation
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
    var isSidebar: Bool { appearance == .sidebar || appearance == .sidebarPlain }
}

/// An accessory a list cell shows at its trailing edge.
public struct UICellAccessory: Sendable {
    public enum Kind: Sendable { case disclosureIndicator, checkmark, detail, delete, insert, reorder, multiselect, label(String), outlineDisclosure, popUpMenu, custom }
    public enum DisplayedState: Sendable { case always, whenEditing, whenNotEditing }
    public let kind: Kind
    public var displayed: DisplayedState = .always
    /// An outline disclosure's options (`outlineDisclosure(displayed:options:actionHandler:)`).
    public var outlineOptions = OutlineDisclosureOptions()
    /// Called when an outline disclosure toggles.
    public var actionHandler: (@Sendable () -> Void)?

    /// How an outline disclosure behaves: a header's whole row toggles, a cell's chevron alone
    /// does (the row selects as usual); automatic is the header style.
    public struct OutlineDisclosureOptions: Sendable {
        public enum Style: Int, Sendable { case automatic = 0, header, cell }
        public var style: Style
        public var isHidden: Bool
        public var reservedLayoutWidth: CGFloat?
        public var tintColor: UIColor?
        public init(style: Style = .automatic, isHidden: Bool = false, reservedLayoutWidth: CGFloat? = nil, tintColor: UIColor? = nil) {
            self.style = style
            self.isHidden = isHidden
            self.reservedLayoutWidth = reservedLayoutWidth
            self.tintColor = tintColor
        }
        var togglesWholeRow: Bool { style != .cell }
    }

    public static func disclosureIndicator(displayed: DisplayedState = .always, options: Any? = nil) -> UICellAccessory { UICellAccessory(kind: .disclosureIndicator, displayed: displayed) }
    public static func checkmark(displayed: DisplayedState = .always, options: Any? = nil) -> UICellAccessory { UICellAccessory(kind: .checkmark, displayed: displayed) }
    public static func detail(displayed: DisplayedState = .always, options: Any? = nil, actionHandler: (() -> Void)? = nil) -> UICellAccessory { UICellAccessory(kind: .detail, displayed: displayed) }
    public static func delete(displayed: DisplayedState = .whenEditing, options: Any? = nil, actionHandler: (() -> Void)? = nil) -> UICellAccessory { UICellAccessory(kind: .delete, displayed: displayed) }
    public static func insert(displayed: DisplayedState = .whenEditing, options: Any? = nil, actionHandler: (() -> Void)? = nil) -> UICellAccessory { UICellAccessory(kind: .insert, displayed: displayed) }
    public static func reorder(displayed: DisplayedState = .whenEditing, options: Any? = nil) -> UICellAccessory { UICellAccessory(kind: .reorder, displayed: displayed) }
    public static func multiselect(displayed: DisplayedState = .whenEditing, options: Any? = nil) -> UICellAccessory { UICellAccessory(kind: .multiselect, displayed: displayed) }
    public static func label(text: String, displayed: DisplayedState = .always, options: Any? = nil) -> UICellAccessory { UICellAccessory(kind: .label(text), displayed: displayed) }
    public static func outlineDisclosure(displayed: DisplayedState = .always, options: OutlineDisclosureOptions = OutlineDisclosureOptions(), actionHandler: (@Sendable () -> Void)? = nil) -> UICellAccessory {
        var accessory = UICellAccessory(kind: .outlineDisclosure, displayed: displayed)
        accessory.outlineOptions = options
        accessory.actionHandler = actionHandler
        return accessory
    }
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
    /// Where each section ends (a plain header pins until the next section pushes it away).
    private var sectionEnds: [Int: CGFloat] = [:]
    /// Heights measured from cells and supplementaries that appeared; rows out of view are laid
    /// out at the estimate (56, headers 44.5, footers 35) until then, as UIKit sizes lazily
    /// (uikit/collection/plainlist: no cell exists for a row below the fold).
    private var measuredRows: [IndexPath: CGFloat] = [:]
    private var measuredSupplementary: [String: CGFloat] = [:]

    func needsMeasurement(of path: IndexPath) -> Bool { measuredRows[path] == nil }
    func needsMeasurement(ofKind kind: String, section: Int) -> Bool { measuredSupplementary[kind + "#" + "\(section)"] == nil }

    /// Records a row's measured height; true when it changes the row's laid-out height.
    func recordMeasured(_ height: CGFloat, at path: IndexPath) -> Bool {
        measuredRows[path] = height
        return rows[path].map { $0.frame.height != height } ?? false
    }

    func recordMeasured(_ height: CGFloat, kind: String, section: Int) -> Bool {
        measuredSupplementary[kind + "#" + "\(section)"] = height
        return supplementary[kind]?[section].map { $0.frame.height != height } ?? false
    }

    override func invalidateLayout() {
        measuredRows.removeAll()
        measuredSupplementary.removeAll()
        super.invalidateLayout()
    }
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
        sectionEnds.removeAll()
        guard let collection = collectionView, let dataSource = collection.dataSource else { size = .zero; return }
        if !appliedBackground {
            appliedBackground = true
            // The sidebar appearance sits on the secondary background (uikit/collection/sidebar).
            let ground: UIColor = listConfiguration.appearance == .sidebar ? .secondarySystemBackground : listConfiguration.isGrouped ? .systemGroupedBackground : .systemBackground
            collection.backgroundColor = listConfiguration.backgroundColor ?? ground
        }
        let width = collection.bounds.width
        // The sidebar appearances' rows sit 16 in like the inset grouped cards (without the
        // card); a plain sidebar's headers span the width (uikit/collection/sidebarplain).
        let inset: CGFloat = listConfiguration.isInset || listConfiguration.appearance == .sidebarPlain ? 16 : 0
        let headerInset: CGFloat = listConfiguration.appearance == .sidebarPlain ? 0 : inset
        var y: CGFloat = 0
        let sections = dataSource.numberOfSections(in: collection)
        // Only what the bounds show is measured now; the rest takes the estimate until it appears.
        let window = collection.bounds
        func rowHeight(_ path: IndexPath, estimate: CGFloat) -> CGFloat {
            if let measured = measuredRows[path] { return measured }
            let inset = isHeaderItem(path) ? headerInset : inset
            guard CGRect(x: inset, y: y, width: width - 2 * inset, height: estimate).intersects(window) else { return estimate }
            let height = collection.selfSizedItem(at: path, estimated: CGSize(width: width - 2 * inset, height: estimate)).height
            measuredRows[path] = height
            return height
        }
        func supplementaryHeight(_ kind: String, _ path: IndexPath, estimate: CGFloat) -> CGFloat {
            if let measured = measuredSupplementary[kind + "#" + "\(path.section)"] { return measured }
            guard CGRect(x: inset, y: y, width: width - 2 * inset, height: estimate).intersects(window) else { return estimate }
            let height = collection.selfSizedSupplementary(ofKind: kind, at: path, estimated: CGSize(width: width - 2 * inset, height: estimate)).height
            measuredSupplementary[kind + "#" + "\(path.section)"] = height
            return height
        }
        for section in 0..<sections {
            let count = dataSource.collectionView(collection, numberOfItemsInSection: section)
            // A supplementary header replaces the 35 pt gap above a grouped section
            // (uikit/collection/listheaders: 44.5 tall for a headline, rows right under it); a
            // first-item header does too, with 17.5 between sections (uikit/collection/firstitem).
            if listConfiguration.headerMode == .firstItemInSection {
                // The sidebar's sections start at the top and sit 10 apart; the plain sidebar's
                // headers 22 down and 30 after the last row (uikit/collection/sidebar, sidebarplain).
                switch listConfiguration.appearance {
                case .sidebar: if section > 0 { y += 10 }
                case .sidebarPlain: y += section > 0 ? 30 : 22
                default: if section > 0 { y += 17.5 }
                }
            } else if listConfiguration.headerMode == .supplementary {
                // A plain header sits 22 below what precedes it (uikit/collection/plainlist); a
                // grouped one directly after, plus `headerTopPadding` (uikit/collection/listpadding).
                switch listConfiguration.appearance {
                case .sidebar: y += listConfiguration.headerTopPadding ?? (section > 0 ? 10 : 0)
                case .sidebarPlain: y += listConfiguration.headerTopPadding ?? (section > 0 ? 30 : 22)
                default: y += listConfiguration.isGrouped ? (listConfiguration.headerTopPadding ?? 0) : 22
                }
                let path = IndexPath(item: 0, section: section)
                let height = supplementaryHeight(UICollectionView.elementKindSectionHeader, path, estimate: 44.5)
                let attribute = UICollectionViewLayoutAttributes(forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, with: path)
                attribute.frame = CGRect(x: headerInset, y: y, width: width - 2 * headerInset, height: height)
                attribute.listAppearance = listConfiguration.appearance
                supplementary[UICollectionView.elementKindSectionHeader, default: [:]][section] = attribute
                y += height
            } else if listConfiguration.appearance == .sidebar {
                if section > 0 { y += 10 }
            } else if listConfiguration.appearance == .sidebarPlain {
                y += section > 0 ? 30 : 22
            } else if listConfiguration.isGrouped {
                y += listConfiguration.headerTopPadding ?? 35
            }
            for item in 0..<count {
                let path = IndexPath(item: item, section: section)
                let header = isHeaderItem(path)
                let x = header ? headerInset : inset
                let height = rowHeight(path, estimate: 56)
                let attribute = UICollectionViewLayoutAttributes(forCellWith: path)
                attribute.frame = CGRect(x: x, y: y, width: width - 2 * x, height: height)
                // A plain sidebar's rows start 8 below their header (uikit/collection/sidebarplain).
                if header, listConfiguration.appearance == .sidebarPlain { y += 8 }
                let firstRow = listConfiguration.headerMode == .firstItemInSection ? 1 : 0
                attribute.listPosition = (first: item == firstRow, last: item == count - 1)
                attribute.listAppearance = listConfiguration.appearance
                // Separators run between rows; a plain section's last row keeps its own unless a
                // footer follows (uikit/collection/plainlist, plainfooters); the sidebar has
                // none, the plain sidebar one under every row.
                switch listConfiguration.appearance {
                case .sidebar: attribute.listSeparatorAfter = false
                case .sidebarPlain: attribute.listSeparatorAfter = !header
                default: attribute.listSeparatorAfter = item < count - 1 || (!listConfiguration.isGrouped && listConfiguration.footerMode != .supplementary)
                }
                rows[path] = attribute
                y += height
            }
            if listConfiguration.footerMode == .supplementary {
                let path = IndexPath(item: 0, section: section)
                let height = supplementaryHeight(UICollectionView.elementKindSectionFooter, path, estimate: 35)
                let attribute = UICollectionViewLayoutAttributes(forSupplementaryViewOfKind: UICollectionView.elementKindSectionFooter, with: path)
                attribute.frame = CGRect(x: inset, y: y, width: width - 2 * inset, height: height)
                supplementary[UICollectionView.elementKindSectionFooter, default: [:]][section] = attribute
                y += height
            }
            sectionEnds[section] = y
        }
        size = CGSize(width: width, height: y)
    }

    /// Plain-appearance headers pin to the visible top while their section scrolls under them,
    /// pushed away by the next section (uikit/collection/plainlist); grouped ones scroll.
    private var pinsHeaders: Bool { !listConfiguration.isGrouped && listConfiguration.headerMode == .supplementary }

    private func headerAttributes(for section: Int) -> UICollectionViewLayoutAttributes? {
        guard let natural = supplementary[UICollectionView.elementKindSectionHeader]?[section] else { return nil }
        guard pinsHeaders, let collection = collectionView else { return natural }
        let attribute = UICollectionViewLayoutAttributes(forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, with: natural.indexPath)
        let top = collection.contentOffset.y + collection.adjustedContentInset.top
        let end = sectionEnds[section] ?? natural.frame.maxY
        var frame = natural.frame
        frame.origin.y = min(max(natural.frame.minY, top), end - natural.frame.height)
        attribute.frame = frame
        attribute.zIndex = frame.minY < top ? -1 : 1
        attribute.listHeaderPinned = frame.minY > natural.frame.minY
        attribute.listAppearance = listConfiguration.appearance
        return attribute
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        let items = rows.values.filter { $0.frame.intersects(rect) }.sorted { $0.indexPath < $1.indexPath }
        var extras: [UICollectionViewLayoutAttributes] = []
        for (kind, bySection) in supplementary {
            for (section, attribute) in bySection {
                let placed = kind == UICollectionView.elementKindSectionHeader ? (headerAttributes(for: section) ?? attribute) : attribute
                if placed.frame.intersects(rect) { extras.append(placed) }
            }
        }
        extras.sort { $0.indexPath < $1.indexPath }
        return items + extras
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? { rows[indexPath] }
    override func layoutAttributesForSupplementaryView(ofKind kind: String, at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        kind == UICollectionView.elementKindSectionHeader ? headerAttributes(for: indexPath.section) : supplementary[kind]?[indexPath.section]
    }

    /// Whether the item is its section's header (`headerMode == .firstItemInSection`).
    func isHeaderItem(_ indexPath: IndexPath) -> Bool { listConfiguration.headerMode == .firstItemInSection && indexPath.item == 0 }
}

/// A collection view cell that provides list features and default styling.
@MainActor
open class UICollectionViewListCell: UICollectionViewCell {
    /// No archive to decode on the web: nil, as for an archive this class cannot read.
    public required init?(coder: NSCoder) { return nil }

    open var accessories: [UICellAccessory] = [] { didSet { setNeedsLayout(); setNeedsDisplay() } }
    open var indentationLevel = 0 { didSet { setNeedsLayout() } }
    /// An outline parent's state: the disclosure chevron points down when expanded.
    var isOutlineExpanded = false { didSet { setNeedsDisplay() } }
    /// A plain header held at the visible top: it paints the list's ground under itself and a
    /// short fade below, where UIKit blurs the rows passing under (a scroll pocket).
    var isPinnedHeader = false { didSet { if isPinnedHeader != oldValue { setNeedsDisplay() } } }
    open var indentationWidth: CGFloat = 10
    open var indentsAccessories = true
    var listPosition: (first: Bool, last: Bool) = (true, true)
    var listAppearance: UICollectionLayoutListConfiguration.Appearance = .plain
    var drawsSeparator = false
    /// Dequeued as its section's header (`headerMode == .firstItemInSection`): styled like a
    /// supplementary header, no card.
    var isHeaderItem = false
    /// Whether the cell stands for a header or footer rather than a row.
    var isHeaderOrFooter: Bool { supplementaryKind != nil || isHeaderItem }

    public required init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
    }

    /// The list content configuration a list cell starts from: body text over subheadline
    /// secondary text on the list's metrics (`UIListContentConfiguration.listMetrics`).
    open func defaultContentConfiguration() -> UIListContentConfiguration {
        let sidebar = listAppearance == .sidebar || listAppearance == .sidebarPlain
        switch supplementaryKind {
        case UICollectionView.elementKindSectionHeader?: return sidebar ? .sidebarHeader() : .groupedHeader()
        case UICollectionView.elementKindSectionFooter?: return .groupedFooter()
        case nil where isHeaderItem: return sidebar ? .sidebarHeader() : .groupedHeader()
        default:
            if sidebar { return .sidebarSubtitleCell() }
            var configuration = UIListContentConfiguration.subtitleCell()
            configuration.listMetrics = true
            return configuration
        }
    }

    /// The sidebar presets' margins for this list: a plain sidebar's rows start 8 in (their
    /// text level with the full-width header's at 24) and its headers 24 in; the sidebar's
    /// rows and headers 16 (uikit/collection/sidebar, sidebarplain).
    func sidebarMargins(for configuration: UIListContentConfiguration) -> UIEdgeInsets {
        let header = configuration.listRole == .header
        switch listAppearance {
        case .sidebarPlain: return UIEdgeInsets(top: 14, left: header ? 24 : 8, bottom: 13.5, right: header ? 24 : 16)
        default: return UIEdgeInsets(top: 14, left: 16, bottom: 13.5, right: 16)
        }
    }

    open override var contentConfiguration: (any UIContentConfiguration)? {
        didSet {
            // A sidebar preset takes the list's margins (unless the app set its own).
            if let list = contentConfiguration as? UIListContentConfiguration, list.sidebar, !list.tableMetrics, list.usesPresetMargins,
               listAppearance == .sidebar || listAppearance == .sidebarPlain {
                var adjusted = list
                adjusted.directionalLayoutMargins = sidebarMargins(for: list)
                adjusted.usesPresetMargins = false
                contentConfiguration = adjusted
            }
        }
    }

    open override func apply(_ layoutAttributes: UICollectionViewLayoutAttributes) {
        super.apply(layoutAttributes)
        if let position = layoutAttributes.listPosition { listPosition = position }
        if let appearance = layoutAttributes.listAppearance { listAppearance = appearance }
        if let separator = layoutAttributes.listSeparatorAfter { drawsSeparator = separator }
        isPinnedHeader = layoutAttributes.listHeaderPinned
        setNeedsLayout()
        setNeedsDisplay()
    }

    /// The accessory's box: the disclosure chevron 10.5 × 14 in a 14 pt box ending 16 from the
    /// trailing edge, the checkmark 19 × 18 ending 18.5 in.
    private var accessorySize: CGSize {
        guard let accessory = accessories.first(where: { $0.displayed != .whenEditing }) else { return .zero }
        switch accessory.kind {
        case .outlineDisclosure where accessory.outlineOptions.isHidden:
            return accessory.outlineOptions.reservedLayoutWidth.map { CGSize(width: $0, height: 14) } ?? .zero
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
        // The row is as tall as its content view's fit for the width less the accessory (a
        // hosted configuration's fit is at least 56: ios/representable/hostingcollection).
        updateConfigurationIfNeeded()
        let attributes = UICollectionViewLayoutAttributes(forCellWith: layoutAttributes.indexPath)
        let accessory = accessorySize
        let contentWidth = accessory.width > 0 ? layoutAttributes.frame.width - accessory.width - accessoryTrailingInset : layoutAttributes.frame.width
        let height = configuredContent?.view.sizeThatFits(CGSize(width: contentWidth, height: .greatestFiniteMagnitude)).height ?? 44
        // Rows are at least 44; headers and footers are exactly their content (a footer is 35).
        let floor: CGFloat = isHeaderOrFooter ? 0 : 44
        attributes.frame = CGRect(origin: layoutAttributes.frame.origin, size: CGSize(width: layoutAttributes.frame.width, height: max(floor, height)))
        return attributes
    }

    /// Whether the list is a sidebar appearance (no card, its own header chevron).
    var isSidebarAppearance: Bool { listAppearance == .sidebar || listAppearance == .sidebarPlain }

    /// A sidebar header's outline chevron: a 2 pt stroke 12 × 6.5 pointing down when expanded,
    /// 6.5 × 11.5 pointing right when closed, centred 23 from the trailing edge (31 for a
    /// plain sidebar's full-width header), in the secondary label colour.
    private func drawSidebarChevron(into list: inout DisplayList, context: PaintContext, style userStyle: UIUserInterfaceStyle, tint: UIColor?) {
        let cx = context.origin.x + bounds.width - (listAppearance == .sidebarPlain ? 31 : 23)
        let cy = context.origin.y + (bounds.height / 2).rounded()
        var chevron = Path()
        if isOutlineExpanded {
            chevron.move(to: (CGPoint(x: cx - 5, y: cy - 2)))
            chevron.addLine(to: (CGPoint(x: cx, y: cy + 2.5)))
            chevron.addLine(to: (CGPoint(x: cx + 5, y: cy - 2)))
        } else {
            chevron.move(to: (CGPoint(x: cx - 2.25, y: cy - 4.75)))
            chevron.addLine(to: (CGPoint(x: cx + 2.25, y: cy)))
            chevron.addLine(to: (CGPoint(x: cx - 2.25, y: cy + 4.75)))
        }
        list.append(.strokePath(chevron, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round), (tint ?? UIColor.secondaryLabel).rgba(for: userStyle)))
    }

    override func drawContent(into list: inout DisplayList, context: PaintContext, style userStyle: UIUserInterfaceStyle) {
        if isSidebarAppearance {
            // No card: the row sits on the ground, selected in grey; a header's outline
            // disclosure is the small chevron; the plain sidebar's rows end in a faint separator
            // from the text to 8 before the trailing edge (uikit/collection/sidebarplain).
            if isSelected || isHighlighted, !isHeaderOrFooter {
                list.append(.fillPath(Path(roundedRect: context.absoluteRect(CGRect(origin: .zero, size: bounds.size)), cornerRadius: 10), UIColor.systemGray4.rgba(for: userStyle)))
            }
            if let accessory = accessories.first(where: { $0.displayed != .whenEditing }), case .outlineDisclosure = accessory.kind, !accessory.outlineOptions.isHidden {
                drawSidebarChevron(into: &list, context: context, style: userStyle, tint: accessory.outlineOptions.tintColor)
            }
            if drawsSeparator {
                let left = (contentConfiguration as? UIListContentConfiguration)?.directionalLayoutMargins.left ?? 8
                let line = context.absoluteRect(CGRect(x: left, y: bounds.height - 1, width: bounds.width - left - 8, height: 1))
                list.append(.fillRect(line, UIColor.separator.rgba(for: userStyle).multiplyingAlpha(by: 0.42)))
            }
            return
        }
        if isHeaderOrFooter {
            // Headers and footers: text on the ground, no card. A pinned plain header covers the
            // rows under it with the ground and a 16 pt fade (uikit/collection/plainlist scroll).
            if isPinnedHeader {
                // The ground under the header, then the pocket's scrim: black at 15 % at the
                // top easing to nothing 60 pt down (the table's pinned header measures the same).
                let ground = (listAppearance == .plain ? UIColor.systemBackground : UIColor.systemGroupedBackground).rgba(for: userStyle)
                let rect = context.absoluteRect(CGRect(origin: .zero, size: bounds.size))
                list.append(.fillRect(rect, ground))
                let fade = context.absoluteRect(CGRect(x: 0, y: bounds.height, width: bounds.width, height: 16))
                let fadeGradient = DisplayGradient(kind: .linear(start: CGPoint(x: fade.minX, y: fade.minY), end: CGPoint(x: fade.minX, y: fade.maxY)),
                                                   stops: [DisplayGradient.Stop(location: 0, color: ground), DisplayGradient.Stop(location: 1, color: ground.multiplyingAlpha(by: 0))])
                list.append(.fillGradient(Path(fade), fadeGradient))
                let top = context.absoluteRect(CGRect(x: 0, y: 0, width: bounds.width, height: 60))
                let ink: RGBA = userStyle == .dark ? RGBA(r: 255, g: 255, b: 255) : RGBA(r: 0, g: 0, b: 0)
                let stops = [(0.0, 0.15), (0.25, 0.106), (0.5, 0.065), (0.75, 0.028), (1.0, 0.0)].map { DisplayGradient.Stop(location: $0.0, color: ink.multiplyingAlpha(by: $0.1)) }
                list.append(.fillGradient(Path(top), DisplayGradient(kind: .linear(start: CGPoint(x: top.minX, y: top.minY), end: CGPoint(x: top.minX, y: top.maxY)), stops: stops)))
            }
            return
        }
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
            case .outlineDisclosure where accessory.outlineOptions.isHidden:
                break
            case .disclosureIndicator, .outlineDisclosure:
                var chevron = Path()
                if case .outlineDisclosure = accessory.kind, isOutlineExpanded {
                    // Expanded: the chevron points down (14 wide, 10.5 tall in the same box).
                    let box = context.absoluteRect(CGRect(x: contentRight, y: ((bounds.height - 10.5) / 2).rounded(), width: 14, height: 10.5))
                    chevron.move(to: CGPoint(x: box.minX + 1.5, y: box.minY + 2))
                    chevron.addLine(to: CGPoint(x: box.midX, y: box.maxY - 1.5))
                    chevron.addLine(to: CGPoint(x: box.maxX - 1.5, y: box.minY + 2))
                } else {
                    let box = context.absoluteRect(CGRect(x: contentRight + 2, y: ((bounds.height - 14) / 2).rounded(), width: 10.5, height: 14))
                    chevron.move(to: CGPoint(x: box.minX + 2, y: box.minY + 1.5))
                    chevron.addLine(to: CGPoint(x: box.maxX - 1.5, y: box.midY))
                    chevron.addLine(to: CGPoint(x: box.minX + 2, y: box.maxY - 1.5))
                }
                let chevronInk: RGBA
                if case .outlineDisclosure = accessory.kind, let tint = accessory.outlineOptions.tintColor { chevronInk = tint.rgba(for: userStyle) } else { chevronInk = ink }
                list.append(.strokePath(chevron, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round), chevronInk))
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
        // The separator: 1 pt at the bottom, 16 in from both edges of the card (an indented
        // outline child's starts with its content: 42 in the card at one level), between rows;
        // a plain section's last row keeps its separator (uikit/collection/plainlist).
        if drawsSeparator {
            let left = 16 + CGFloat(indentationLevel) * indentationWidth
            let line = context.absoluteRect(CGRect(x: left, y: bounds.height - 1, width: bounds.width - left - 16, height: 1))
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
