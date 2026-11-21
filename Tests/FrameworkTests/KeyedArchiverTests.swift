// Keyed archives: an NSCoding object graph through NSKeyedArchiver and back, in both formats,
// and an archive of Foundation's collections laid out as Apple's archiver writes it (built with
// Python's plistlib from the $objects table Foundation produces). Run against Foundation on
// macOS and Linux too, so the wasm coders read and write what Apple's do.
import Testing
import WebFoundation
#if os(WASI)
import WebFoundationFormats
#endif

final class ArchivedNote: NSObject, NSCoding {
    let title: String
    let count: Int
    let pinned: Bool
    let ratio: Double
    let tags: [String]
    let created: Date
    let sizes: [String: Int]
    let child: ArchivedNote?

    init(title: String, count: Int, pinned: Bool, ratio: Double, tags: [String], created: Date, sizes: [String: Int], child: ArchivedNote?) {
        self.title = title
        self.count = count
        self.pinned = pinned
        self.ratio = ratio
        self.tags = tags
        self.created = created
        self.sizes = sizes
        self.child = child
        super.init()
    }

    func encode(with coder: NSCoder) {
        coder.encode(title, forKey: "title")
        coder.encode(count, forKey: "count")
        coder.encode(pinned, forKey: "pinned")
        coder.encode(ratio, forKey: "ratio")
        coder.encode(tags, forKey: "tags")
        coder.encode(created, forKey: "created")
        coder.encode(sizes, forKey: "sizes")
        coder.encode(child, forKey: "child")
    }

    init?(coder: NSCoder) {
        guard let title = coder.decodeObject(forKey: "title") as? String,
              let tags = coder.decodeObject(forKey: "tags") as? [String],
              let created = coder.decodeObject(forKey: "created") as? Date,
              let sizes = coder.decodeObject(forKey: "sizes") as? [String: Int] else { return nil }
        self.title = title
        count = coder.decodeInteger(forKey: "count")
        pinned = coder.decodeBool(forKey: "pinned")
        ratio = coder.decodeDouble(forKey: "ratio")
        self.tags = tags
        self.created = created
        self.sizes = sizes
        child = coder.decodeObject(forKey: "child") as? ArchivedNote
        super.init()
    }
}

@Suite struct KeyedArchiverTests {
    let note = ArchivedNote(title: "Groceries", count: 3, pinned: true, ratio: 0.75, tags: ["home", "é"],
                            created: Date(timeIntervalSinceReferenceDate: 1000), sizes: ["milk": 2],
                            child: ArchivedNote(title: "Later", count: -1, pinned: false, ratio: 0, tags: [],
                                                created: Date(timeIntervalSinceReferenceDate: 0), sizes: [:], child: nil))

