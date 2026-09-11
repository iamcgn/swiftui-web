// Compositional layouts (Docs/elements/UIKit/CollectionView.md): sections of groups of items
// sized by fractions of their container or by points, with spacing, insets and boundary
// supplementary items, solved into layout attributes for the collection view. Measured on the
// iPhone SE simulator (uikit/collection/compositional).
#if os(WASI)
import FoundationEssentials
#else
import Foundation
#endif

/// A dimension of an item, group or supplementary item.
public struct NSCollectionLayoutDimension: Equatable, Sendable {
    enum Kind: Equatable, Sendable { case fractionalWidth, fractionalHeight, absolute, estimated }
    let kind: Kind
    public let dimension: CGFloat

    public static func fractionalWidth(_ fraction: CGFloat) -> NSCollectionLayoutDimension { NSCollectionLayoutDimension(kind: .fractionalWidth, dimension: fraction) }
    public static func fractionalHeight(_ fraction: CGFloat) -> NSCollectionLayoutDimension { NSCollectionLayoutDimension(kind: .fractionalHeight, dimension: fraction) }
    public static func absolute(_ value: CGFloat) -> NSCollectionLayoutDimension { NSCollectionLayoutDimension(kind: .absolute, dimension: value) }
    public static func estimated(_ value: CGFloat) -> NSCollectionLayoutDimension { NSCollectionLayoutDimension(kind: .estimated, dimension: value) }
    public static func uniformAcrossSiblings(estimate: CGFloat) -> NSCollectionLayoutDimension { NSCollectionLayoutDimension(kind: .estimated, dimension: estimate) }

    public var isFractionalWidth: Bool { kind == .fractionalWidth }
    public var isFractionalHeight: Bool { kind == .fractionalHeight }
    public var isAbsolute: Bool { kind == .absolute }
    public var isEstimated: Bool { kind == .estimated }

    /// The points in a container `size` (an estimate is taken as given).
    func resolved(in size: CGSize) -> CGFloat {
        switch kind {
        case .fractionalWidth: return size.width * dimension
        case .fractionalHeight: return size.height * dimension
        case .absolute, .estimated: return dimension
        }
    }
}

public struct NSCollectionLayoutSize: Equatable, Sendable {
    public let widthDimension: NSCollectionLayoutDimension
    public let heightDimension: NSCollectionLayoutDimension
    public init(widthDimension width: NSCollectionLayoutDimension, heightDimension height: NSCollectionLayoutDimension) {
        widthDimension = width
        heightDimension = height
    }
    func resolved(in size: CGSize) -> CGSize { CGSize(width: widthDimension.resolved(in: size), height: heightDimension.resolved(in: size)) }
}

/// The spacing between items in a group: a fixed amount, or at least an amount, spread.
public struct NSCollectionLayoutSpacing: Equatable, Sendable {
    public let spacing: CGFloat
    public let isFixedSpacing: Bool
    public static func fixed(_ spacing: CGFloat) -> NSCollectionLayoutSpacing { NSCollectionLayoutSpacing(spacing: spacing, isFixedSpacing: true) }
    public static func flexible(_ spacing: CGFloat) -> NSCollectionLayoutSpacing { NSCollectionLayoutSpacing(spacing: spacing, isFixedSpacing: false) }
    public var isFlexibleSpacing: Bool { !isFixedSpacing }
}

/// Spacing around an item's edges.
public struct NSCollectionLayoutEdgeSpacing: Sendable {
    public let leading: NSCollectionLayoutSpacing?
    public let top: NSCollectionLayoutSpacing?
    public let trailing: NSCollectionLayoutSpacing?
    public let bottom: NSCollectionLayoutSpacing?
    public init(leading: NSCollectionLayoutSpacing?, top: NSCollectionLayoutSpacing?, trailing: NSCollectionLayoutSpacing?, bottom: NSCollectionLayoutSpacing?) {
        self.leading = leading; self.top = top; self.trailing = trailing; self.bottom = bottom
    }
}

