// Diffable data sources and cell registrations (Docs/elements/UIKit/CollectionView.md): a
// snapshot of section and item identifiers applied to a table or collection view, which
// reloads to match (differences are not animated yet), and registrations that configure cells
// and supplementary views by item.
#if os(WASI)
import FoundationEssentials
#else
import Foundation
#endif

/// A representation of the state of the data in a view at a specific point in time.
public struct NSDiffableDataSourceSnapshot<SectionIdentifierType: Hashable & Sendable, ItemIdentifierType: Hashable & Sendable>: Sendable {
    public private(set) var sectionIdentifiers: [SectionIdentifierType] = []
    private var items: [SectionIdentifierType: [ItemIdentifierType]] = [:]
    private var reloaded: Set<ItemIdentifierType> = []
    private var reconfigured: Set<ItemIdentifierType> = []
    private var reloadedSections: Set<SectionIdentifierType> = []

    public init() {}

    public var numberOfSections: Int { sectionIdentifiers.count }
    public var numberOfItems: Int { sectionIdentifiers.reduce(0) { $0 + (items[$1]?.count ?? 0) } }
    public var itemIdentifiers: [ItemIdentifierType] { sectionIdentifiers.flatMap { items[$0] ?? [] } }
    public var reloadedItemIdentifiers: [ItemIdentifierType] { Array(reloaded) }
    public var reconfiguredItemIdentifiers: [ItemIdentifierType] { Array(reconfigured) }
    public var reloadedSectionIdentifiers: [SectionIdentifierType] { Array(reloadedSections) }

    public func numberOfItems(inSection identifier: SectionIdentifierType) -> Int { items[identifier]?.count ?? 0 }
    public func itemIdentifiers(inSection identifier: SectionIdentifierType) -> [ItemIdentifierType] { items[identifier] ?? [] }
    public func sectionIdentifier(containingItem identifier: ItemIdentifierType) -> SectionIdentifierType? {
        sectionIdentifiers.first { items[$0]?.contains(identifier) == true }
    }
    public func indexOfItem(_ identifier: ItemIdentifierType) -> Int? {
        var index = 0
        for section in sectionIdentifiers {
            if let position = items[section]?.firstIndex(of: identifier) { return index + position }
            index += items[section]?.count ?? 0
        }
        return nil
    }
    public func indexOfSection(_ identifier: SectionIdentifierType) -> Int? { sectionIdentifiers.firstIndex(of: identifier) }

    public mutating func appendSections(_ identifiers: [SectionIdentifierType]) {
        for identifier in identifiers where !sectionIdentifiers.contains(identifier) {
            sectionIdentifiers.append(identifier)
            items[identifier] = []
        }
    }

    public mutating func insertSections(_ identifiers: [SectionIdentifierType], beforeSection toIdentifier: SectionIdentifierType) {
        guard let index = sectionIdentifiers.firstIndex(of: toIdentifier) else { return appendSections(identifiers) }
        deleteSections(identifiers)
        let at = min(index, sectionIdentifiers.count)
        sectionIdentifiers.insert(contentsOf: identifiers, at: at)
        for identifier in identifiers where items[identifier] == nil { items[identifier] = [] }
    }

    public mutating func insertSections(_ identifiers: [SectionIdentifierType], afterSection toIdentifier: SectionIdentifierType) {
        guard let index = sectionIdentifiers.firstIndex(of: toIdentifier) else { return appendSections(identifiers) }
        deleteSections(identifiers)
        let at = min(index + 1, sectionIdentifiers.count)
        sectionIdentifiers.insert(contentsOf: identifiers, at: at)
        for identifier in identifiers where items[identifier] == nil { items[identifier] = [] }
    }

    public mutating func deleteSections(_ identifiers: [SectionIdentifierType]) {
        sectionIdentifiers.removeAll { identifiers.contains($0) }
        for identifier in identifiers { items.removeValue(forKey: identifier) }
    }

