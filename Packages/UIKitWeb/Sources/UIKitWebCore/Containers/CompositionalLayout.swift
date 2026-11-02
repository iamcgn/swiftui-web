// Compositional layouts (Docs/elements/UIKit/CollectionView.md): sections of groups of items
// sized by fractions of their container or by points, with spacing, insets and boundary
// supplementary items, solved into layout attributes for the collection view. Measured on the
// iPhone SE simulator (uikit/collection/compositional).
#if os(WASI)
import WebFoundation
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
@preconcurrency @MainActor
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

/// The edges of a directional rectangle.
public struct NSDirectionalRectEdge: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let top = NSDirectionalRectEdge(rawValue: 1 << 0)
    public static let leading = NSDirectionalRectEdge(rawValue: 1 << 1)
    public static let bottom = NSDirectionalRectEdge(rawValue: 1 << 2)
    public static let trailing = NSDirectionalRectEdge(rawValue: 1 << 3)
    public static let all: NSDirectionalRectEdge = [.top, .leading, .bottom, .trailing]
}

/// Where a supplementary item attaches: the edges it aligns to (the middle where an axis has
/// none) and an offset, in points or in fractions of the supplementary item's own size.
@preconcurrency @MainActor
open class NSCollectionLayoutAnchor {
    public let edges: NSDirectionalRectEdge
    public let offset: CGPoint
    public let isAbsoluteOffset: Bool
    public var isFractionalOffset: Bool { !isAbsoluteOffset && offset != .zero }

    public init(edges: NSDirectionalRectEdge) {
        self.edges = edges
        offset = .zero
        isAbsoluteOffset = true
    }
    public init(edges: NSDirectionalRectEdge, absoluteOffset: CGPoint) {
        self.edges = edges
        offset = absoluteOffset
        isAbsoluteOffset = true
    }
    public init(edges: NSDirectionalRectEdge, fractionalOffset: CGPoint) {
        self.edges = edges
        offset = fractionalOffset
        isAbsoluteOffset = false
    }

    /// The anchored point on `rect`, moved by the offset (fractions of `size`).
    func point(on rect: CGRect, size: CGSize) -> CGPoint {
        let x = edges.contains(.leading) ? rect.minX : edges.contains(.trailing) ? rect.maxX : rect.midX
        let y = edges.contains(.top) ? rect.minY : edges.contains(.bottom) ? rect.maxY : rect.midY
        let dx = isAbsoluteOffset ? offset.x : offset.x * size.width
        let dy = isAbsoluteOffset ? offset.y : offset.y * size.height
        return CGPoint(x: x + dx, y: y + dy)
    }
}

/// A supplementary item anchored to an item (a badge at a corner): its container anchor names
/// the point on the item, its item anchor the point on itself that lands there (the same edges
/// when nil, so the item sits inside the corner).
@preconcurrency @MainActor
open class NSCollectionLayoutSupplementaryItem {
    public let layoutSize: NSCollectionLayoutSize
    public let elementKind: String
    public let containerAnchor: NSCollectionLayoutAnchor
    public let itemAnchor: NSCollectionLayoutAnchor?
    open var zIndex = 1
    open var contentInsets = NSDirectionalEdgeInsets.zero
    public init(layoutSize: NSCollectionLayoutSize, elementKind: String) {
        self.layoutSize = layoutSize
        self.elementKind = elementKind
        containerAnchor = NSCollectionLayoutAnchor(edges: [.top, .leading])
        itemAnchor = nil
    }
    public init(layoutSize: NSCollectionLayoutSize, elementKind: String, containerAnchor: NSCollectionLayoutAnchor) {
        self.layoutSize = layoutSize
        self.elementKind = elementKind
        self.containerAnchor = containerAnchor
        itemAnchor = nil
    }
    public init(layoutSize: NSCollectionLayoutSize, elementKind: String, containerAnchor: NSCollectionLayoutAnchor, itemAnchor: NSCollectionLayoutAnchor) {
        self.layoutSize = layoutSize
        self.elementKind = elementKind
        self.containerAnchor = containerAnchor
        self.itemAnchor = itemAnchor
    }

    /// The supplementary item's frame on an item at `container`.
    func frame(on container: CGRect) -> CGRect {
        let size = layoutSize.resolved(in: container.size)
        let own = CGRect(origin: .zero, size: size)
        let target = containerAnchor.point(on: container, size: size)
        let mine = (itemAnchor ?? NSCollectionLayoutAnchor(edges: containerAnchor.edges)).point(on: own, size: size)
        return CGRect(x: target.x - mine.x, y: target.y - mine.y, width: size.width, height: size.height).inset(by: contentInsets)
    }
}

