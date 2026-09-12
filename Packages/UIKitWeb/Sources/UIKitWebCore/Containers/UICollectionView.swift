// UICollectionView with a flow layout (Docs/elements/UIKit/CollectionView.md): items placed by
// a layout object over the scroll view, cells for the items in view from a reuse pool, selection
// by tap. The flow layout's rules are measured on the iPhone SE simulator (iOS 26):
// `uikit/collection/grid`, `horizontal`, `sized`.

#if os(WASI)
import FoundationEssentials
#else
import Foundation
#endif

/// The layout attributes of one element in a collection view.
@MainActor
open class UICollectionViewLayoutAttributes {
    /// A list row's place in its section and the list's appearance (Containers/ListLayout.swift).
    var listPosition: (first: Bool, last: Bool)?
    /// A plain list header held at the visible top by scrolling (it paints its ground).
    var listHeaderPinned = false
    var listAppearance: UICollectionLayoutListConfiguration.Appearance?
    /// The orthogonally scrolling section this item belongs to (Containers/CompositionalLayout.swift).
    var orthogonalSection: Int?
    public enum Category { case cell, supplementaryView, decorationView }
    open var frame: CGRect
    open var indexPath: IndexPath
    open var zIndex = 0
    open var alpha: CGFloat = 1
    open var isHidden = false
    open var transform = CGAffineTransform.identity
    public let representedElementCategory: Category
    public let representedElementKind: String?

    public init(forCellWith indexPath: IndexPath) {
        self.indexPath = indexPath
        frame = .zero
        representedElementCategory = .cell
        representedElementKind = nil
    }

    public init(forSupplementaryViewOfKind kind: String, with indexPath: IndexPath) {
        self.indexPath = indexPath
        frame = .zero
        representedElementCategory = .supplementaryView
        representedElementKind = kind
    }

    public init(forDecorationViewOfKind kind: String, with indexPath: IndexPath) {
        self.indexPath = indexPath
        frame = .zero
        representedElementCategory = .decorationView
        representedElementKind = kind
    }

    open var center: CGPoint {
        get { CGPoint(x: frame.midX, y: frame.midY) }
        set { frame.origin = CGPoint(x: newValue.x - frame.width / 2, y: newValue.y - frame.height / 2) }
    }
    open var size: CGSize {
        get { frame.size }
        set { frame.size = newValue }
    }
}

/// An abstract base class for generating layout information for a collection view.
@MainActor
open class UICollectionViewLayout {
    public internal(set) weak var collectionView: UICollectionView?

    public init() {}

    /// Computes the layout; called before the attributes are asked for.
    open func prepare() {}
    open var collectionViewContentSize: CGSize { .zero }
    open func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? { nil }
    open func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? { nil }
    open func layoutAttributesForSupplementaryView(ofKind kind: String, at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? { nil }
    open func layoutAttributesForDecorationView(ofKind kind: String, at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? { nil }
    open func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool { false }
    open func invalidateLayout() { collectionView?.setNeedsReload() }

    /// Decoration views the layout makes itself (a section background), by element kind.
    var registeredDecorations: [String: () -> UICollectionReusableView] = [:]
    open func register(_ viewClass: AnyClass?, forDecorationViewOfKind kind: String) {
        guard let type = viewClass as? UICollectionReusableView.Type else { registeredDecorations[kind] = nil; return }
        registeredDecorations[kind] = { type.init(frame: .zero) }
    }
}

/// The methods a flow layout's delegate implements to size items and space sections.
@MainActor
public protocol UICollectionViewDelegateFlowLayout: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumInteritemSpacingForSectionAt section: Int) -> CGFloat
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForHeaderInSection section: Int) -> CGSize
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForFooterInSection section: Int) -> CGSize
}

extension UICollectionViewDelegateFlowLayout {
    public func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        (collectionViewLayout as? UICollectionViewFlowLayout)?.itemSize ?? CGSize(width: 50, height: 50)
    }
    public func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
        (collectionViewLayout as? UICollectionViewFlowLayout)?.sectionInset ?? .zero
    }
    public func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        (collectionViewLayout as? UICollectionViewFlowLayout)?.minimumLineSpacing ?? 10
    }
    public func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumInteritemSpacingForSectionAt section: Int) -> CGFloat {
        (collectionViewLayout as? UICollectionViewFlowLayout)?.minimumInteritemSpacing ?? 10
    }
    public func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForHeaderInSection section: Int) -> CGSize {
        (collectionViewLayout as? UICollectionViewFlowLayout)?.headerReferenceSize ?? .zero
    }
    public func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForFooterInSection section: Int) -> CGSize {
        (collectionViewLayout as? UICollectionViewFlowLayout)?.footerReferenceSize ?? .zero
    }
}

/// A layout object that organizes items into a grid with optional header and footer views for
/// each section.
@MainActor
open class UICollectionViewFlowLayout: UICollectionViewLayout {
    public enum ScrollDirection: Int, Sendable { case vertical = 0, horizontal }
    public static let automaticSize = CGSize(width: -1, height: -1)