    public mutating func moveSection(_ identifier: SectionIdentifierType, beforeSection toIdentifier: SectionIdentifierType) {
        guard let from = sectionIdentifiers.firstIndex(of: identifier) else { return }
        sectionIdentifiers.remove(at: from)
        guard let to = sectionIdentifiers.firstIndex(of: toIdentifier) else { sectionIdentifiers.append(identifier); return }
        sectionIdentifiers.insert(identifier, at: to)
    }

    public mutating func reloadSections(_ identifiers: [SectionIdentifierType]) { reloadedSections.formUnion(identifiers) }

    /// Appends to `section`, or to the last section when nil (the items already present move).
    public mutating func appendItems(_ identifiers: [ItemIdentifierType], toSection sectionIdentifier: SectionIdentifierType? = nil) {
        guard let section = sectionIdentifier ?? sectionIdentifiers.last else { return }
        if items[section] == nil { appendSections([section]) }
        deleteItems(identifiers)
        items[section, default: []].append(contentsOf: identifiers)
    }

    public mutating func insertItems(_ identifiers: [ItemIdentifierType], beforeItem beforeIdentifier: ItemIdentifierType) {
        insert(identifiers, relativeTo: beforeIdentifier, after: false)
    }

    public mutating func insertItems(_ identifiers: [ItemIdentifierType], afterItem afterIdentifier: ItemIdentifierType) {
        insert(identifiers, relativeTo: afterIdentifier, after: true)
    }

    private mutating func insert(_ identifiers: [ItemIdentifierType], relativeTo anchor: ItemIdentifierType, after: Bool) {
        deleteItems(identifiers)
        guard let section = sectionIdentifier(containingItem: anchor), let index = items[section]?.firstIndex(of: anchor) else { return }
        items[section]?.insert(contentsOf: identifiers, at: after ? index + 1 : index)
    }

    public mutating func deleteItems(_ identifiers: [ItemIdentifierType]) {
        for section in sectionIdentifiers { items[section]?.removeAll { identifiers.contains($0) } }
    }

    public mutating func deleteAllItems() {
        sectionIdentifiers.removeAll()
        items.removeAll()
    }

    public mutating func moveItem(_ identifier: ItemIdentifierType, beforeItem toIdentifier: ItemIdentifierType) {
        deleteItems([identifier])
        insertItems([identifier], beforeItem: toIdentifier)
    }

    public mutating func moveItem(_ identifier: ItemIdentifierType, afterItem toIdentifier: ItemIdentifierType) {
        deleteItems([identifier])
        insertItems([identifier], afterItem: toIdentifier)
    }

    public mutating func reloadItems(_ identifiers: [ItemIdentifierType]) { reloaded.formUnion(identifiers) }
    public mutating func reconfigureItems(_ identifiers: [ItemIdentifierType]) { reconfigured.formUnion(identifiers) }
}

/// The shared bookkeeping: the applied snapshot and lookups by index path.
@MainActor
final class DiffableState<SectionIdentifierType: Hashable & Sendable, ItemIdentifierType: Hashable & Sendable> {
    var snapshot = NSDiffableDataSourceSnapshot<SectionIdentifierType, ItemIdentifierType>()

    func itemIdentifier(for indexPath: IndexPath) -> ItemIdentifierType? {
        guard snapshot.sectionIdentifiers.indices.contains(indexPath.section) else { return nil }
        let items = snapshot.itemIdentifiers(inSection: snapshot.sectionIdentifiers[indexPath.section])
        return items.indices.contains(indexPath.item) ? items[indexPath.item] : nil
    }

    func indexPath(for identifier: ItemIdentifierType) -> IndexPath? {
        for (section, sectionIdentifier) in snapshot.sectionIdentifiers.enumerated() {
            if let item = snapshot.itemIdentifiers(inSection: sectionIdentifier).firstIndex(of: identifier) { return IndexPath(item: item, section: section) }
        }
        return nil
    }

