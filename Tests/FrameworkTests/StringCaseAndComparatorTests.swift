// Foundation's locale-taking case changes and its string sort comparators, as apps sort a list of
// names (`sorted(using: .localizedStandard)`, `KeyPathComparator(\.name, comparator:
// .localizedStandard)`) and title a label in the user's language. The cases run against
// Foundation on macOS and Linux and WebFoundation's forms on wasm.
import Testing
import WebFoundation

private struct Item: Sendable { let name: String }

@Suite struct StringCaseAndComparatorTests {
    private let turkish = Locale(identifier: "tr_TR")
    private let english = Locale(identifier: "en_US")

    @Test func caseChangesFollowTheLocale() {
        #expect("I".lowercased(with: turkish) == "ı")
        #expect("Iİ".lowercased(with: turkish) == "ıi")
        #expect("i".uppercased(with: turkish) == "İ")
        #expect("i".uppercased(with: english) == "I")
        #expect("I".lowercased(with: english) == "i")
        #expect("straße".uppercased(with: nil) == "STRASSE")
        #expect("ÉCOLE".lowercased(with: nil) == "école")
        #expect("istanbul ılık".capitalized(with: turkish) == "İstanbul Ilık")
        #expect("hello wORLD".capitalized(with: english) == "Hello World")
        #expect("hello wORLD".capitalized == "Hello World")
        #expect("hello wORLD"[...].capitalized == "Hello World")
    }

    // Issues 213 and 214: titlecase forms, words that start with digits or an apostrophe, final
    // sigma and Turkish i with an accent after it. Linux's Foundation maps these its own way.
    #if canImport(Darwin) || os(WASI)
    @Test func titlecaseFinalSigmaAndAccentedTurkishI() {
        #expect("ßeta".capitalized(with: nil) == "Sseta")
        // capitalized(with:) titles a word's first letter or digit, as Apple's does.
        #expect("123hello".capitalized(with: nil) == "123hello")
        #expect("'hello".capitalized(with: nil) == "'Hello")
        // NSString titles a letter after a digit too, as Core Foundation does.
        #expect(NSString(string: "123hello").capitalized(with: nil) == "123Hello")
        #expect("ΟΣ".lowercased(with: nil) == "ος")
        #expect("i\u{0301}".uppercased(with: turkish) == "İ\u{0301}")
        #expect("I\u{0301}".lowercased(with: turkish) == "ı\u{0301}")
    }
    #endif

    @Test func nsStringCaseChanges() {
        let word = NSString(string: "ÉCOLE")
        #expect(word.lowercased(with: nil) == "école")
        #expect(NSString(string: "i").uppercased(with: turkish) == "İ")
        #expect(NSString(string: "hello world").capitalized(with: nil) == "Hello World")
    }

    @Test func lexicalComparatorSortsByScalars() {
        let lexical = String.StandardComparator.lexical
        #expect(["b", "B", "a"].sorted(using: lexical) == ["B", "a", "b"])
        #expect(lexical.compare("a", "B") == .orderedDescending)
        let descending = String.StandardComparator(lexical, order: .reverse)
        #expect(["b", "B", "a"].sorted(using: descending) == ["b", "a", "B"])
        #expect(descending != lexical && descending.order == .reverse)
        #expect(String.StandardComparator(descending) == lexical)
    }

    @Test func optionalKeyPathsSortNilFirst() {
        struct Entry: Sendable { let title: String?; let rank: Int? }
        let entries = [Entry(title: "b", rank: 2), Entry(title: nil, rank: nil), Entry(title: "a", rank: 1)]
        #expect(entries.sorted(using: KeyPathComparator(\Entry.rank)).map(\.rank) == [nil, 1, 2])
        #expect(entries.sorted(using: KeyPathComparator(\Entry.rank, order: .reverse)).map(\.rank) == [2, 1, nil])
        #expect(entries.sorted(using: KeyPathComparator(\Entry.title, comparator: String.StandardComparator.lexical)).map(\.title) == [nil, "a", "b"])
    }

    #if os(WASI)
    // Foundation's formatters are Sendable: an app keeps one in a `static let` (Hipstapaper).
    private static let shared: DateFormatter = { let formatter = DateFormatter(); formatter.dateStyle = .short; return formatter }()
    @Test func formattersAreSendable() {
        func sendable<T: Sendable>(_: T.Type) {}
        sendable(DateFormatter.self)
        sendable(NumberFormatter.self)
        sendable(RelativeDateTimeFormatter.self)
        sendable(ListFormatter.self)
        #expect(Self.shared.dateStyle == .short)
    }
    #endif

    // Linux's Foundation keeps only `.lexical`; the localized comparators are Apple's and wasm's.
    #if canImport(Darwin) || os(WASI)
    @Test func localizedComparatorsSort() {
        #expect(["File 10", "file 2", "File 1"].sorted(using: .localizedStandard) == ["File 1", "file 2", "File 10"])
        #expect(["b", "B", "a", "A"].sorted(using: String.StandardComparator.localized) == ["a", "A", "b", "B"])
        let descending = String.StandardComparator(.localizedStandard, order: .reverse)
        #expect(["2", "10", "1"].sorted(using: descending) == ["10", "2", "1"])
        let items = [Item(name: "Track 12"), Item(name: "track 3"), Item(name: "Track 1")]
        let sorted = items.sorted(using: KeyPathComparator(\Item.name, comparator: .localizedStandard))
        #expect(sorted.map(\.name) == ["Track 1", "track 3", "Track 12"])
        #expect(String.StandardComparator.localizedStandard.compare("File 2", "File 10") == .orderedAscending)
        #expect(String.StandardComparator.localizedStandard == .localizedStandard)
        #expect(String.StandardComparator.localizedStandard != .lexical)
        #expect(String.StandardComparator.localized != .localizedStandard)
    }
    #endif
}