    open var itemSize = CGSize(width: 50, height: 50) { didSet { invalidateLayout() } }
    open var estimatedItemSize = CGSize.zero
    open var minimumLineSpacing: CGFloat = 10 { didSet { invalidateLayout() } }
    open var minimumInteritemSpacing: CGFloat = 10 { didSet { invalidateLayout() } }
    open var scrollDirection: ScrollDirection = .vertical { didSet { invalidateLayout() } }
    open var sectionInset = UIEdgeInsets.zero { didSet { invalidateLayout() } }
    open var headerReferenceSize = CGSize.zero
    open var footerReferenceSize = CGSize.zero
    open var sectionInsetReference = 0
    open var sectionHeadersPinToVisibleBounds = false

    private var attributes: [IndexPath: UICollectionViewLayoutAttributes] = [:]
    /// The headers' and footers' attributes, by kind then section.
    private var supplementary: [String: [Int: UICollectionViewLayoutAttributes]] = [:]
    private var contentSize = CGSize.zero

    open override var collectionViewContentSize: CGSize { contentSize }

    /// Lays every item out: sections in turn, each inset, its items in lines along the scroll
    /// direction's cross axis. Items in a full line spread evenly over the line's free space; a
    /// section's last line keeps the minimum spacing unless the section's items share one size,
    /// when it takes the gap of a full line (uikit/collection/grid, sized).
    open override func prepare() {
        attributes.removeAll()
        supplementary.removeAll()
        guard let collection = collectionView, let dataSource = collection.dataSource else { contentSize = .zero; return }
        let flowDelegate = collection.delegate as? any UICollectionViewDelegateFlowLayout
        let horizontal = scrollDirection == .horizontal
        let bounds = collection.bounds
        var cursor: CGFloat = 0   // along the scroll direction
        var crossExtent: CGFloat = horizontal ? bounds.height : bounds.width
        let sections = dataSource.numberOfSections(in: collection)
        for section in 0..<sections {
            let inset = flowDelegate?.collectionView(collection, layout: self, insetForSectionAt: section) ?? sectionInset
            let lineSpacing = flowDelegate?.collectionView(collection, layout: self, minimumLineSpacingForSectionAt: section) ?? minimumLineSpacing
            let itemSpacing = flowDelegate?.collectionView(collection, layout: self, minimumInteritemSpacingForSectionAt: section) ?? minimumInteritemSpacing
            let count = dataSource.collectionView(collection, numberOfItemsInSection: section)
            // Self-sizing: with an estimated size each cell answers its fitting size (its
            // constraints' compressed fit, uikit/collection/selfsizing); the delegate's size wins.
            let sizes = (0..<count).map { item -> CGSize in
                let path = IndexPath(item: item, section: section)
                if let delegated = flowDelegate?.collectionView(collection, layout: self, sizeForItemAt: path) { return delegated }
                if estimatedItemSize != .zero { return collection.selfSizedItem(at: path, estimated: estimatedItemSize == Self.automaticSize ? itemSize : estimatedItemSize) }
                return itemSize
            }
            // A header spans the cross axis before the section's inset; a footer follows the inset
            // (the reference size's extent along the scroll direction; zero means none).
            let headerSize = flowDelegate?.collectionView(collection, layout: self, referenceSizeForHeaderInSection: section) ?? headerReferenceSize
            let headerExtent = horizontal ? headerSize.width : headerSize.height
            if headerExtent > 0 {
                let attribute = UICollectionViewLayoutAttributes(forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, with: IndexPath(item: 0, section: section))
                attribute.frame = horizontal ? CGRect(x: cursor, y: 0, width: headerExtent, height: bounds.height) : CGRect(x: 0, y: cursor, width: bounds.width, height: headerExtent)
                supplementary[UICollectionView.elementKindSectionHeader, default: [:]][section] = attribute
                cursor += headerExtent
            }
            // The room across the scroll direction for a line of items.
            let available = (horizontal ? bounds.height - inset.top - inset.bottom : bounds.width - inset.left - inset.right)
            func across(_ size: CGSize) -> CGFloat { horizontal ? size.height : size.width }
            func along(_ size: CGSize) -> CGFloat { horizontal ? size.width : size.height }
            // Greedy lines.
            var lines: [[Int]] = []
            var current: [Int] = []
            var used: CGFloat = 0
            for item in 0..<count {
                let extent = across(sizes[item])
                if !current.isEmpty, used + itemSpacing + extent > available + 0.001 {
                    lines.append(current)
                    current = []
                    used = 0
                }
                used += (current.isEmpty ? 0 : itemSpacing) + extent
                current.append(item)
            }
            if !current.isEmpty { lines.append(current) }
            // Items of one size all sit on the grid a full line makes, however few there are:
            // the gap is the full line's (uikit/collection/grid: 9 for three 90 pt items in 288,
            // also between the two items of the second section).
            let uniform = Set(sizes.map { "\($0.width)x\($0.height)" }).count <= 1
            var fullLineGap: CGFloat?
            if uniform, let first = sizes.first {
                let extent = across(first)
                let perLine = extent > 0 ? Int(((available + itemSpacing) / (extent + itemSpacing)).rounded(.down)) : 1
                fullLineGap = perLine > 1 ? max(itemSpacing, (available - CGFloat(perLine) * extent) / CGFloat(perLine - 1)) : itemSpacing
            }
            cursor += horizontal ? inset.left : inset.top
            for (index, line) in lines.enumerated() {
                let isLast = index == lines.count - 1
                let spacing: CGFloat
                if !isLast {
                    spacing = gap(for: line, sizes: sizes, available: available, minimum: itemSpacing, across: across)
                } else {
                    spacing = uniform ? (fullLineGap ?? itemSpacing) : itemSpacing
                }
                var position = horizontal ? inset.top : inset.left
                let lineExtent = line.map { along(sizes[$0]) }.max() ?? 0
                let scale = UIScreen.main.scale
                for item in line {
                    let size = sizes[item]
                    // The origin lands on the pixel grid; the running position stays unrounded
                    // (uikit/collection/selfsizing: 124.25 places at 124.5, the next item at 247).
                    let placed = (position * scale).rounded() / scale
                    let frame = horizontal
                        ? CGRect(x: cursor, y: placed, width: size.width, height: size.height)
                        : CGRect(x: placed, y: cursor, width: size.width, height: size.height)
                    let path = IndexPath(item: item, section: section)
                    let attribute = UICollectionViewLayoutAttributes(forCellWith: path)
                    attribute.frame = frame
                    attributes[path] = attribute
                    position += across(size) + spacing
                }
                cursor += lineExtent + (isLast ? 0 : lineSpacing)
            }
            cursor += horizontal ? inset.right : inset.bottom
            let footerSize = flowDelegate?.collectionView(collection, layout: self, referenceSizeForFooterInSection: section) ?? footerReferenceSize
            let footerExtent = horizontal ? footerSize.width : footerSize.height
            if footerExtent > 0 {
                let attribute = UICollectionViewLayoutAttributes(forSupplementaryViewOfKind: UICollectionView.elementKindSectionFooter, with: IndexPath(item: 0, section: section))
                attribute.frame = horizontal ? CGRect(x: cursor, y: 0, width: footerExtent, height: bounds.height) : CGRect(x: 0, y: cursor, width: bounds.width, height: footerExtent)
                supplementary[UICollectionView.elementKindSectionFooter, default: [:]][section] = attribute
                cursor += footerExtent
            }
            crossExtent = max(crossExtent, horizontal ? bounds.height : bounds.width)
        }
        contentSize = horizontal ? CGSize(width: cursor, height: crossExtent) : CGSize(width: crossExtent, height: cursor)
    }