    func sectionIdentifier(for index: Int) -> SectionIdentifierType? {
        snapshot.sectionIdentifiers.indices.contains(index) ? snapshot.sectionIdentifiers[index] : nil
    }
}

extension UICollectionView {
    /// A registration for the collection view's cells (`dequeueConfiguredReusableCell`).
    public struct CellRegistration<Cell: UICollectionViewCell, Item> {
        public typealias Handler = (Cell, IndexPath, Item) -> Void
        let identifier: String
        let handler: Handler
        public init(handler: @escaping Handler) {
            identifier = "registration.\(Cell.self).\(Item.self).\(UICollectionView.nextRegistration())"
            self.handler = handler
        }
    }

    /// A registration for the collection view's supplementary views.
    public struct SupplementaryRegistration<Supplementary: UICollectionReusableView> {
        public typealias Handler = (Supplementary, String, IndexPath) -> Void
        let identifier: String
        let elementKind: String
        let handler: Handler
        public init(elementKind: String, handler: @escaping Handler) {
            identifier = "registration.\(Supplementary.self).\(UICollectionView.nextRegistration())"
            self.elementKind = elementKind
            self.handler = handler
        }
    }

    nonisolated(unsafe) private static var registrationCounter = 0
    nonisolated static func nextRegistration() -> Int {
        registrationCounter += 1
        return registrationCounter
    }

    public func dequeueConfiguredReusableCell<Cell: UICollectionViewCell, Item>(using registration: CellRegistration<Cell, Item>, for indexPath: IndexPath, item: Item?) -> Cell {
        if !hasRegisteredCell(withIdentifier: registration.identifier) { register(Cell.self, forCellWithReuseIdentifier: registration.identifier) }
        let cell = dequeueReusableCell(withReuseIdentifier: registration.identifier, for: indexPath) as! Cell
        if let item { registration.handler(cell, indexPath, item) }
        return cell
    }

    public func dequeueConfiguredReusableSupplementary<Supplementary: UICollectionReusableView>(using registration: SupplementaryRegistration<Supplementary>, for indexPath: IndexPath) -> Supplementary {
        register(Supplementary.self, forSupplementaryViewOfKind: registration.elementKind, withReuseIdentifier: registration.identifier)
        let view = dequeueReusableSupplementaryView(ofKind: registration.elementKind, withReuseIdentifier: registration.identifier, for: indexPath) as! Supplementary
        registration.handler(view, registration.elementKind, indexPath)
        return view
    }
}

/// A collection view data source driven by snapshots.
@MainActor
open class UICollectionViewDiffableDataSource<SectionIdentifierType: Hashable & Sendable, ItemIdentifierType: Hashable & Sendable>: NSObject, UICollectionViewDataSource {
    public typealias CellProvider = (UICollectionView, IndexPath, ItemIdentifierType) -> UICollectionViewCell?
    public typealias SupplementaryViewProvider = (UICollectionView, String, IndexPath) -> UICollectionReusableView?

    private weak var collectionView: UICollectionView?
    private let cellProvider: CellProvider
    private let state = DiffableState<SectionIdentifierType, ItemIdentifierType>()
    open var supplementaryViewProvider: SupplementaryViewProvider?

    public init(collectionView: UICollectionView, cellProvider: @escaping CellProvider) {
        self.collectionView = collectionView
        self.cellProvider = cellProvider
        super.init()
        collectionView.dataSource = self
    }

    /// Applies the snapshot: the view reloads to match (differences are not animated).
    open func apply(_ snapshot: NSDiffableDataSourceSnapshot<SectionIdentifierType, ItemIdentifierType>, animatingDifferences: Bool = true, completion: (() -> Void)? = nil) {
        state.snapshot = snapshot
        collectionView?.reloadData()
        if let completion { UIKitScene.shared.schedule(after: 0) { completion() } }
    }