/// An item: a cell, or (as a group) a container of items.
@MainActor
open class NSCollectionLayoutItem {
    public let layoutSize: NSCollectionLayoutSize
    open var contentInsets = NSDirectionalEdgeInsets.zero
    open var edgeSpacing: NSCollectionLayoutEdgeSpacing?
    public let supplementaryItems: [NSCollectionLayoutSupplementaryItem]

    public init(layoutSize: NSCollectionLayoutSize, supplementaryItems: [NSCollectionLayoutSupplementaryItem] = []) {
        self.layoutSize = layoutSize
        self.supplementaryItems = supplementaryItems
    }
}

/// A supplementary item anchored to an item (stored).
@MainActor
open class NSCollectionLayoutSupplementaryItem {
    public let layoutSize: NSCollectionLayoutSize
    public let elementKind: String
    public init(layoutSize: NSCollectionLayoutSize, elementKind: String) {
        self.layoutSize = layoutSize
        self.elementKind = elementKind
    }
}

/// A group: items along an axis, repeating to fill the group's size.
@MainActor
open class NSCollectionLayoutGroup: NSCollectionLayoutItem {
    public enum Axis: Sendable { case horizontal, vertical }
    let axis: Axis
    let subitems: [NSCollectionLayoutItem]
    let repeatCount: Int?
    open var interItemSpacing: NSCollectionLayoutSpacing?

    init(axis: Axis, layoutSize: NSCollectionLayoutSize, subitems: [NSCollectionLayoutItem], count: Int?) {
        self.axis = axis
        self.subitems = subitems
        repeatCount = count
        super.init(layoutSize: layoutSize)
    }

    public class func horizontal(layoutSize: NSCollectionLayoutSize, subitems: [NSCollectionLayoutItem]) -> NSCollectionLayoutGroup {
        NSCollectionLayoutGroup(axis: .horizontal, layoutSize: layoutSize, subitems: subitems, count: nil)
    }
    public class func vertical(layoutSize: NSCollectionLayoutSize, subitems: [NSCollectionLayoutItem]) -> NSCollectionLayoutGroup {
        NSCollectionLayoutGroup(axis: .vertical, layoutSize: layoutSize, subitems: subitems, count: nil)
    }
    public class func horizontal(layoutSize: NSCollectionLayoutSize, repeatingSubitem subitem: NSCollectionLayoutItem, count: Int) -> NSCollectionLayoutGroup {
        NSCollectionLayoutGroup(axis: .horizontal, layoutSize: layoutSize, subitems: [subitem], count: count)
    }
    public class func vertical(layoutSize: NSCollectionLayoutSize, repeatingSubitem subitem: NSCollectionLayoutItem, count: Int) -> NSCollectionLayoutGroup {
        NSCollectionLayoutGroup(axis: .vertical, layoutSize: layoutSize, subitems: [subitem], count: count)
    }
    public class func horizontal(layoutSize: NSCollectionLayoutSize, subitem: NSCollectionLayoutItem, count: Int) -> NSCollectionLayoutGroup {
        horizontal(layoutSize: layoutSize, repeatingSubitem: subitem, count: count)
    }
    public class func vertical(layoutSize: NSCollectionLayoutSize, subitem: NSCollectionLayoutItem, count: Int) -> NSCollectionLayoutGroup {
        vertical(layoutSize: layoutSize, repeatingSubitem: subitem, count: count)
    }
}

/// A supplementary item at a section's (or the layout's) edge.
@MainActor
open class NSCollectionLayoutBoundarySupplementaryItem: NSCollectionLayoutSupplementaryItem {
    public let alignment: NSRectAlignment
    open var pinToVisibleBounds = false
    open var extendsBoundary = true
    public init(layoutSize: NSCollectionLayoutSize, elementKind: String, alignment: NSRectAlignment) {
        self.alignment = alignment
        super.init(layoutSize: layoutSize, elementKind: elementKind)
    }
}