    func unarchived(_ data: Data) throws -> Any? {
        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
        unarchiver.requiresSecureCoding = false
        return unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey)
    }

    func check(_ object: Any?) {
        let copy = object as? ArchivedNote
        #expect(copy?.title == "Groceries")
        #expect(copy?.count == 3)
        #expect(copy?.pinned == true)
        #expect(copy?.ratio == 0.75)
        #expect(copy?.tags == ["home", "é"])
        #expect(copy?.created == Date(timeIntervalSinceReferenceDate: 1000))
        #expect(copy?.sizes == ["milk": 2])
        #expect(copy?.child?.title == "Later")
        #expect(copy?.child?.count == -1)
        #expect(copy?.child?.child == nil)
    }

    @Test func anObjectGraphRoundTrips() throws {
        let data = try NSKeyedArchiver.archivedData(withRootObject: note, requiringSecureCoding: false)
        #expect(Array(data.prefix(8)) == Array("bplist00".utf8))
        check(try unarchived(data))
    }

    @Test func theArchiveIsApplesLayout() throws {
        let data = try NSKeyedArchiver.archivedData(withRootObject: note, requiringSecureCoding: false)
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        #expect(plist?["$archiver"] as? String == "NSKeyedArchiver")
        #expect(plist?["$version"] as? Int == 100000)
        let objects = plist?["$objects"] as? [Any] ?? []
        #expect(objects.first as? String == "$null")
        let classes = objects.compactMap { $0 as? [String: Any] }.filter { $0["$classname"] as? String == "FrameworkTests.ArchivedNote" }
        #expect(classes.count == 1)
        #expect((classes.first?["$classes"] as? [String])?.last == "NSObject")
        #expect(plist?["$top"] is [String: Any])
    }

    @Test func theXMLFormatRoundTrips() throws {
        let archiver = NSKeyedArchiver(requiringSecureCoding: false)
        archiver.outputFormat = .xml
        archiver.encode(note, forKey: NSKeyedArchiveRootObjectKey)
        archiver.finishEncoding()
        let data = archiver.encodedData
        #expect(String(decoding: data, as: UTF8.self).hasPrefix("<?xml"))
        check(try unarchived(data))
    }

    /// Foundation's archive of ["name": "Ada", "tags": ["a", "b"], "year": 1815, "when": the reference date].
    let collections: [UInt8] = [
        0x62, 0x70, 0x6c, 0x69, 0x73, 0x74, 0x30, 0x30, 0xd4, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x0a, 0x58, 0x24, 0x76,
        0x65, 0x72, 0x73, 0x69, 0x6f, 0x6e, 0x59, 0x24, 0x61, 0x72, 0x63, 0x68, 0x69, 0x76, 0x65, 0x72, 0x54, 0x24, 0x74, 0x6f,
        0x70, 0x58, 0x24, 0x6f, 0x62, 0x6a, 0x65, 0x63, 0x74, 0x73, 0x12, 0x00, 0x01, 0x86, 0xa0, 0x5f, 0x10, 0x0f, 0x4e, 0x53,
        0x4b, 0x65, 0x79, 0x65, 0x64, 0x41, 0x72, 0x63, 0x68, 0x69, 0x76, 0x65, 0x72, 0xd1, 0x08, 0x09, 0x54, 0x72, 0x6f, 0x6f,
        0x74, 0x80, 0x01, 0xaf, 0x10, 0x0f, 0x0b, 0x0c, 0x1b, 0x1c, 0x1d, 0x1e, 0x1f, 0x20, 0x25, 0x26, 0x2c, 0x2f, 0x33, 0x34,
        0x35, 0x55, 0x24, 0x6e, 0x75, 0x6c, 0x6c, 0xd3, 0x0d, 0x0e, 0x0f, 0x10, 0x15, 0x1a, 0x57, 0x4e, 0x53, 0x2e, 0x6b, 0x65,
        0x79, 0x73, 0x5a, 0x4e, 0x53, 0x2e, 0x6f, 0x62, 0x6a, 0x65, 0x63, 0x74, 0x73, 0x56, 0x24, 0x63, 0x6c, 0x61, 0x73, 0x73,
        0xa4, 0x11, 0x12, 0x13, 0x14, 0x80, 0x02, 0x80, 0x03, 0x80, 0x04, 0x80, 0x05, 0xa4, 0x16, 0x17, 0x18, 0x19, 0x80, 0x06,
        0x80, 0x07, 0x80, 0x0b, 0x80, 0x08, 0x80, 0x0a, 0x54, 0x6e, 0x61, 0x6d, 0x65, 0x54, 0x74, 0x61, 0x67, 0x73, 0x54, 0x77,
        0x68, 0x65, 0x6e, 0x54, 0x79, 0x65, 0x61, 0x72, 0x53, 0x41, 0x64, 0x61, 0xd2, 0x0e, 0x0f, 0x21, 0x24, 0xa2, 0x22, 0x23,
        0x80, 0x0c, 0x80, 0x0d, 0x80, 0x09, 0x11, 0x07, 0x17, 0xd2, 0x27, 0x28, 0x29, 0x2a, 0x5a, 0x24, 0x63, 0x6c, 0x61, 0x73,
        0x73, 0x6e, 0x61, 0x6d, 0x65, 0x58, 0x24, 0x63, 0x6c, 0x61, 0x73, 0x73, 0x65, 0x73, 0x57, 0x4e, 0x53, 0x41, 0x72, 0x72,
        0x61, 0x79, 0xa2, 0x29, 0x2b, 0x58, 0x4e, 0x53, 0x4f, 0x62, 0x6a, 0x65, 0x63, 0x74, 0xd2, 0x27, 0x28, 0x2d, 0x2e, 0x5c,
        0x4e, 0x53, 0x44, 0x69, 0x63, 0x74, 0x69, 0x6f, 0x6e, 0x61, 0x72, 0x79, 0xa2, 0x2d, 0x2b, 0xd2, 0x30, 0x0f, 0x31, 0x32,
        0x57, 0x4e, 0x53, 0x2e, 0x74, 0x69, 0x6d, 0x65, 0x23, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x80, 0x0e, 0x51,
        0x61, 0x51, 0x62, 0xd2, 0x27, 0x28, 0x36, 0x37, 0x56, 0x4e, 0x53, 0x44, 0x61, 0x74, 0x65, 0xa2, 0x36, 0x2b, 0x00, 0x08,
        0x00, 0x11, 0x00, 0x1a, 0x00, 0x24, 0x00, 0x29, 0x00, 0x32, 0x00, 0x37, 0x00, 0x49, 0x00, 0x4c, 0x00, 0x51, 0x00, 0x53,
        0x00, 0x65, 0x00, 0x6b, 0x00, 0x72, 0x00, 0x7a, 0x00, 0x85, 0x00, 0x8c, 0x00, 0x91, 0x00, 0x93, 0x00, 0x95, 0x00, 0x97,
        0x00, 0x99, 0x00, 0x9e, 0x00, 0xa0, 0x00, 0xa2, 0x00, 0xa4, 0x00, 0xa6, 0x00, 0xa8, 0x00, 0xad, 0x00, 0xb2, 0x00, 0xb7,
        0x00, 0xbc, 0x00, 0xc0, 0x00, 0xc5, 0x00, 0xc8, 0x00, 0xca, 0x00, 0xcc, 0x00, 0xce, 0x00, 0xd1, 0x00, 0xd6, 0x00, 0xe1,
        0x00, 0xea, 0x00, 0xf2, 0x00, 0xf5, 0x00, 0xfe, 0x01, 0x03, 0x01, 0x10, 0x01, 0x13, 0x01, 0x18, 0x01, 0x20, 0x01, 0x29,
        0x01, 0x2b, 0x01, 0x2d, 0x01, 0x2f, 0x01, 0x34, 0x01, 0x3b, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02, 0x01, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x38, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x01, 0x3e,
    ]

    @Test func foundationsCollectionsRead() throws {
        let dictionary = try unarchived(Data(collections)) as? [String: Any]
        #expect(dictionary?["name"] as? String == "Ada")
        #expect(dictionary?["tags"] as? [String] == ["a", "b"])
        #expect(dictionary?["year"] as? Int == 1815)
        #expect(dictionary?["when"] as? Date == Date(timeIntervalSinceReferenceDate: 0))
    }

    @Test func collectionsRoundTrip() throws {
        let value: [String: Any] = ["name": "Ada", "tags": ["a", "b"], "year": 1815, "when": Date(timeIntervalSinceReferenceDate: 0)]
        let data = try NSKeyedArchiver.archivedData(withRootObject: value, requiringSecureCoding: false)
        let dictionary = try unarchived(data) as? [String: Any]
        #expect(dictionary?["name"] as? String == "Ada")
        #expect(dictionary?["tags"] as? [String] == ["a", "b"])
        #expect(dictionary?["year"] as? Int == 1815)
        #expect(dictionary?["when"] as? Date == Date(timeIntervalSinceReferenceDate: 0))
    }

    @Test func dataThatIsNoArchiveThrows() {
        #expect(throws: (any Error).self) { try NSKeyedUnarchiver(forReadingFrom: Data([1, 2, 3])) }
    }

    #if os(WASI)
    @Test func aPropertyListThatIsNoArchiveThrows() throws {
        let plain = try PropertyListSerialization.data(fromPropertyList: ["a": 1], format: .binary, options: 0)
        #expect(throws: (any Error).self) { try NSKeyedUnarchiver(forReadingFrom: plain) }
    }

    @Test func secureCodingRefusesAClassWithoutIt() {
        #expect(throws: (any Error).self) { try NSKeyedArchiver.archivedData(withRootObject: note, requiringSecureCoding: true) }
    }
    #endif
}