    open func applySnapshotUsingReloadData(_ snapshot: NSDiffableDataSourceSnapshot<SectionIdentifierType, ItemIdentifierType>, completion: (() -> Void)? = nil) {
        apply(snapshot, animatingDifferences: false, completion: completion)
    }

    open func snapshot() -> NSDiffableDataSourceSnapshot<SectionIdentifierType, ItemIdentifierType> { state.snapshot }
    open func itemIdentifier(for indexPath: IndexPath) -> ItemIdentifierType? { state.itemIdentifier(for: indexPath) }
    open func indexPath(for itemIdentifier: ItemIdentifierType) -> IndexPath? { state.indexPath(for: itemIdentifier) }
    open func sectionIdentifier(for index: Int) -> SectionIdentifierType? { state.sectionIdentifier(for: index) }

    public func numberOfSections(in collectionView: UICollectionView) -> Int { state.snapshot.numberOfSections }
    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        state.sectionIdentifier(for: section).map { state.snapshot.numberOfItems(inSection: $0) } ?? 0
    }
    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let item = state.itemIdentifier(for: indexPath), let cell = cellProvider(collectionView, indexPath, item) else { return UICollectionViewCell(frame: .zero) }
        return cell
    }
    public func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        supplementaryViewProvider?(collectionView, kind, indexPath) ?? UICollectionReusableView(frame: .zero)
    }
}

/// A table view data source driven by snapshots.
@MainActor
open class UITableViewDiffableDataSource<SectionIdentifierType: Hashable & Sendable, ItemIdentifierType: Hashable & Sendable>: NSObject, UITableViewDataSource {
    public typealias CellProvider = (UITableView, IndexPath, ItemIdentifierType) -> UITableViewCell?

    private weak var tableView: UITableView?
    private let cellProvider: CellProvider
    private let state = DiffableState<SectionIdentifierType, ItemIdentifierType>()
    open var defaultRowAnimation: UITableView.RowAnimation = .automatic

    public init(tableView: UITableView, cellProvider: @escaping CellProvider) {
        self.tableView = tableView
        self.cellProvider = cellProvider
        super.init()
        tableView.dataSource = self
    }

    open func apply(_ snapshot: NSDiffableDataSourceSnapshot<SectionIdentifierType, ItemIdentifierType>, animatingDifferences: Bool = true, completion: (() -> Void)? = nil) {
        state.snapshot = snapshot
        tableView?.reloadData()
        if let completion { UIKitScene.shared.schedule(after: 0) { completion() } }
    }

    open func applySnapshotUsingReloadData(_ snapshot: NSDiffableDataSourceSnapshot<SectionIdentifierType, ItemIdentifierType>, completion: (() -> Void)? = nil) {
        apply(snapshot, animatingDifferences: false, completion: completion)
    }

    open func snapshot() -> NSDiffableDataSourceSnapshot<SectionIdentifierType, ItemIdentifierType> { state.snapshot }
    open func itemIdentifier(for indexPath: IndexPath) -> ItemIdentifierType? { state.itemIdentifier(for: indexPath) }
    open func indexPath(for itemIdentifier: ItemIdentifierType) -> IndexPath? { state.indexPath(for: itemIdentifier) }
    open func sectionIdentifier(for index: Int) -> SectionIdentifierType? { state.sectionIdentifier(for: index) }

    /// The section titles a subclass supplies (UIKit's `tableView(_:titleForHeaderInSection:)` override).
    open func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { nil }
    open func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? { nil }

    public func numberOfSections(in tableView: UITableView) -> Int { state.snapshot.numberOfSections }
    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        state.sectionIdentifier(for: section).map { state.snapshot.numberOfItems(inSection: $0) } ?? 0
    }
    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let item = state.itemIdentifier(for: indexPath), let cell = cellProvider(tableView, indexPath, item) else { return UITableViewCell(style: .default, reuseIdentifier: nil) }
        return cell
    }
}