/// A group: items along an axis, repeating to fill the group's size.
@preconcurrency @MainActor
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
@preconcurrency @MainActor
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

/// A decoration behind a section: a view of a kind registered with the layout, filling the
/// section's frame inside the item's content insets.
@preconcurrency @MainActor
open class NSCollectionLayoutDecorationItem {
    public let elementKind: String
    open var contentInsets = NSDirectionalEdgeInsets.zero
    open var zIndex = 0
    public init(elementKind: String) { self.elementKind = elementKind }
    public class func background(elementKind: String) -> NSCollectionLayoutDecorationItem { NSCollectionLayoutDecorationItem(elementKind: elementKind) }
}

/// A section: its group repeated along the layout's scroll direction until the items run out.
@preconcurrency @MainActor
open class NSCollectionLayoutSection {
    public enum OrthogonalScrollingBehavior: Int, Sendable { case none = 0, continuous, continuousGroupLeadingBoundary, paging, groupPaging, groupPagingCentered }
    let group: NSCollectionLayoutGroup
    open var contentInsets = NSDirectionalEdgeInsets.zero
    open var interGroupSpacing: CGFloat = 0
    open var boundarySupplementaryItems: [NSCollectionLayoutBoundarySupplementaryItem] = []
    open var decorationItems: [NSCollectionLayoutDecorationItem] = []
    open var orthogonalScrollingBehavior: OrthogonalScrollingBehavior = .none
    open var supplementariesFollowContentInsets = true
    /// Called with the items in view before each layout of the section (an orthogonal section
    /// as it scrolls, with its own offset; any section as the collection scrolls), to change
    /// their transform, alpha, z-index or centre.
    open var visibleItemsInvalidationHandler: VisibleItemsInvalidationHandler?
    public typealias VisibleItemsInvalidationHandler = ([any NSCollectionLayoutVisibleItem], CGPoint, any NSCollectionLayoutEnvironment) -> Void

    public init(group: NSCollectionLayoutGroup) { self.group = group }
}

/// What the layout knows about its container when a section provider asks.
public protocol NSCollectionLayoutEnvironment {
    var container: any NSCollectionLayoutContainer { get }
}