    private func gap(for line: [Int], sizes: [CGSize], available: CGFloat, minimum: CGFloat, across: (CGSize) -> CGFloat) -> CGFloat {
        guard line.count > 1 else { return minimum }
        let used = line.reduce(0) { $0 + across(sizes[$1]) }
        return max(minimum, (available - used) / CGFloat(line.count - 1))
    }

    open override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        let items = attributes.values.filter { $0.frame.intersects(rect) }.sorted { $0.indexPath < $1.indexPath }
        let extras = supplementary.values.flatMap { $0.values }.filter { $0.frame.intersects(rect) }.sorted { $0.indexPath < $1.indexPath }
        return items + extras
    }

    open override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? { attributes[indexPath] }
    open override func layoutAttributesForSupplementaryView(ofKind kind: String, at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        supplementary[kind]?[indexPath.section]
    }
    open override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool { newBounds.size != collectionView?.bounds.size }

    /// Every item's attributes (for hit testing and rects).
    var allAttributes: [IndexPath: UICollectionViewLayoutAttributes] { attributes }
}

/// A view that can be reused in a collection view.
@MainActor
open class UICollectionReusableView: UIView {
    public internal(set) var reuseIdentifier: String?
    /// The pool a supplementary view returns to (its kind and identifier).
    var supplementaryKey: String?
    /// The element kind a supplementary view was dequeued for (a list cell styles itself by it).
    var supplementaryKind: String?
    open func prepareForReuse() {}
    open func apply(_ layoutAttributes: UICollectionViewLayoutAttributes) {
        frame = layoutAttributes.frame
        alpha = layoutAttributes.alpha
        isHidden = layoutAttributes.isHidden
        transform = layoutAttributes.transform
    }

    /// The attributes a self-sizing cell prefers: its content's fitting size (a cell's
    /// `contentView` constraints, compressed), else the layout's estimate.
    open func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        let fitting = (self as? UICollectionViewCell)?.contentView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize) ?? systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        guard fitting.width > 0, fitting.height > 0 else { return layoutAttributes }
        let attributes = UICollectionViewLayoutAttributes(forCellWith: layoutAttributes.indexPath)
        attributes.frame = CGRect(origin: layoutAttributes.frame.origin, size: fitting)
        return attributes
    }
    public required override init(frame: CGRect) { super.init(frame: frame) }
}

/// A single data item when that item is within the collection view's visible bounds.
@MainActor
open class UICollectionViewCell: UICollectionReusableView {
    public let contentView = UIView()
    open var backgroundView: UIView? { didSet { oldValue?.removeFromSuperview(); if let view = backgroundView { insertSubview(view, at: 0) } } }
    open var selectedBackgroundView: UIView?
    open var isSelected = false { didSet { setNeedsDisplay() } }
    open var isHighlighted = false { didSet { setNeedsDisplay() } }