public enum NSRectAlignment: Int, Sendable { case none = 0, top, topLeading, leading, bottomLeading, bottom, bottomTrailing, trailing, topTrailing }

/// A section: its group repeated along the layout's scroll direction until the items run out.
@MainActor
open class NSCollectionLayoutSection {
    public enum OrthogonalScrollingBehavior: Int, Sendable { case none = 0, continuous, continuousGroupLeadingBoundary, paging, groupPaging, groupPagingCentered }
    let group: NSCollectionLayoutGroup
    open var contentInsets = NSDirectionalEdgeInsets.zero
    open var interGroupSpacing: CGFloat = 0
    open var boundarySupplementaryItems: [NSCollectionLayoutBoundarySupplementaryItem] = []
    open var orthogonalScrollingBehavior: OrthogonalScrollingBehavior = .none
    open var supplementariesFollowContentInsets = true
    open var visibleItemsInvalidationHandler: ((Any, CGPoint, Any) -> Void)?

    public init(group: NSCollectionLayoutGroup) { self.group = group }
}

/// What the layout knows about its container when a section provider asks.
public protocol NSCollectionLayoutEnvironment {
    var container: any NSCollectionLayoutContainer { get }
}

public protocol NSCollectionLayoutContainer {
    var contentSize: CGSize { get }
    var effectiveContentSize: CGSize { get }
    var contentInsets: NSDirectionalEdgeInsets { get }
    var effectiveContentInsets: NSDirectionalEdgeInsets { get }
}

struct LayoutContainer: NSCollectionLayoutContainer {
    let contentSize: CGSize
    let contentInsets: NSDirectionalEdgeInsets
    var effectiveContentSize: CGSize { CGSize(width: contentSize.width - contentInsets.leading - contentInsets.trailing, height: contentSize.height - contentInsets.top - contentInsets.bottom) }
    var effectiveContentInsets: NSDirectionalEdgeInsets { contentInsets }
}

struct LayoutEnvironment: NSCollectionLayoutEnvironment {
    let container: any NSCollectionLayoutContainer
}

/// The layout's configuration: the scroll direction and the spacing between sections.
public final class UICollectionViewCompositionalLayoutConfiguration {
    public var scrollDirection: UICollectionViewFlowLayout.ScrollDirection = .vertical
    public var interSectionSpacing: CGFloat = 0
    public var boundarySupplementaryItems: [NSCollectionLayoutBoundarySupplementaryItem] = []
    public var contentInsetsReference = 0
    public init() {}
}

