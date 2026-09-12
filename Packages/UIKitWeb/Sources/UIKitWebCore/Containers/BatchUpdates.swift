// Batch updates (Docs/elements/UIKit/TableView.md, CollectionView.md): the rows or items a table
// or collection view keeps across an update, and where they go. Deletes and reloads name old
// index paths, inserts new ones, moves both, as UIKit's batch semantics have it; the rows a
// section keeps take the new indices its inserts and moved-in rows leave free, in order.
#if os(WASI)
import FoundationEssentials
#else
import Foundation
#endif

/// The changes recorded between `beginUpdates` and `endUpdates` (or in `performBatchUpdates`).
struct BatchUpdateMapping {
    /// The rows per section before the update.
    let oldCounts: [Int]
    var deletedItems: Set<IndexPath> = []
    var insertedItems: Set<IndexPath> = []
    var reloadedItems: Set<IndexPath> = []
    var moves: [IndexPath: IndexPath] = [:]
    var deletedSections = IndexSet()
    var insertedSections = IndexSet()
    var reloadedSections = IndexSet()

    init(oldCounts: [Int]) { self.oldCounts = oldCounts }

    /// The old index path of every row that survives, mapped to its new one, and whether its
    /// cell is kept (a reloaded row keeps its place but gets a new cell).
    func retained() -> (mapping: [IndexPath: IndexPath], reloaded: Set<IndexPath>) {
        var sectionMap: [Int: Int] = [:]
        var newIndex = 0
        for section in 0..<oldCounts.count where !deletedSections.contains(section) {
            while insertedSections.contains(newIndex) { newIndex += 1 }
            sectionMap[section] = newIndex
            newIndex += 1
        }
        var mapping: [IndexPath: IndexPath] = [:]
        var reloaded: Set<IndexPath> = []
        let movedIn = Set(moves.values)
        for (section, count) in oldCounts.enumerated() {
            guard let newSection = sectionMap[section] else { continue }
            let sectionReloaded = reloadedSections.contains(section)
            var newRow = 0
            func blocked(_ row: Int) -> Bool {
                let path = IndexPath(item: row, section: newSection)
                return insertedItems.contains(path) || movedIn.contains(path)
            }
            for row in 0..<count {
                let old = IndexPath(item: row, section: section)
                if deletedItems.contains(old) || moves[old] != nil { continue }
                while blocked(newRow) { newRow += 1 }
                let new = IndexPath(item: newRow, section: newSection)
                mapping[old] = new
                if reloadedItems.contains(old) || sectionReloaded { reloaded.insert(new) }
                newRow += 1
            }
        }
        for (from, to) in moves { mapping[from] = to }
        return (mapping, reloaded)
    }
}

/// The duration of UIKit's row and item animations.
let batchUpdateDuration: Double = 0.3