    /// A content configuration makes the content view that fills the cell's content view
    /// (Containers/ContentConfiguration.swift).
    open var contentConfiguration: (any UIContentConfiguration)? {
        didSet {
            configuredContent?.view.removeFromSuperview()
            configuredContent = nil
            guard let contentConfiguration else { return }
            let view = contentConfiguration.makeContentView()
            view.frame = contentView.bounds
            view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            contentView.addSubview(view)
            configuredContent = ConfiguredContent(view: view)
        }
    }
    open var backgroundConfiguration: UIBackgroundConfiguration? {
        didSet { if let color = backgroundConfiguration?.backgroundColor { backgroundColor = color } }
    }
    var configuredContent: ConfiguredContent?

    public required init(frame: CGRect) {
        super.init(frame: frame)
        contentView.frame = bounds
        contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(contentView)
        isAccessibilityElement = false
    }

    open override func prepareForReuse() {
        isSelected = false
        isHighlighted = false
    }
}

/// The methods adopted by the object you use to manage data and provide cells for a collection view.
@MainActor
public protocol UICollectionViewDataSource: AnyObject {
    func numberOfSections(in collectionView: UICollectionView) -> Int
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell
    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView
}

extension UICollectionViewDataSource {
    public func numberOfSections(in collectionView: UICollectionView) -> Int { 1 }
    public func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        UICollectionReusableView(frame: .zero)
    }
}

/// The methods adopted by the object you use to manage user interactions with items in a
/// collection view.
@MainActor
public protocol UICollectionViewDelegate: UIScrollViewDelegate {
    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath)
    func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath)
    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath)
}

extension UICollectionViewDelegate {
    public func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool { true }
    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {}
    public func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {}
    public func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {}
}

