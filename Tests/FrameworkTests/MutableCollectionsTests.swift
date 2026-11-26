// Foundation's mutable object collections (Packages/WebGraphics/Sources/WebFoundationFormats/
// MutableCollections.swift) as UIImageColors uses them in OldOS: an image's colours counted in an
// `NSCountedSet`, walked with an enumerator and sorted in an `NSMutableArray` by a comparator.
// Run against Foundation on macOS and Linux too, so the wasm forms behave as Apple's.
import Testing
import WebFoundation
import WebFoundationFormats

private final class Counter {
    let color: Double
    let count: Int
    init(color: Double, count: Int) {
        self.color = color
        self.count = count
    }
}

@Suite struct MutableCollectionsTests {
    @Test func aCountedSetCountsEachObject() {
        let colors = NSCountedSet(capacity: 8)
        for color in [3.0, 1, 3, 2, 3, 1] { colors.add(color) }
        #expect(colors.count == 3)
        #expect(colors.count(for: 3.0) == 3 && colors.count(for: 1.0) == 2 && colors.count(for: 9.0) == 0)
        colors.remove(3.0)
        #expect(colors.count(for: 3.0) == 2 && colors.count == 3)
        colors.remove(2.0)
        #expect(colors.count(for: 2.0) == 0 && colors.count == 2)
        #expect(NSCountedSet(array: [1, 1, 2]).count(for: 1) == 2)

        var walked: [Double] = []
        let enumerator = colors.objectEnumerator()
        while let color = enumerator.nextObject() as? Double { walked.append(color) }
        #expect(walked.sorted() == [1, 3])
        #expect(enumerator.nextObject() == nil)
    }

    @Test func aMutableArraySortsByAComparatorAndChanges() {
        let counters = NSMutableArray(capacity: 4)
        counters.add(Counter(color: 1, count: 5))
        counters.add(Counter(color: 2, count: 9))
        counters.add(Counter(color: 3, count: 5))
        let byCountDescending: Comparator = { lhs, rhs in
            let l = lhs as! Counter, r = rhs as! Counter
            return l.count < r.count ? .orderedDescending : l.count == r.count ? .orderedSame : .orderedAscending
        }
        counters.sort(comparator: byCountDescending)
        // Equal counts keep their order.
        #expect(counters.map { ($0 as! Counter).color } == [2, 1, 3])
        #expect((counters.object(at: 0) as! Counter).color == 2)
        counters.insert(Counter(color: 4, count: 1), at: 1)
        counters.removeObject(at: 0)
        #expect(counters.count == 3 && (counters.firstObject as! Counter).color == 4)
        counters.replaceObject(at: 0, with: Counter(color: 5, count: 1))
        counters.removeLastObject()
        #expect(counters.map { ($0 as! Counter).color } == [5, 1])
        counters.removeAllObjects()
        #expect(counters.count == 0)

        let numbers = NSMutableArray(array: [3, 1, 2])
        #expect(numbers.sortedArray(comparator: { ($0 as! Int) < ($1 as! Int) ? .orderedAscending : .orderedDescending }) as? [Int] == [1, 2, 3])
        numbers.remove(1)
        numbers.addObjects(from: [4, 5])
        #expect(numbers.map { $0 as! Int } == [3, 2, 4, 5])
        var reversed: [Int] = []
        let backwards = numbers.reverseObjectEnumerator()
        while let number = backwards.nextObject() as? Int { reversed.append(number) }
        #expect(reversed == [5, 4, 2, 3])
        var visited: [Int] = []
        numbers.enumerateObjects { number, index, stop in
            visited.append(index)
            if index == 1 { stop.pointee = true }
        }
        #expect(visited == [0, 1])
        let immutable: NSArray = numbers
        #expect(immutable.count == 4)
    }

    @Test func aMutableSetAddsEachObjectOnce() {
        let set = NSMutableSet(capacity: 2)
        set.add("a")
        set.add("b")
        set.add("a")
        #expect(set.count == 2 && set.contains("a"))
        set.remove("a")
        #expect(set.count == 1 && !set.contains("a"))
        set.addObjects(from: ["c", "d"])
        #expect(set.count == 3)
        set.removeAllObjects()
        #expect(set.count == 0)
    }
}