/// An item in view as the invalidation handler sees it: its layout attributes to change.
@preconcurrency @MainActor
public protocol NSCollectionLayoutVisibleItem: AnyObject {
    var alpha: CGFloat { get set }
    var zIndex: Int { get set }
    var isHidden: Bool { get set }
    var center: CGPoint { get set }
    var transform: CGAffineTransform { get set }
    var name: String? { get }
    var indexPath: IndexPath { get }
    var frame: CGRect { get }
    var bounds: CGRect { get }
    var representedElementCategory: UICollectionViewLayoutAttributes.Category { get }
    var representedElementKind: String? { get }
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
@preconcurrency @MainActor
open class UICollectionViewCompositionalLayout: UICollectionViewLayout {
    public typealias SectionProvider = (Int, any NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection?
    private let sectionProvider: SectionProvider
    open var configuration: UICollectionViewCompositionalLayoutConfiguration

    private var itemAttributes: [IndexPath: UICollectionViewLayoutAttributes] = [:]
    private var supplementary: [String: [Int: UICollectionViewLayoutAttributes]] = [:]
    /// Supplementary items anchored to items (badges), by kind then item.
    private var itemSupplementaries: [String: [IndexPath: UICollectionViewLayoutAttributes]] = [:]
    private var decorations: [String: [Int: UICollectionViewLayoutAttributes]] = [:]
    /// A pinned boundary item: its natural frame, the start and end of its section, between
    /// which it holds at the visible top (a header) or bottom (a footer).
    private struct PinnedHeader { let kind: String; let section: Int; let sectionStart: CGFloat; let sectionEnd: CGFloat; let footer: Bool }
    private var pinned: [PinnedHeader] = []
    private var contentSize = CGSize.zero
    /// Heights measured for items with an estimated dimension, kept across layouts.
    private var measuredItems: [IndexPath: CGFloat] = [:]
    /// The sections' invalidation handlers, by section.
    private(set) var visibleItemHandlers: [Int: NSCollectionLayoutSection.VisibleItemsInvalidationHandler] = [:]
    /// The environment sections were made with (handed to the invalidation handlers).
    private(set) var environment: any NSCollectionLayoutEnvironment = LayoutEnvironment(container: LayoutContainer(contentSize: .zero, contentInsets: .zero))

    /// An orthogonally scrolling section: where its scroll view sits in the collection (the
    /// section inset by its content insets) and how wide its content runs.
    struct OrthogonalSection {
        let frame: CGRect
        let contentWidth: CGFloat
        let behavior: NSCollectionLayoutSection.OrthogonalScrollingBehavior
        /// The groups' leading edges in the scroll view's content, and their width (paging snaps to them).
        let groupStarts: [CGFloat]
        let groupWidth: CGFloat
        let leadingInset: CGFloat
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

    open override func invalidateLayout() {
        measuredItems.removeAll()
        super.invalidateLayout()
    }

    open override func prepare() {
        itemAttributes.removeAll()
        supplementary.removeAll()
        itemSupplementaries.removeAll()
        decorations.removeAll()
        pinned.removeAll()
        orthogonalSections.removeAll()
        visibleItemHandlers.removeAll()
        guard let collection = collectionView, let dataSource = collection.dataSource else { contentSize = .zero; return }
        let bounds = collection.bounds
        let vertical = configuration.scrollDirection == .vertical
        var cursor: CGFloat = 0
        let sections = dataSource.numberOfSections(in: collection)
        let environment = LayoutEnvironment(container: LayoutContainer(contentSize: bounds.size, contentInsets: .zero))
        self.environment = environment
        for section in 0..<sections {
            guard let layoutSection = sectionProvider(section, environment) else { continue }
            if let handler = layoutSection.visibleItemsInvalidationHandler { visibleItemHandlers[section] = handler }
            let count = dataSource.collectionView(collection, numberOfItemsInSection: section)
            let insets = layoutSection.contentInsets
            let container = vertical
                ? CGSize(width: bounds.width - insets.leading - insets.trailing, height: bounds.height)
                : CGSize(width: bounds.width, height: bounds.height - insets.top - insets.bottom)
            if section > 0 { cursor += configuration.interSectionSpacing }
            let sectionStart = cursor
            // Boundary items at the top (leading) span the section's container.
            for boundary in layoutSection.boundarySupplementaryItems where boundary.alignment == .top || boundary.alignment == .topLeading || boundary.alignment == .topTrailing {
                let size = boundary.layoutSize.resolved(in: container)
                let attribute = UICollectionViewLayoutAttributes(forSupplementaryViewOfKind: boundary.elementKind, with: IndexPath(item: 0, section: section))
                attribute.frame = vertical ? CGRect(x: insets.leading, y: cursor, width: size.width, height: size.height) : CGRect(x: cursor, y: insets.top, width: size.width, height: size.height)
                if boundary.pinToVisibleBounds { attribute.zIndex = 1; pinned.append(PinnedHeader(kind: boundary.elementKind, section: section, sectionStart: sectionStart, sectionEnd: 0, footer: false)) }
                supplementary[boundary.elementKind, default: [:]][section] = attribute
                cursor += vertical ? size.height : size.width
            }
            cursor += vertical ? insets.top : insets.leading
            var item = 0
            var groupIndex = 0
            /// Records a placed group's items and their anchored supplementary items.
            func record(_ placed: Placed, orthogonal: Bool) {
                for (path, frame) in placed.frames {
                    let attribute = UICollectionViewLayoutAttributes(forCellWith: path)
                    attribute.frame = frame
                    if orthogonal { attribute.orthogonalSection = section }
                    itemAttributes[path] = attribute
                }
                for (path, items) in placed.supplementaries {
                    for (kind, frame, zIndex) in items {
                        let attribute = UICollectionViewLayoutAttributes(forSupplementaryViewOfKind: kind, with: path)
                        attribute.frame = frame
                        attribute.zIndex = zIndex
                        if orthogonal { attribute.orthogonalSection = section }
                        itemSupplementaries[kind, default: [:]][path] = attribute
                    }
                }
            }
            if vertical, layoutSection.orthogonalScrollingBehavior != .none {
                // The groups run sideways in a scroll view of their own, inset by the section's
                // insets (uikit/collection/orthogonal: 200 pt groups 12 apart from x 16 in a 288
                // wide scroll view 100 tall); the items' attributes stay in the collection's space.
                let group = layoutSection.group
                let groupSize = group.layoutSize.resolved(in: container)
                var x = insets.leading
                var starts: [CGFloat] = []
                var height = groupSize.height
                while item < count {
                    if groupIndex > 0 { x += layoutSection.interGroupSpacing }
                    let placed = place(group, in: CGRect(origin: CGPoint(x: x, y: cursor), size: groupSize), section: section, from: item, count: count)
                    record(placed, orthogonal: true)
                    starts.append(x - insets.leading)
                    height = max(height, placed.size.height)
                    item = placed.next
                    x += groupSize.width
                    groupIndex += 1
                    if placed.frames.isEmpty { break }
                }
                orthogonalSections[section] = OrthogonalSection(frame: CGRect(x: insets.leading, y: cursor, width: bounds.width - insets.leading - insets.trailing, height: height),
                                                                contentWidth: x - insets.leading + insets.trailing, behavior: layoutSection.orthogonalScrollingBehavior,
                                                                groupStarts: starts, groupWidth: groupSize.width, leadingInset: insets.leading)
                cursor += height
                item = count
            }
            while item < count {
                if groupIndex > 0 { cursor += layoutSection.interGroupSpacing }
                let group = layoutSection.group
                let groupSize = group.layoutSize.resolved(in: container)
                let origin = vertical ? CGPoint(x: insets.leading, y: cursor) : CGPoint(x: cursor, y: insets.top)
                let placed = place(group, in: CGRect(origin: origin, size: groupSize), section: section, from: item, count: count)
                record(placed, orthogonal: false)
                item = placed.next
                // An estimated group is as long as its measured items made it.
                cursor += vertical ? placed.size.height : placed.size.width
                groupIndex += 1
                if placed.next == item, placed.frames.isEmpty { break }
            }
            cursor += vertical ? insets.bottom : insets.trailing
            for boundary in layoutSection.boundarySupplementaryItems where boundary.alignment == .bottom || boundary.alignment == .bottomLeading || boundary.alignment == .bottomTrailing {
                let size = boundary.layoutSize.resolved(in: container)
                let attribute = UICollectionViewLayoutAttributes(forSupplementaryViewOfKind: boundary.elementKind, with: IndexPath(item: 0, section: section))
                attribute.frame = vertical ? CGRect(x: insets.leading, y: cursor, width: size.width, height: size.height) : CGRect(x: cursor, y: insets.top, width: size.width, height: size.height)
                if boundary.pinToVisibleBounds { attribute.zIndex = 1; pinned.append(PinnedHeader(kind: boundary.elementKind, section: section, sectionStart: sectionStart, sectionEnd: 0, footer: true)) }
                supplementary[boundary.elementKind, default: [:]][section] = attribute
                cursor += vertical ? size.height : size.width
            }
            // Decoration items span the section, boundary items and content insets included.
            for decoration in layoutSection.decorationItems {
                let attribute = UICollectionViewLayoutAttributes(forDecorationViewOfKind: decoration.elementKind, with: IndexPath(item: 0, section: section))
                let frame = vertical ? CGRect(x: 0, y: sectionStart, width: bounds.width, height: cursor - sectionStart) : CGRect(x: sectionStart, y: 0, width: cursor - sectionStart, height: bounds.height)
                attribute.frame = frame.inset(by: decoration.contentInsets)
                attribute.zIndex = decoration.zIndex - 1
                decorations[decoration.elementKind, default: [:]][section] = attribute
            }
            for index in pinned.indices where pinned[index].section == section {
                let old = pinned[index]
                pinned[index] = PinnedHeader(kind: old.kind, section: section, sectionStart: old.sectionStart, sectionEnd: cursor, footer: old.footer)
            }
        }
        contentSize = vertical ? CGSize(width: bounds.width, height: cursor) : CGSize(width: cursor, height: bounds.height)
    }

    /// A pinned header's attributes for the current bounds: held at the visible top while its
    /// section scrolls past, pushed away by the end of its section. A pinned footer holds at
    /// the visible bottom from its section's start until its natural place scrolls into view.
    private func pinnedAttributes(_ header: PinnedHeader) -> UICollectionViewLayoutAttributes? {
        guard let natural = supplementary[header.kind]?[header.section], let collection = collectionView else { return nil }
        let attribute = UICollectionViewLayoutAttributes(forSupplementaryViewOfKind: header.kind, with: natural.indexPath)
        var frame = natural.frame
        let vertical = configuration.scrollDirection == .vertical
        if header.footer {
            let bottom = vertical
                ? collection.contentOffset.y + collection.bounds.height - collection.adjustedContentInset.bottom
                : collection.contentOffset.x + collection.bounds.width - collection.adjustedContentInset.right
            if vertical {
                frame.origin.y = max(min(natural.frame.minY, bottom - natural.frame.height), header.sectionStart)
            } else {
                frame.origin.x = max(min(natural.frame.minX, bottom - natural.frame.width), header.sectionStart)
            }
            attribute.zIndex = 1
            attribute.frame = frame
            return attribute
        }
        let top: CGFloat
        if vertical {
            top = collection.contentOffset.y + collection.adjustedContentInset.top
            frame.origin.y = min(max(natural.frame.minY, top), header.sectionEnd - natural.frame.height)
        } else {
            top = collection.contentOffset.x + collection.adjustedContentInset.left
            frame.origin.x = min(max(natural.frame.minX, top), header.sectionEnd - natural.frame.width)
        }
        // A pinned header rides above the cells; one being pushed away by the next section
        // slips under them (uikit/collection/pinned push: the last row covers it).
        let pushed = (vertical ? frame.minY : frame.minX) < top
        attribute.zIndex = pushed ? -1 : 1
        attribute.frame = frame
        return attribute
    }

    /// What `place` lays out: the items' frames, their anchored supplementary items, the next
    /// item to place and the size the group took (its estimated axis measured).
    private struct Placed {
        var frames: [IndexPath: CGRect] = [:]
        var supplementaries: [IndexPath: [(kind: String, frame: CGRect, zIndex: Int)]] = [:]
        var next: Int
        var size: CGSize
    }

    /// An item's height for `width` when its height is estimated: the cell's preferred fit,
    /// measured once and kept until the layout is invalidated.
    private func measuredHeight(of item: NSCollectionLayoutItem, at path: IndexPath, width: CGFloat, estimate: CGFloat) -> CGFloat {
        if let measured = measuredItems[path] { return measured }
        guard let collection = collectionView else { return estimate }
        let inner = CGSize(width: max(0, width - item.contentInsets.leading - item.contentInsets.trailing), height: estimate)
        let height = collection.selfSizedItem(at: path, estimated: inner, fixedWidth: true).height + item.contentInsets.top + item.contentInsets.bottom
        measuredItems[path] = height
        return height
    }

    /// Lays a group's subitems out in `frame`, repeating them to fill the group's axis, taking
    /// items from `from`; nested groups recurse. Fixed inter-item spacing comes out of the
    /// fractional items' share; flexible spacing spreads what is left.
    private func place(_ group: NSCollectionLayoutGroup, in frame: CGRect, section: Int, from: Int, count: Int) -> Placed {
        var placed = Placed(next: from, size: frame.size)
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
        guard !slots.isEmpty else { return placed }
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
        // A vertical group's estimated items take their measured heights along the axis.
        if !horizontal {
            var probe = item
            for index in slots.indices where probe < count {
                let slot = slots[index]
                // A nested group takes an unknown run of items: no measuring past it.
                if slot is NSCollectionLayoutGroup { break }
                if slot.layoutSize.heightDimension.isEstimated {
                    extents[index] = measuredHeight(of: slot, at: IndexPath(item: probe, section: section), width: min(slot.layoutSize.resolved(in: inner.size).width, inner.width), estimate: extents[index])
                }
                probe += 1
            }
        }
        let gap = fixed ? spacing : (slots.count > 1 ? max(spacing, (axisLength - extents.reduce(0, +)) / CGFloat(slots.count - 1)) : 0)
        // A horizontal group with an estimated height grows to its tallest item: the items with
        // estimated heights are measured first, fractional ones then take the group's height.
        var crossExtent = horizontal ? inner.height : inner.width
        if horizontal, group.layoutSize.heightDimension.isEstimated {
            var tallest: CGFloat = 0
            var probe = item
            var anyMeasured = false
            for (index, slot) in slots.enumerated() where probe < count {
                if slot is NSCollectionLayoutGroup { break }
                let size = slot.layoutSize.resolved(in: inner.size)
                if slot.layoutSize.heightDimension.isEstimated {
                    tallest = max(tallest, measuredHeight(of: slot, at: IndexPath(item: probe, section: section), width: extents[index], estimate: size.height))
                    anyMeasured = true
                } else if slot.layoutSize.heightDimension.isAbsolute {
                    tallest = max(tallest, size.height)
                    anyMeasured = true
                }
                probe += 1
            }
            if anyMeasured { crossExtent = tallest }
        }
        var position: CGFloat = horizontal ? inner.minX : inner.minY
        var used: CGFloat = 0
        for (index, slot) in slots.enumerated() {
            guard item < count else { break }
            let size = slot.layoutSize.resolved(in: inner.size)
            let extent = extents[index]
            let rounded = (position * scale).rounded() / scale
            var height = min(size.height, inner.height)
            if horizontal {
                if slot.layoutSize.heightDimension.isEstimated, !(slot is NSCollectionLayoutGroup) {
                    height = measuredHeight(of: slot, at: IndexPath(item: item, section: section), width: extent, estimate: size.height)
                } else if slot.layoutSize.heightDimension.isFractionalHeight {
                    height = crossExtent * slot.layoutSize.heightDimension.dimension
                }
            }
            let slotFrame = horizontal
                ? CGRect(x: rounded, y: inner.minY, width: extent, height: height)
                : CGRect(x: inner.minX, y: rounded, width: min(size.width, inner.width), height: extent)
            if let nested = slot as? NSCollectionLayoutGroup {
                let nestedPlaced = place(nested, in: slotFrame, section: section, from: item, count: count)
                placed.frames.merge(nestedPlaced.frames) { $1 }
                placed.supplementaries.merge(nestedPlaced.supplementaries) { $1 }
                item = nestedPlaced.next
            } else {
                let path = IndexPath(item: item, section: section)
                let itemFrame = slotFrame.inset(by: slot.contentInsets)
                placed.frames[path] = itemFrame
                if !slot.supplementaryItems.isEmpty {
                    placed.supplementaries[path] = slot.supplementaryItems.map { ($0.elementKind, $0.frame(on: itemFrame), $0.zIndex) }
                }
                item += 1
            }
            used = position + extent - (horizontal ? inner.minX : inner.minY)
            position += extent + gap
        }
        placed.next = item
        if horizontal {
            placed.size = CGSize(width: frame.width, height: group.layoutSize.heightDimension.isEstimated ? crossExtent + group.contentInsets.top + group.contentInsets.bottom : frame.height)
        } else {
            placed.size = CGSize(width: frame.width, height: group.layoutSize.heightDimension.isEstimated ? used + group.contentInsets.top + group.contentInsets.bottom : frame.height)
        }
        return placed
    }

    open override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        let items = itemAttributes.values.filter { $0.frame.intersects(rect) }.sorted { $0.indexPath < $1.indexPath }
        let pinnedKeys = Set(pinned.map { $0.kind + "#" + "\($0.section)" })
        var extras = supplementary.values.flatMap { $0.values }
            .filter { !pinnedKeys.contains(($0.representedElementKind ?? "") + "#" + "\($0.indexPath.section)") && $0.frame.intersects(rect) }
        extras += pinned.compactMap(pinnedAttributes).filter { $0.frame.intersects(rect) }
        extras += itemSupplementaries.values.flatMap { $0.values }.filter { $0.frame.intersects(rect) }
        extras.sort { $0.indexPath < $1.indexPath }
        let backgrounds = decorations.values.flatMap { $0.values }.filter { $0.frame.intersects(rect) }.sorted { $0.indexPath < $1.indexPath }
        return backgrounds + items + extras
    }

    open override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? { itemAttributes[indexPath] }
    open override func layoutAttributesForSupplementaryView(ofKind kind: String, at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        if let header = pinned.first(where: { $0.kind == kind && $0.section == indexPath.section }) { return pinnedAttributes(header) }
        if let anchored = itemSupplementaries[kind]?[indexPath] { return anchored }
        return supplementary[kind]?[indexPath.section]
    }
    open override func layoutAttributesForDecorationView(ofKind kind: String, at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? { decorations[kind]?[indexPath.section] }
    open override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool { newBounds.size != collectionView?.bounds.size }
}

extension CGRect {
    /// The rectangle inside directional insets (leading as left).
    func inset(by insets: NSDirectionalEdgeInsets) -> CGRect {
        CGRect(x: minX + insets.leading, y: minY + insets.top, width: max(0, width - insets.leading - insets.trailing), height: max(0, height - insets.top - insets.bottom))
    }
}