/// An object that manages an ordered collection of data items and presents them using
/// customizable layouts.
@MainActor
open class UICollectionView: UIScrollView {
    public struct ScrollPosition: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let top = ScrollPosition(rawValue: 1)
        public static let centeredVertically = ScrollPosition(rawValue: 2)
        public static let bottom = ScrollPosition(rawValue: 4)
        public static let left = ScrollPosition(rawValue: 8)
        public static let centeredHorizontally = ScrollPosition(rawValue: 16)
        public static let right = ScrollPosition(rawValue: 32)
    }
    public static let elementKindSectionHeader = "UICollectionElementKindSectionHeader"
    public static let elementKindSectionFooter = "UICollectionElementKindSectionFooter"

    open var collectionViewLayout: UICollectionViewLayout {
        didSet { oldValue.collectionView = nil; collectionViewLayout.collectionView = self; setNeedsReload() }
    }
    open weak var dataSource: (any UICollectionViewDataSource)? { didSet { setNeedsReload() } }
    open weak var collectionDelegate: (any UICollectionViewDelegate)?
    open override weak var delegate: (any UIScrollViewDelegate)? {
        didSet { collectionDelegate = delegate as? any UICollectionViewDelegate }
    }
    open var allowsSelection = true
    open var allowsMultipleSelection = false
    open var isPrefetchingEnabled = true
    open var backgroundView: UIView?

    private var registeredCells: [String: () -> UICollectionViewCell] = [:]
    private var reusePool: [String: [UICollectionViewCell]] = [:]
    private var visibleCellsByPath: [IndexPath: UICollectionViewCell] = [:]
    /// Supplementary views: registered by kind and identifier, pooled, and visible by kind and section.
    private var registeredSupplementaries: [String: () -> UICollectionReusableView] = [:]
    /// The scroll views hosting orthogonally scrolling sections' cells, by section.
    private var orthogonalScrollViews: [Int: OrthogonalScrollView] = [:]
    private var supplementaryPool: [String: [UICollectionReusableView]] = [:]
    private var visibleSupplementaries: [String: UICollectionReusableView] = [:]
    /// Decoration views by kind and section, made by the layout's registered classes.
    private var visibleDecorations: [String: UICollectionReusableView] = [:]
    private var needsReload = true
    private var selected: Set<IndexPath> = []

    public init(frame: CGRect, collectionViewLayout layout: UICollectionViewLayout) {
        collectionViewLayout = layout
        super.init(frame: frame)
        layout.collectionView = self
        backgroundColor = .systemBackground
        let tap = UITapGestureRecognizer()
        tap.addTarget { [weak self] recognizer in self?.handleTap(recognizer) }
        addGestureRecognizer(tap)
    }

    public override convenience init(frame: CGRect) { self.init(frame: frame, collectionViewLayout: UICollectionViewFlowLayout()) }

    // MARK: Cells

    open func register(_ cellClass: AnyClass?, forCellWithReuseIdentifier identifier: String) {
        guard let type = cellClass as? UICollectionViewCell.Type else { return }
        registeredCells[identifier] = { type.init(frame: .zero) }
    }

    func hasRegisteredCell(withIdentifier identifier: String) -> Bool { registeredCells[identifier] != nil }

    open func dequeueReusableCell(withReuseIdentifier identifier: String, for indexPath: IndexPath) -> UICollectionViewCell {
        let cell: UICollectionViewCell
        if let pooled = reusePool[identifier]?.popLast() {
            pooled.prepareForReuse()
            cell = pooled
        } else {
            cell = registeredCells[identifier]?() ?? UICollectionViewCell(frame: .zero)
            cell.reuseIdentifier = identifier
        }
        // A list cell dequeued as its section's first-item header knows before it is configured.
        if let listCell = cell as? UICollectionViewListCell {
            listCell.isHeaderItem = (collectionViewLayout as? UICollectionViewListLayout)?.isHeaderItem(indexPath) ?? false
        }
        return cell
    }

    open func register(_ viewClass: AnyClass?, forSupplementaryViewOfKind kind: String, withReuseIdentifier identifier: String) {
        guard let type = viewClass as? UICollectionReusableView.Type else { return }
        registeredSupplementaries[kind + "|" + identifier] = { type.init(frame: .zero) }
    }

    open func dequeueReusableSupplementaryView(ofKind kind: String, withReuseIdentifier identifier: String, for indexPath: IndexPath) -> UICollectionReusableView {
        let key = kind + "|" + identifier
        if let view = supplementaryPool[key]?.popLast() {
            view.prepareForReuse()
            view.supplementaryKind = kind
            return view
        }
        let view = registeredSupplementaries[key]?() ?? UICollectionReusableView(frame: .zero)
        view.reuseIdentifier = identifier
        view.supplementaryKey = key
        view.supplementaryKind = kind
        return view
    }

    /// A supplementary view's size for a section: the data source's view, asked for its preferred
    /// attributes, then returned to its pool (a list header or footer sized by its content).
    func selfSizedSupplementary(ofKind kind: String, at indexPath: IndexPath, estimated: CGSize) -> CGSize {
        guard let dataSource else { return estimated }
        let key = kind + "#" + "\(indexPath.section)"
        let attributes = UICollectionViewLayoutAttributes(forSupplementaryViewOfKind: kind, with: indexPath)
        attributes.frame = CGRect(origin: .zero, size: estimated)
        if let visible = visibleSupplementaries[key] { return visible.preferredLayoutAttributesFitting(attributes).frame.size }
        let view = dataSource.collectionView(self, viewForSupplementaryElementOfKind: kind, at: indexPath)
        let size = view.preferredLayoutAttributesFitting(attributes).frame.size
        if let pool = view.supplementaryKey, view.superview == nil { supplementaryPool[pool, default: []].append(view) }
        return size
    }

    /// A self-sizing item's size: the data source's cell for it, asked for its preferred
    /// attributes, then returned to the pool.
    func selfSizedItem(at indexPath: IndexPath, estimated: CGSize) -> CGSize {
        guard let dataSource else { return estimated }
        if let visible = visibleCellsByPath[indexPath] {
            let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
            attributes.frame = CGRect(origin: .zero, size: estimated)
            return visible.preferredLayoutAttributesFitting(attributes).frame.size
        }
        let cell = dataSource.collectionView(self, cellForItemAt: indexPath)
        let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
        attributes.frame = CGRect(origin: .zero, size: estimated)
        let size = cell.preferredLayoutAttributesFitting(attributes).frame.size
        if let identifier = cell.reuseIdentifier, cell.superview == nil { reusePool[identifier, default: []].append(cell) }
        return size
    }

    open func supplementaryView(forElementKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView? {
        visibleSupplementaries[kind + "#" + "\(indexPath.section)"]
    }

    open var visibleCells: [UICollectionViewCell] { visibleCellsByPath.sorted { $0.key < $1.key }.map(\.value) }
    open var indexPathsForVisibleItems: [IndexPath] { visibleCellsByPath.keys.sorted() }
    open func cellForItem(at indexPath: IndexPath) -> UICollectionViewCell? { visibleCellsByPath[indexPath] }
    open func indexPath(for cell: UICollectionViewCell) -> IndexPath? { visibleCellsByPath.first { $0.value === cell }?.key }
    open func indexPathForItem(at point: CGPoint) -> IndexPath? {
        collectionViewLayout.layoutAttributesForElements(in: CGRect(origin: point, size: CGSize(width: 1, height: 1)))?.first?.indexPath
    }
    open func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? { collectionViewLayout.layoutAttributesForItem(at: indexPath) }
    open var numberOfSections: Int { dataSource?.numberOfSections(in: self) ?? 0 }
    open func numberOfItems(inSection section: Int) -> Int { dataSource?.collectionView(self, numberOfItemsInSection: section) ?? 0 }

    // MARK: Selection

    open var indexPathsForSelectedItems: [IndexPath]? { selected.isEmpty ? nil : selected.sorted() }

    open func selectItem(at indexPath: IndexPath?, animated: Bool, scrollPosition: ScrollPosition) {
        if !allowsMultipleSelection { for path in selected { visibleCellsByPath[path]?.isSelected = false }; selected.removeAll() }
        guard let indexPath else { return }
        selected.insert(indexPath)
        visibleCellsByPath[indexPath]?.isSelected = true
        if let frame = layoutAttributesForItem(at: indexPath)?.frame, !scrollPosition.isEmpty { scrollRectToVisible(frame, animated: animated) }
    }

    open func deselectItem(at indexPath: IndexPath, animated: Bool) {
        selected.remove(indexPath)
        visibleCellsByPath[indexPath]?.isSelected = false
    }

    open func scrollToItem(at indexPath: IndexPath, at scrollPosition: ScrollPosition, animated: Bool) {
        guard let frame = layoutAttributesForItem(at: indexPath)?.frame else { return }
        scrollRectToVisible(frame, animated: animated)
    }

    private func handleTap(_ recognizer: UIGestureRecognizer) {
        guard recognizer.state == .ended, let path = indexPathForItem(at: recognizer.location(in: self)) else { return }
        // An outline parent's tap expands or collapses it rather than selecting it.
        if let listCell = visibleCellsByPath[path] as? UICollectionViewListCell, listCell.accessories.contains(where: { if case .outlineDisclosure = $0.kind { return true } else { return false } }),
           let outline = dataSource as? any _OutlineToggling, outline.toggleOutlineItem(at: path) { return }
        guard allowsSelection else { return }
        if selected.contains(path), allowsMultipleSelection {
            deselectItem(at: path, animated: false)
            collectionDelegate?.collectionView(self, didDeselectItemAt: path)
            return
        }
        guard collectionDelegate?.collectionView(self, shouldSelectItemAt: path) ?? true else { return }
        let previous = selected
        selectItem(at: path, animated: false, scrollPosition: [])
        for old in previous where old != path { collectionDelegate?.collectionView(self, didDeselectItemAt: old) }
        collectionDelegate?.collectionView(self, didSelectItemAt: path)
    }

    // MARK: Loading

    open func reloadData() { setNeedsReload() }

    // MARK: Batch updates (Containers/BatchUpdates.swift)

    private var pendingUpdate: BatchUpdateMapping?
    private var updateDepth = 0
    /// The items per section at the last layout (the old counts of a batch update).
    private var itemCounts: [Int] = []
    /// Cells kept across an animated update, by their new index path.
    private var retainedCells: [IndexPath: UICollectionViewCell] = [:]

    private func record(_ change: (inout BatchUpdateMapping) -> Void) {
        if pendingUpdate != nil {
            change(&pendingUpdate!)
        } else {
            beginUpdates()
            change(&pendingUpdate!)
            endUpdates(completion: nil)
        }
    }

    open func reloadItems(at indexPaths: [IndexPath]) { record { $0.reloadedItems.formUnion(indexPaths) } }
    open func reloadSections(_ sections: IndexSet) { record { $0.reloadedSections.formUnion(sections) } }
    open func insertItems(at indexPaths: [IndexPath]) { record { $0.insertedItems.formUnion(indexPaths) } }
    open func deleteItems(at indexPaths: [IndexPath]) { record { $0.deletedItems.formUnion(indexPaths) } }
    open func moveItem(at indexPath: IndexPath, to newIndexPath: IndexPath) { record { $0.moves[indexPath] = newIndexPath } }
    open func insertSections(_ sections: IndexSet) { record { $0.insertedSections.formUnion(sections) } }
    open func deleteSections(_ sections: IndexSet) { record { $0.deletedSections.formUnion(sections) } }
    open func moveSection(_ section: Int, toSection newSection: Int) { record { $0.deletedSections.insert(section); $0.insertedSections.insert(newSection) } }

    private func beginUpdates() {
        if pendingUpdate == nil { pendingUpdate = BatchUpdateMapping(oldCounts: itemCounts) }
        updateDepth += 1
    }

    private func endUpdates(completion: ((Bool) -> Void)?) {
        updateDepth = max(0, updateDepth - 1)
        guard updateDepth == 0, let update = pendingUpdate else { return }
        pendingUpdate = nil
        let retained = update.retained()
        animateUpdate(retained: retained.mapping, replaced: retained.reloaded, completion: completion)
    }

    open func performBatchUpdates(_ updates: (() -> Void)?, completion: ((Bool) -> Void)? = nil) {
        beginUpdates()
        updates?()
        endUpdates(completion: completion)
    }

    /// Lays the collection out for the new data keeping the cells of `retained` items (old
    /// index path to new), which slide to their new frames; other items' cells fade out, new
    /// items' cells fade in; `replaced` items (reloaded) get a new cell at once. Off screen or
    /// before the first layout the collection just reloads.
    func animateUpdate(retained: [IndexPath: IndexPath], replaced: Set<IndexPath>, completion: ((Bool) -> Void)?) {
        guard window != nil, !visibleCellsByPath.isEmpty, !needsReload else {
            reloadData()
            if let completion { _ = UIKitScene.shared.schedule(after: 0) { completion(true) } }
            return
        }
        var startFrames: [IndexPath: CGRect] = [:]
        var fading: [UICollectionViewCell] = []
        for (oldPath, cell) in visibleCellsByPath {
            if let newPath = retained[oldPath], !replaced.contains(newPath), cell.superview === self {
                retainedCells[newPath] = cell
                startFrames[newPath] = cell.frame
            } else {
                fading.append(cell)
            }
        }
        visibleCellsByPath.removeAll()
        let before = Set(fading.map { ObjectIdentifier($0) }).union(retainedCells.values.map { ObjectIdentifier($0) })
        needsReload = true
        layoutSubviews()
        for cell in retainedCells.values {
            cell.removeFromSuperview()
            if let identifier = cell.reuseIdentifier { reusePool[identifier, default: []].append(cell) }
        }
        retainedCells.removeAll()
        var inserted: [UICollectionViewCell] = []
        for (path, cell) in visibleCellsByPath {
            if let start = startFrames[path] {
                let target = cell.frame
                UIView.performWithoutAnimation { cell.frame = start }
                UIView.animate(withDuration: batchUpdateDuration) { cell.frame = target }
            } else if !before.contains(ObjectIdentifier(cell)) {
                inserted.append(cell)
            }
        }
        for cell in fading { bringSubviewToFront(cell) }
        UIView.performWithoutAnimation { for cell in inserted { cell.alpha = 0 } }
        UIView.animate(withDuration: batchUpdateDuration, animations: {
            for cell in inserted { cell.alpha = 1 }
            for cell in fading { cell.alpha = 0 }
        }, completion: { [weak self] _ in
            guard let self else { return }
            for cell in fading {
                cell.removeFromSuperview()
                cell.alpha = 1
                if let identifier = cell.reuseIdentifier { reusePool[identifier, default: []].append(cell) }
            }
            completion?(true)
        })
    }

    func setNeedsReload() {
        pendingUpdate = nil
        updateDepth = 0
        needsReload = true
        setNeedsLayout()
    }

    open override func layoutSubviews() {
        super.layoutSubviews()
        if needsReload {
            needsReload = false
            for cell in visibleCellsByPath.values {
                cell.removeFromSuperview()
                if let identifier = cell.reuseIdentifier { reusePool[identifier, default: []].append(cell) }
            }
            visibleCellsByPath.removeAll()
            for view in visibleSupplementaries.values {
                view.removeFromSuperview()
                if let key = view.supplementaryKey { supplementaryPool[key, default: []].append(view) }
            }
            visibleSupplementaries.removeAll()
            for view in visibleDecorations.values { view.removeFromSuperview() }
            visibleDecorations.removeAll()
            collectionViewLayout.prepare()
            contentSize = collectionViewLayout.collectionViewContentSize
            if let dataSource {
                itemCounts = (0..<dataSource.numberOfSections(in: self)).map { dataSource.collectionView(self, numberOfItemsInSection: $0) }
            } else {
                itemCounts = []
            }
        }
        updateVisibleCells()
    }

    /// Cells for the items whose frames meet the bounds, as UIKit makes them (the fourth item of
    /// `uikit/collection/horizontal` sits off screen and has no cell).
    private func updateVisibleCells() {
        guard let dataSource else { return }
        let visible = bounds
        // Orthogonal sections: a scroll view per section in view, whose offset decides which
        // of its cells exist (the ones past its right edge are not made, as UIKit does not).
        let sections = (collectionViewLayout as? UICollectionViewCompositionalLayout)?.orthogonalSections ?? [:]
        for (section, scrollView) in orthogonalScrollViews where sections[section] == nil || !sections[section]!.frame.intersects(visible) {
            for (path, cell) in visibleCellsByPath where cell.superview === scrollView {
                cell.removeFromSuperview()
                visibleCellsByPath.removeValue(forKey: path)
                if let identifier = cell.reuseIdentifier { reusePool[identifier, default: []].append(cell) }
            }
            scrollView.removeFromSuperview()
            orthogonalScrollViews.removeValue(forKey: section)
        }
        for (section, info) in sections where info.frame.intersects(visible) {
            let scrollView = orthogonalScrollViews[section] ?? {
                let view = OrthogonalScrollView()
                view.onScroll = { [weak self] in self?.setNeedsLayout() }
                addSubview(view)
                orthogonalScrollViews[section] = view
                return view
            }()
            if scrollView.frame != info.frame { scrollView.frame = info.frame }
            let contentSize = CGSize(width: info.contentWidth, height: info.frame.height)
            if scrollView.contentSize != contentSize { scrollView.contentSize = contentSize }
            scrollView.isPagingEnabled = info.behavior == .paging || info.behavior == .groupPaging || info.behavior == .groupPagingCentered
        }
        func isVisible(_ attribute: UICollectionViewLayoutAttributes) -> Bool {
            guard let section = attribute.orthogonalSection, let info = sections[section], let scrollView = orthogonalScrollViews[section] else { return attribute.frame.intersects(visible) }
            let window = CGRect(x: info.frame.minX + scrollView.contentOffset.x, y: info.frame.minY, width: info.frame.width, height: info.frame.height)
            return attribute.frame.intersects(window)
        }
        for (path, cell) in visibleCellsByPath {
            guard let attribute = layoutAttributesForItem(at: path), isVisible(attribute) else {
                cell.removeFromSuperview()
                visibleCellsByPath.removeValue(forKey: path)
                if let identifier = cell.reuseIdentifier { reusePool[identifier, default: []].append(cell) }
                continue
            }
        }
        var elements = collectionViewLayout.layoutAttributesForElements(in: visible) ?? []
        // An orthogonal section's items sit past the bounds sideways: ask for its scrolled window too.
        for (section, info) in sections where info.frame.intersects(visible) {
            guard let scrollView = orthogonalScrollViews[section] else { continue }
            let window = CGRect(x: info.frame.minX + scrollView.contentOffset.x, y: info.frame.minY, width: info.frame.width, height: info.frame.height)
            let seen = Set(elements.map { $0.indexPath })
            for attribute in collectionViewLayout.layoutAttributesForElements(in: window) ?? [] where attribute.representedElementKind == nil && attribute.orthogonalSection == section && !seen.contains(attribute.indexPath) {
                elements.append(attribute)
            }
        }
        let listLayout = collectionViewLayout as? UICollectionViewListLayout
        var corrected = false
        for attribute in elements where attribute.representedElementKind == nil && visibleCellsByPath[attribute.indexPath] == nil && isVisible(attribute) {
            let cell = retainedCells.removeValue(forKey: attribute.indexPath) ?? dataSource.collectionView(self, cellForItemAt: attribute.indexPath)
            // A list row laid out at an estimate measures itself as it appears.
            if let listLayout, listLayout.needsMeasurement(of: attribute.indexPath) {
                let fitted = cell.preferredLayoutAttributesFitting(attribute).frame.height
                if listLayout.recordMeasured(fitted, at: attribute.indexPath) { corrected = true }
            }
            cell.apply(attribute)
            cell.isSelected = selected.contains(attribute.indexPath)
            collectionDelegate?.collectionView(self, willDisplay: cell, forItemAt: attribute.indexPath)
            if let section = attribute.orthogonalSection, let info = sections[section], let scrollView = orthogonalScrollViews[section] {
                // Inside its section's scroll view, in that view's content coordinates.
                cell.frame = attribute.frame.offsetBy(dx: -info.frame.minX, dy: -info.frame.minY)
                if cell.superview !== scrollView { scrollView.addSubview(cell) }
            } else if cell.superview !== self {
                addSubview(cell)
            }
            visibleCellsByPath[attribute.indexPath] = cell
        }
        // Headers and footers in view; the ones scrolled away go back to their pool. A pinned
        // header's attributes move with the bounds, so a visible one takes them again.
        func key(_ element: UICollectionViewLayoutAttributes) -> String { (element.representedElementKind ?? "") + "#" + "\(element.indexPath.section)" }
        let wanted = Set(elements.filter { $0.representedElementCategory == .supplementaryView }.map(key))
        for (key, view) in visibleSupplementaries where !wanted.contains(key) {
            view.removeFromSuperview()
            visibleSupplementaries.removeValue(forKey: key)
            if let pool = view.supplementaryKey { supplementaryPool[pool, default: []].append(view) }
        }
        for attribute in elements where attribute.representedElementCategory == .supplementaryView {
            guard let kind = attribute.representedElementKind else { continue }
            if let view = visibleSupplementaries[key(attribute)] {
                if view.frame != attribute.frame { view.apply(attribute) }
                continue
            }
            let view = dataSource.collectionView(self, viewForSupplementaryElementOfKind: kind, at: attribute.indexPath)
            if let listLayout, listLayout.needsMeasurement(ofKind: kind, section: attribute.indexPath.section) {
                let fitted = view.preferredLayoutAttributesFitting(attribute).frame.height
                if listLayout.recordMeasured(fitted, kind: kind, section: attribute.indexPath.section) { corrected = true }
            }
            view.apply(attribute)
            if view.superview !== self { addSubview(view) }
            visibleSupplementaries[key(attribute)] = view
        }
        if corrected {
            // Measured heights changed the layout: lay out again (the cells made so far are pooled).
            needsReload = true
            layoutSubviews()
            return
        }
        // Raised supplementaries (pinned headers) stay above the cells added after them; lowered
        // ones (a header being pushed away) sit just above the decorations, under the cells.
        for attribute in elements where attribute.representedElementCategory == .supplementaryView && attribute.zIndex != 0 {
            guard let view = visibleSupplementaries[key(attribute)] else { continue }
            if attribute.zIndex > 0 {
                if subviews.last !== view { bringSubviewToFront(view) }
            } else if let index = subviews.firstIndex(where: { $0 === view }), index != visibleDecorations.count {
                insertSubview(view, at: visibleDecorations.count)
            }
        }
        // Decoration views (section backgrounds) in view, behind the cells.
        let wantedDecorations = Set(elements.filter { $0.representedElementCategory == .decorationView }.map(key))
        for (key, view) in visibleDecorations where !wantedDecorations.contains(key) {
            view.removeFromSuperview()
            visibleDecorations.removeValue(forKey: key)
        }
        for attribute in elements where attribute.representedElementCategory == .decorationView {
            guard let kind = attribute.representedElementKind else { continue }
            if let view = visibleDecorations[key(attribute)] {
                if view.frame != attribute.frame { view.apply(attribute) }
                continue
            }
            guard let view = collectionViewLayout.registeredDecorations[kind]?() else { continue }
            view.apply(attribute)
            insertSubview(view, at: 0)
            visibleDecorations[key(attribute)] = view
        }
    }

    open override var contentOffset: CGPoint {
        didSet { if contentOffset != oldValue, !needsReload { setNeedsLayout() } }
    }
}

/// The scroll view an orthogonally scrolling section's cells live in: horizontal, without
/// indicators, telling the collection view when it moves so the cells in view update.
@MainActor
final class OrthogonalScrollView: UIScrollView {
    var onScroll: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        alwaysBounceVertical = false
    }

    override var contentOffset: CGPoint {
        didSet { if contentOffset != oldValue { onScroll?() } }
    }
}

/// A data source whose sections can be outlines (the diffable data source).
@MainActor
protocol _OutlineToggling: AnyObject {
    func toggleOutlineItem(at indexPath: IndexPath) -> Bool
}