/// A layout object that lets you combine items in highly adaptive and flexible visual arrangements.
@MainActor
open class UICollectionViewCompositionalLayout: UICollectionViewLayout {
    public typealias SectionProvider = (Int, any NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection?
    private let sectionProvider: SectionProvider
    open var configuration: UICollectionViewCompositionalLayoutConfiguration

    private var itemAttributes: [IndexPath: UICollectionViewLayoutAttributes] = [:]
    private var supplementary: [String: [Int: UICollectionViewLayoutAttributes]] = [:]
    private var contentSize = CGSize.zero

    /// An orthogonally scrolling section: where its scroll view sits in the collection (the
    /// section inset by its content insets) and how wide its content runs.
    struct OrthogonalSection {
        let frame: CGRect
        let contentWidth: CGFloat
        let behavior: NSCollectionLayoutSection.OrthogonalScrollingBehavior
    }
    private(set) var orthogonalSections: [Int: OrthogonalSection] = [:]

    public init(section: NSCollectionLayoutSection) {
        sectionProvider = { _, _ in section }
        configuration = UICollectionViewCompositionalLayoutConfiguration()
        super.init()
    }

    public init(section: NSCollectionLayoutSection, configuration: UICollectionViewCompositionalLayoutConfiguration) {
        sectionProvider = { _, _ in section }
        self.configuration = configuration
        super.init()
    }

    public init(sectionProvider: @escaping SectionProvider) {
        self.sectionProvider = sectionProvider
        configuration = UICollectionViewCompositionalLayoutConfiguration()
        super.init()
    }

    public init(sectionProvider: @escaping SectionProvider, configuration: UICollectionViewCompositionalLayoutConfiguration) {
        self.sectionProvider = sectionProvider
        self.configuration = configuration
        super.init()
    }

    open override var collectionViewContentSize: CGSize { contentSize }

    open override func prepare() {
        itemAttributes.removeAll()
        supplementary.removeAll()
        orthogonalSections.removeAll()
        guard let collection = collectionView, let dataSource = collection.dataSource else { contentSize = .zero; return }
        let bounds = collection.bounds
        let vertical = configuration.scrollDirection == .vertical
        var cursor: CGFloat = 0
        let sections = dataSource.numberOfSections(in: collection)
        let environment = LayoutEnvironment(container: LayoutContainer(contentSize: bounds.size, contentInsets: .zero))
        for section in 0..<sections {
            guard let layoutSection = sectionProvider(section, environment) else { continue }
            let count = dataSource.collectionView(collection, numberOfItemsInSection: section)
            let insets = layoutSection.contentInsets
            let container = vertical
                ? CGSize(width: bounds.width - insets.leading - insets.trailing, height: bounds.height)
                : CGSize(width: bounds.width, height: bounds.height - insets.top - insets.bottom)
            if section > 0 { cursor += configuration.interSectionSpacing }
            // Boundary items at the top (leading) span the section's container.
            for boundary in layoutSection.boundarySupplementaryItems where boundary.alignment == .top || boundary.alignment == .topLeading || boundary.alignment == .topTrailing {
                let size = boundary.layoutSize.resolved(in: container)
                let attribute = UICollectionViewLayoutAttributes(forSupplementaryViewOfKind: boundary.elementKind, with: IndexPath(item: 0, section: section))
                attribute.frame = vertical ? CGRect(x: insets.leading, y: cursor, width: size.width, height: size.height) : CGRect(x: cursor, y: insets.top, width: size.width, height: size.height)
                supplementary[boundary.elementKind, default: [:]][section] = attribute
                cursor += vertical ? size.height : size.width
            }
            cursor += vertical ? insets.top : insets.leading
            var item = 0
            var groupIndex = 0
            if vertical, layoutSection.orthogonalScrollingBehavior != .none {
                // The groups run sideways in a scroll view of their own, inset by the section's
                // insets (uikit/collection/orthogonal: 200 pt groups 12 apart from x 16 in a 288
                // wide scroll view 100 tall); the items' attributes stay in the collection's space.
                let group = layoutSection.group
                let groupSize = group.layoutSize.resolved(in: container)
                var x = insets.leading
                while item < count {
                    if groupIndex > 0 { x += layoutSection.interGroupSpacing }
                    let placed = place(group, in: CGRect(origin: CGPoint(x: x, y: cursor), size: groupSize), section: section, from: item, count: count)
                    for (path, frame) in placed.frames {
                        let attribute = UICollectionViewLayoutAttributes(forCellWith: path)
                        attribute.frame = frame
                        attribute.orthogonalSection = section
                        itemAttributes[path] = attribute
                    }
                    item = placed.next
                    x += groupSize.width
                    groupIndex += 1
                    if placed.frames.isEmpty { break }
                }
                orthogonalSections[section] = OrthogonalSection(frame: CGRect(x: insets.leading, y: cursor, width: bounds.width - insets.leading - insets.trailing, height: groupSize.height),
                                                                contentWidth: x - insets.leading + insets.trailing, behavior: layoutSection.orthogonalScrollingBehavior)
                cursor += groupSize.height
                item = count
            }
            while item < count {
                if groupIndex > 0 { cursor += layoutSection.interGroupSpacing }
                let group = layoutSection.group
                let groupSize = group.layoutSize.resolved(in: container)
                let origin = vertical ? CGPoint(x: insets.leading, y: cursor) : CGPoint(x: cursor, y: insets.top)
                let placed = place(group, in: CGRect(origin: origin, size: groupSize), section: section, from: item, count: count)
                for (path, frame) in placed.frames {
                    let attribute = UICollectionViewLayoutAttributes(forCellWith: path)
                    attribute.frame = frame
                    itemAttributes[path] = attribute
                }
                item = placed.next
                cursor += vertical ? groupSize.height : groupSize.width
                groupIndex += 1
                if placed.next == item, placed.frames.isEmpty { break }
            }
            cursor += vertical ? insets.bottom : insets.trailing
            for boundary in layoutSection.boundarySupplementaryItems where boundary.alignment == .bottom || boundary.alignment == .bottomLeading || boundary.alignment == .bottomTrailing {
                let size = boundary.layoutSize.resolved(in: container)
                let attribute = UICollectionViewLayoutAttributes(forSupplementaryViewOfKind: boundary.elementKind, with: IndexPath(item: 0, section: section))
                attribute.frame = vertical ? CGRect(x: insets.leading, y: cursor, width: size.width, height: size.height) : CGRect(x: cursor, y: insets.top, width: size.width, height: size.height)
                supplementary[boundary.elementKind, default: [:]][section] = attribute
                cursor += vertical ? size.height : size.width
            }
        }
        contentSize = vertical ? CGSize(width: bounds.width, height: cursor) : CGSize(width: cursor, height: bounds.height)
    }

    /// Lays a group's subitems out in `frame`, repeating them to fill the group's axis, taking
    /// items from `from`; nested groups recurse. Fixed inter-item spacing comes out of the
    /// fractional items' share; flexible spacing spreads what is left.
    private func place(_ group: NSCollectionLayoutGroup, in frame: CGRect, section: Int, from: Int, count: Int) -> (frames: [IndexPath: CGRect], next: Int) {
        var frames: [IndexPath: CGRect] = [:]
        var item = from
        let inner = frame.inset(by: group.contentInsets)
        let horizontal = group.axis == .horizontal
        let spacing = group.interItemSpacing?.spacing ?? 0
        let fixed = group.interItemSpacing?.isFixedSpacing ?? true
        // The slots: the subitems repeated to fill the axis (or `count` of the one subitem).
        var slots: [NSCollectionLayoutItem] = []
        if let repeatCount = group.repeatCount, let subitem = group.subitems.first {
            slots = Array(repeating: subitem, count: repeatCount)
        } else {
            let axisLength = horizontal ? inner.width : inner.height
            var used: CGFloat = 0
            var index = 0
            while !group.subitems.isEmpty {
                let subitem = group.subitems[index % group.subitems.count]
                let size = subitem.layoutSize.resolved(in: inner.size)
                let extent = horizontal ? size.width : size.height
                // Slots fill by the items' own sizes; a fixed spacing comes out of the
                // fractional items afterwards (three 1/3 items 8 apart fit, at 90.5 each in 288).
                if !slots.isEmpty, used + extent > axisLength + 0.001 { break }
                used += extent
                slots.append(subitem)
                index += 1
                if slots.count >= 1000 || (index >= group.subitems.count && !subitem.layoutSize.widthDimension.isFractionalWidth && !subitem.layoutSize.heightDimension.isFractionalHeight && extent == 0) { break }
            }
        }
        guard !slots.isEmpty else { return (frames, item) }
        // Fixed spacing comes out of the fractional items' share of the axis.
        let axisLength = horizontal ? inner.width : inner.height
        let fixedTotal = fixed ? spacing * CGFloat(max(0, slots.count - 1)) : 0
        let fractionalCount = slots.filter { horizontal ? $0.layoutSize.widthDimension.isFractionalWidth : $0.layoutSize.heightDimension.isFractionalHeight }.count
        let absoluteTotal = slots.reduce(CGFloat(0)) { total, slot in
            let size = slot.layoutSize.resolved(in: inner.size)
            let extent = horizontal ? size.width : size.height
            let fractional = horizontal ? slot.layoutSize.widthDimension.isFractionalWidth : slot.layoutSize.heightDimension.isFractionalHeight
            return total + (fractional ? 0 : extent)
        }
        let fractionalBudget = max(0, axisLength - fixedTotal - absoluteTotal)
        var extents: [CGFloat] = slots.map { slot in
            let size = slot.layoutSize.resolved(in: inner.size)
            let extent = horizontal ? size.width : size.height
            let fractional = horizontal ? slot.layoutSize.widthDimension.isFractionalWidth : slot.layoutSize.heightDimension.isFractionalHeight
            return fractional && fractionalCount > 0 ? extent / axisLength * (fractionalBudget + (axisLength - fixedTotal - absoluteTotal - fractionalBudget)) * (axisLength > 0 ? 1 : 0) : extent
        }
        if fixed, fractionalCount > 0 {
            // Scale the fractional items so everything fits with the spacing between.
            let fractionalSum = zip(slots, extents).reduce(CGFloat(0)) { total, pair in
                let fractional = horizontal ? pair.0.layoutSize.widthDimension.isFractionalWidth : pair.0.layoutSize.heightDimension.isFractionalHeight
                return total + (fractional ? pair.1 : 0)
            }
            if fractionalSum > 0, fractionalSum + absoluteTotal + fixedTotal > axisLength + 0.001 {
                let scale = fractionalBudget / fractionalSum
                for index in extents.indices {
                    let fractional = horizontal ? slots[index].layoutSize.widthDimension.isFractionalWidth : slots[index].layoutSize.heightDimension.isFractionalHeight
                    if fractional { extents[index] *= scale }
                }
            }
        }
        let scale = UIScreen.main.scale
        // Extents land on the pixel grid (90.67 becomes 90.5).
        for index in extents.indices { extents[index] = (extents[index] * scale).rounded() / scale }
        let gap = fixed ? spacing : (slots.count > 1 ? max(spacing, (axisLength - extents.reduce(0, +)) / CGFloat(slots.count - 1)) : 0)
        var position: CGFloat = horizontal ? inner.minX : inner.minY
        for (index, slot) in slots.enumerated() {
            guard item < count else { break }
            let size = slot.layoutSize.resolved(in: inner.size)
            let extent = extents[index]
            let rounded = (position * scale).rounded() / scale
            let slotFrame = horizontal
                ? CGRect(x: rounded, y: inner.minY, width: extent, height: min(size.height, inner.height))
                : CGRect(x: inner.minX, y: rounded, width: min(size.width, inner.width), height: extent)
            if let nested = slot as? NSCollectionLayoutGroup {
                let placed = place(nested, in: slotFrame, section: section, from: item, count: count)
                frames.merge(placed.frames) { $1 }
                item = placed.next
            } else {
                frames[IndexPath(item: item, section: section)] = slotFrame.inset(by: slot.contentInsets)
                item += 1
            }
            position += extent + gap
        }
        return (frames, item)
    }

    open override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        let items = itemAttributes.values.filter { $0.frame.intersects(rect) }.sorted { $0.indexPath < $1.indexPath }
        let extras = supplementary.values.flatMap { $0.values }.filter { $0.frame.intersects(rect) }.sorted { $0.indexPath < $1.indexPath }
        return items + extras
    }

    open override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? { itemAttributes[indexPath] }
    open override func layoutAttributesForSupplementaryView(ofKind kind: String, at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? { supplementary[kind]?[indexPath.section] }
    open override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool { newBounds.size != collectionView?.bounds.size }
}

extension CGRect {
    /// The rectangle inside directional insets (leading as left).
    func inset(by insets: NSDirectionalEdgeInsets) -> CGRect {
        CGRect(x: minX + insets.leading, y: minY + insets.top, width: max(0, width - insets.leading - insets.trailing), height: max(0, height - insets.top - insets.bottom))
    }
}
