// Core Data (WebCoreData) against Tests/CoreDataTests/Library.xcdatamodeld, whose classes the
// CoreDataModel plugin generates as Xcode's "Class Definition" codegen would: Author, Book (with
// the Ebook subentity), Tag and Chapter, plus Note, whose codegen is "Category/Extension" (the
// class is written below, the properties are generated).
//
// What the tests prove: the predicate format parser and evaluation, the generated model
// (entities, inverses, subentities, configurations, defaults), the generated accessors, fetches
// (predicates, sort descriptors, limits, offsets, subentities, dictionaries, IDs, counts), inverse
// maintenance, the delete rules (cascade, nullify, deny), validation, rollback, saves reaching
// other containers on the same store and other contexts on the same coordinator, child contexts,
// batch deletes, the store's JSON round trip, and `@FetchRequest` / `@SectionedFetchRequest`
// views following inserts and saves.
//
// Not proven here: SQL semantics, faulting, migrations, the host's storage (the native test
// process shares `_ModelStore.Host` with the SwiftData tests, so it is not set here).
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless
@testable import WebCoreData

// Foundation (re-exported natively) has its own classes by these names; the tests and the
// generated code mean Core Data's.
public typealias NSPredicate = WebCoreData.NSPredicate
public typealias NSCompoundPredicate = WebCoreData.NSCompoundPredicate
public typealias NSComparisonPredicate = WebCoreData.NSComparisonPredicate
public typealias NSExpression = WebCoreData.NSExpression
public typealias NSSortDescriptor = WebCoreData.NSSortDescriptor
public typealias NSSet = WebCoreData.NSSet
public typealias NSOrderedSet = WebCoreData.NSOrderedSet
public typealias NSMutableSet = WebCoreData.NSMutableSet
public typealias NSMutableOrderedSet = WebCoreData.NSMutableOrderedSet

/// The Note entity's class ("Category/Extension" codegen: the app writes the class).
class Note: NSManagedObject, @unchecked Sendable {}

@MainActor
@Suite(.serialized)
struct CoreDataTests {
    init() {
        // The SwiftData tests in this process install their own host storage and count its
        // writes; these stores stay in process memory.
        _CDStoreData._usesHost = false
    }

    // MARK: Helpers

    /// A container over the Library model with an in-memory store, or a named store shared by
    /// every container that opens the same name.
    private func container(store: String? = nil) throws -> NSPersistentContainer {
        let container = NSPersistentContainer(name: store ?? "Library", managedObjectModel: _SwiftUIWebCoreDataModel_Library.model)
        if store == nil {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }
        var failure: (any Error)?
        container.loadPersistentStores { _, error in failure = error }
        if let failure { throw failure }
        return container
    }

    private func uniqueName(_ prefix: String) -> String { "\(prefix)-\(UUID().uuidString)" }

    private func books(_ context: NSManagedObjectContext, _ predicate: NSPredicate? = nil, sortedBy key: String = "title", ascending: Bool = true) throws -> [Book] {
        let request = NSFetchRequest<Book>(entityName: "Book")
        request.predicate = predicate
        request.sortDescriptors = [NSSortDescriptor(key: key, ascending: ascending)]
        return try context.fetch(request)
    }

    @discardableResult
    private func book(_ title: String, pages: Int32 = 0, rating: Double = 0, author: Author? = nil, in context: NSManagedObjectContext) -> Book {
        let book = Book(context: context)
        book.title = title
        book.pages = pages
        book.rating = rating
        book.author = author
        return book
    }

    private func author(_ name: String, in context: NSManagedObjectContext) -> Author {
        let author = Author(context: context)
        author.name = name
        return author
    }

    private func code(of error: (any Error)?) -> Int? {
        guard let error else { return nil }
        return (error as Any as? NSError)?.code
    }

    private func settled(_ condition: @escaping @MainActor () -> Bool) async {
        for _ in 0..<1000 { if await MainActor.run(body: condition) { return }; await Task.yield(); try? await Task.sleep(nanoseconds: 1_000_000) }
    }

    // MARK: Predicates

    @Test func predicateFormatsEvaluateOverDictionaries() {
        let dune: [String: Any] = ["title": "Dune", "pages": 412, "rating": 4.5, "tags": ["sf", "classic"], "author": ["name": "Frank Herbert"]]
        let emma: [String: Any] = ["title": "Emma", "pages": 474, "rating": 3.9, "tags": ["classic"], "author": ["name": "Jane Austen"]]

        #expect(NSPredicate(format: "title == %@", "Dune").evaluate(with: dune))
        #expect(!NSPredicate(format: "title == %@", "Dune").evaluate(with: emma))
        #expect(NSPredicate(format: "pages > %d", 450).evaluate(with: emma))
        #expect(NSPredicate(format: "pages BETWEEN {400, 420}").evaluate(with: dune))
        #expect(NSPredicate(format: "title BEGINSWITH[c] %@", "du").evaluate(with: dune))
        #expect(NSPredicate(format: "title CONTAINS[cd] 'MM'").evaluate(with: emma))
        #expect(NSPredicate(format: "title ENDSWITH 'ne'").evaluate(with: dune))
        #expect(NSPredicate(format: "title LIKE 'D?n*'").evaluate(with: dune))
        #expect(NSPredicate(format: "title IN %@", ["Emma", "Persuasion"]).evaluate(with: emma))
        #expect(NSPredicate(format: "ANY tags == 'sf'").evaluate(with: dune))
        #expect(!NSPredicate(format: "ANY tags == 'sf'").evaluate(with: emma))
        #expect(NSPredicate(format: "tags.@count == 2").evaluate(with: dune))
        #expect(NSPredicate(format: "author.name == %@", "Jane Austen").evaluate(with: emma))
        #expect(NSPredicate(format: "%K == %@", "title", "Emma").evaluate(with: emma))
        #expect(NSPredicate(format: "rating > 4 AND pages < 500").evaluate(with: dune))
        #expect(NSPredicate(format: "rating > 4 OR title == 'Emma'").evaluate(with: emma))
        #expect(NSPredicate(format: "NOT (rating > 4)").evaluate(with: emma))
        #expect(NSPredicate(format: "title == $name").withSubstitutionVariables(["name": "Dune"]).evaluate(with: dune))
        #expect(NSPredicate(value: true).evaluate(with: dune))

        let compound = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "pages > 400"), NSPredicate(format: "rating < 4"),
        ])
        #expect(compound.evaluate(with: emma) && !compound.evaluate(with: dune))
        #expect(NSPredicate(format: "title == %@", "Dune").predicateFormat == "title == \"Dune\"")
    }

    @Test func sortDescriptorsSortDictionaries() {
        let rows: [[String: Any]] = [["title": "b", "n": 2], ["title": "a", "n": 2], ["title": "c", "n": 1]]
        let sorted = NSSortDescriptor._sort(rows, by: [NSSortDescriptor(key: "n", ascending: false), NSSortDescriptor(key: "title", ascending: true)])
        #expect(sorted.compactMap { ($0 as? [String: Any])?["title"] as? String } == ["a", "b", "c"])
    }

    // MARK: The generated model

    @Test func generatedModelDescribesTheEntities() throws {
        let model = _SwiftUIWebCoreDataModel_Library.model
        #expect(Set(model.entitiesByName.keys) == ["Author", "Book", "Ebook", "Tag", "Chapter", "Note"])

        let book = try #require(model.entitiesByName["Book"])
        let ebook = try #require(model.entitiesByName["Ebook"])
        #expect(ebook.superentity === book)
        #expect(book.subentities.map(\.name) == ["Ebook"])
        #expect(ebook.attributesByName["title"] != nil)   // inherited
        #expect(ebook.attributesByName["fileSize"]?.attributeType == .integer64AttributeType)
        #expect(book.attributesByName["pages"]?.attributeType == .integer32AttributeType)

        let author = try #require(book.relationshipsByName["author"])
        #expect(!author.isToMany && author.destinationEntity?.name == "Author")
        #expect(author.inverseRelationship?.name == "books")
        #expect(author.inverseRelationship?.deleteRule == .cascadeDeleteRule)
        let chapters = try #require(book.relationshipsByName["chapters"])
        #expect(chapters.isToMany && chapters.isOrdered)
        #expect(model.entitiesByName["Tag"]?.relationshipsByName["books"]?.deleteRule == .denyDeleteRule)

        #expect(model.entities(forConfigurationName: "Shelf")?.compactMap(\.name).sorted() == ["Author", "Book"])
        #expect(Book.entity() === book)
        #expect(Ebook.entity() === ebook)
        #expect(Note.entity().name == "Note")
    }

    @Test func containerFindsTheGeneratedModelByName() throws {
        let container = NSPersistentContainer(name: "Library")
        #expect(container.managedObjectModel.entitiesByName["Book"] != nil)
        container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        var failure: (any Error)?
        container.loadPersistentStores { _, error in failure = error }
        #expect(failure == nil)
        let book = NSEntityDescription.insertNewObject(forEntityName: "Book", into: container.viewContext)
        #expect(book is Book)
    }

    // MARK: Objects and fetches

    @Test func defaultsAndGeneratedAccessors() throws {
        let context = try container().viewContext
        let book = Book(context: context)
        #expect(book.pages == 0 && book.rating == 0 && !book.isRead)
        #expect(book.price == Decimal(0))
        #expect(book.title == nil && book.copies == nil && book.author == nil)
        #expect(book.isInserted && context.hasChanges)

        let isbn = UUID()
        book.title = "Dune"
        book.pages = 412
        book.isRead = true
        book.isbn = isbn
        book.copies = NSNumber(value: 3)
        book.keywords = ["desert", "spice"]
        book.price = Decimal(12.5)
        #expect(book.title == "Dune" && book.pages == 412 && book.isRead && book.isbn == isbn)
        #expect(book.copies?.intValue == 3)
        #expect(book.keywords == ["desert", "spice"])
        #expect(book.price == Decimal(12.5))
        #expect(book.value(forKey: "pages") as? Int == 412)
        book.setValue(500, forKey: "pages")
        #expect(book.pages == 500)

        let note = Note(context: context)
        note.text = "remember"
        #expect(note.text == "remember" && note.entity.name == "Note")
    }

    @Test func fetchesFilterSortAndLimit() throws {
        let context = try container().viewContext
        let herbert = author("Frank Herbert", in: context)
        let leGuin = author("Ursula K. Le Guin", in: context)
        book("Dune", pages: 412, rating: 4.5, author: herbert, in: context)
        book("Children of Dune", pages: 444, rating: 4.0, author: herbert, in: context)
        book("The Dispossessed", pages: 387, rating: 4.3, author: leGuin, in: context)
        book("A Wizard of Earthsea", pages: 183, rating: 4.2, author: leGuin, in: context)
        try context.save()

        #expect(try books(context).compactMap(\.title) == ["A Wizard of Earthsea", "Children of Dune", "Dune", "The Dispossessed"])
        #expect(try books(context, sortedBy: "pages", ascending: false).map(\.pages) == [444, 412, 387, 183])
        #expect(try books(context, NSPredicate(format: "author.name == %@", "Ursula K. Le Guin")).compactMap(\.title) == ["A Wizard of Earthsea", "The Dispossessed"])
        #expect(try books(context, NSPredicate(format: "title CONTAINS[c] %@", "dune")).count == 2)
        #expect(try books(context, NSPredicate(format: "rating >= 4.3")).count == 2)

        let request = NSFetchRequest<Book>(entityName: "Book")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Book.rating, ascending: false)]
        request.fetchLimit = 2
        request.fetchOffset = 1
        #expect(try context.fetch(request).compactMap(\.title) == ["The Dispossessed", "A Wizard of Earthsea"])
        #expect(try context.count(for: NSFetchRequest<Book>(entityName: "Book")) == 4)

        let authors = NSFetchRequest<Author>(entityName: "Author")
        authors.predicate = NSPredicate(format: "ANY books.pages < 200")
        #expect(try context.fetch(authors).compactMap(\.name) == ["Ursula K. Le Guin"])
        authors.predicate = NSPredicate(format: "books.@count == 2")
        #expect(try context.count(for: authors) == 2)

        let titles = NSFetchRequest<[String: Any]>(entityName: "Book")
        titles.resultType = .dictionaryResultType
        titles.propertiesToFetch = ["title", "pages"]
        titles.sortDescriptors = [NSSortDescriptor(key: "pages", ascending: true)]
        let rows = try context.fetch(titles)
        #expect(rows.first?["title"] as? String == "A Wizard of Earthsea")
        #expect(rows.count == 4)

        let ids = NSFetchRequest<NSManagedObjectID>(entityName: "Book")
        ids.resultType = .managedObjectIDResultType
        let found = try context.fetch(ids)
        #expect(found.count == 4 && found.allSatisfy { !$0.isTemporaryID })
        let first = try #require(found.first)
        #expect(context.object(with: first) is Book)
        #expect(try context.existingObject(with: first).objectID == first)
    }

    @Test func subentitiesAreFetchedWithTheirParent() throws {
        let context = try container().viewContext
        book("Paper", in: context)
        let ebook = Ebook(context: context)
        ebook.title = "Pixels"
        ebook.fileSize = 2_000_000
        try context.save()

        let all = NSFetchRequest<Book>(entityName: "Book")
        #expect(try context.count(for: all) == 2)
        all.includesSubentities = false
        #expect(try context.fetch(all).compactMap(\.title) == ["Paper"])
        let ebooks = try context.fetch(NSFetchRequest<Ebook>(entityName: "Ebook"))
        #expect(ebooks.count == 1 && ebooks.first?.fileSize == 2_000_000)
    }

    @Test func inversesFollowEitherSide() throws {
        let context = try container().viewContext
        let herbert = author("Frank Herbert", in: context)
        let dune = book("Dune", author: herbert, in: context)
        #expect(herbert.books?.count == 1)
        #expect(herbert.books?.contains(dune) == true)

        let messiah = book("Dune Messiah", in: context)
        herbert.addToBooks(messiah)
        #expect(messiah.author === herbert)
        herbert.removeFromBooks(dune)
        #expect(dune.author == nil && herbert.books?.count == 1)

        let sf = Tag(context: context)
        sf.name = "sf"
        sf.addToBooks(messiah)
        #expect(messiah.tags?.count == 1)
        messiah.mutableSetValue(forKey: "tags").add(sf)
        #expect(messiah.tags?.count == 1)

        let one = Chapter(context: context)
        one.title = "One"
        let two = Chapter(context: context)
        two.title = "Two"
        let zero = Chapter(context: context)
        zero.title = "Zero"
        messiah.addToChapters(one)
        messiah.addToChapters(two)
        messiah.insertIntoChapters(zero, at: 0)
        #expect(messiah.chapters?.array.compactMap { ($0 as? Chapter)?.title } == ["Zero", "One", "Two"])
        #expect(two.book === messiah)
        messiah.removeFromChapters(at: 1)
        #expect(messiah.chapters?.array.compactMap { ($0 as? Chapter)?.title } == ["Zero", "Two"])
        #expect(one.book == nil)
    }

    // MARK: Deleting and validating

    @Test func deleteRulesCascadeNullifyAndDeny() throws {
        let context = try container().viewContext
        let herbert = author("Frank Herbert", in: context)
        let dune = book("Dune", author: herbert, in: context)
        let chapter = Chapter(context: context)
        dune.addToChapters(chapter)
        let sf = Tag(context: context)
        sf.name = "sf"
        dune.addToTags(sf)
        try context.save()

        // Tag.books is Deny: a tag with books cannot be deleted.
        context.delete(sf)
        let denied = #expect(throws: (any Error).self) { try context.save() }
        #expect(code(of: denied) == NSValidationRelationshipDeniedDeleteError)
        context.rollback()
        #expect(!sf.isDeleted && dune.tags?.count == 1)

        // Author.books is Cascade, Book.chapters is Cascade, Book.tags is Nullify.
        context.delete(herbert)
        try context.save()
        #expect(try context.count(for: NSFetchRequest<Book>(entityName: "Book")) == 0)
        #expect(try context.count(for: NSFetchRequest<Chapter>(entityName: "Chapter")) == 0)
        #expect((sf.books?.count ?? 0) == 0)

        // A tag without books goes.
        context.delete(sf)
        try context.save()
        #expect(try context.count(for: NSFetchRequest<Tag>(entityName: "Tag")) == 0)
    }

    @Test func validationAndRollback() throws {
        let context = try container().viewContext
        _ = Author(context: context)   // `name` is required
        let missing = #expect(throws: (any Error).self) { try context.save() }
        #expect(code(of: missing) == NSValidationMissingMandatoryPropertyError)
        context.rollback()
        #expect(!context.hasChanges)

        let dune = book("Dune", pages: 412, in: context)
        try context.save()
        dune.pages = 1
        dune.title = "Not Dune"
        #expect(dune.isUpdated && dune.changedValues().keys.sorted() == ["pages", "title"])
        context.rollback()
        #expect(dune.pages == 412 && dune.title == "Dune" && !dune.hasChanges)
    }

    // MARK: Contexts and stores

    @Test func savesReachAnotherContainerOnTheSameStore() throws {
        let name = uniqueName("Shelf")
        let first = try container(store: name)
        let herbert = author("Frank Herbert", in: first.viewContext)
        let dune = book("Dune", pages: 412, author: herbert, in: first.viewContext)
        dune.isbn = UUID()
        dune.price = Decimal(9.99)
        try first.viewContext.save()
        #expect(!dune.objectID.isTemporaryID)

        let second = try container(store: name)
        let found = try books(second.viewContext)
        let copy = try #require(found.first)
        #expect(found.count == 1)
        #expect(copy !== dune && copy.objectID == dune.objectID)
        #expect(copy.title == "Dune" && copy.pages == 412 && copy.isbn == dune.isbn && copy.price == Decimal(9.99))
        #expect(copy.author?.name == "Frank Herbert")
        #expect(copy.author?.books?.count == 1)

        // A change saved in the second container shows in the first at its next fetch.
        copy.title = "Dune (1965)"
        try second.viewContext.save()
        #expect(try books(first.viewContext).first?.title == "Dune (1965)")
        #expect(dune.title == "Dune (1965)")

        // An in-memory container does not see the named store.
        #expect(try books(try container().viewContext).isEmpty)
    }

    @Test func storeRowsRoundTripThroughJSON() throws {
        let isbn = UUID()
        let published = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let data = _CDStoreData(name: uniqueName("json"), persistent: false)
        data.rows["Book/p1"] = [
            "title": "Dune", "pages": Int64(412), "rating": 4.5, "isRead": true, "published": published,
            "isbn": isbn, "price": Decimal(12.5), "author": _CDRef.one("Author/p1"),
            "chapters": _CDRef.many(["Chapter/p2", "Chapter/p1"], ordered: true),
        ]
        data.rows["Author/p1"] = ["name": "Frank Herbert", "books": _CDRef.many(["Book/p1"], ordered: false)]
        data.counters = ["Book": 1, "Author": 1, "Chapter": 2]

        let copy = _CDStoreData(name: uniqueName("json"), persistent: false)
        try copy.load(from: try data.encoded())
        let row = try #require(copy.rows["Book/p1"])
        #expect(row["title"] as? String == "Dune")
        #expect(row["pages"] as? Int64 == 412)
        #expect(row["rating"] as? Double == 4.5)
        #expect(row["isRead"] as? Bool == true)
        #expect(row["published"] as? Date == published)
        #expect(row["isbn"] as? UUID == isbn)
        #expect(row["price"] as? Decimal == Decimal(12.5))
        if case .one(let key)? = row["author"] as? _CDRef { #expect(key == "Author/p1") } else { Issue.record("author") }
        if case .many(let keys, let ordered)? = row["chapters"] as? _CDRef { #expect(keys == ["Chapter/p2", "Chapter/p1"] && ordered) } else { Issue.record("chapters") }
        #expect(copy.counters == ["Book": 1, "Author": 1, "Chapter": 2])
        #expect(copy.uuid == data.uuid)
        #expect(throws: (any Error).self) { try copy.load(from: "not a store") }
    }

    @Test func childContextsSaveIntoTheirParent() throws {
        let container = try container()
        let child = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        child.parent = container.viewContext
        let draft = book("Draft", pages: 10, in: child)
        try child.save()

        // The parent holds the change; the store does not until the parent saves.
        #expect(container.viewContext.hasChanges)
        #expect(try books(container.viewContext).compactMap(\.title) == ["Draft"])
        #expect(try books(container.newBackgroundContext()).isEmpty)
        try container.viewContext.save()
        #expect(try books(container.newBackgroundContext()).compactMap(\.title) == ["Draft"])

        // An edit in the child reaches the parent's object.
        draft.pages = 20
        try child.save()
        #expect(try books(container.viewContext).first?.pages == 20)
    }

    @Test func backgroundSavesReachTheViewContext() async throws {
        let container = try container()
        #expect(try books(container.viewContext).isEmpty)
        try await container.performBackgroundTask { context in
            let book = Book(context: context)
            book.title = "From the background"
            try context.save()
        }
        #expect(try books(container.viewContext).compactMap(\.title) == ["From the background"])

        let background = container.newBackgroundContext()
        try background.performAndWait {
            let found = try books(background)
            found.first?.title = "Edited"
            try background.save()
        }
        #expect(try books(container.viewContext).first?.title == "Edited")
    }

    @Test func batchDeletesRemoveStoreRows() throws {
        let container = try container()
        let context = container.viewContext
        book("Short", pages: 50, in: context)
        book("Long", pages: 900, in: context)
        book("Longer", pages: 1200, in: context)
        try context.save()

        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "Book")
        request.predicate = NSPredicate(format: "pages > 100")
        let delete = NSBatchDeleteRequest(fetchRequest: request)
        delete.resultType = .resultTypeObjectIDs
        let result = try context.execute(delete) as? NSBatchDeleteResult
        #expect((result?.result as? [NSManagedObjectID])?.count == 2)
        #expect(try books(context).compactMap(\.title) == ["Short"])
    }

    // MARK: SwiftUI

    struct BookTitles: View {
        @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Book.title, ascending: true)]) private var books: FetchedResults<Book>
        var body: some View {
            VStack { ForEach(books) { Text($0.title ?? "") } }
        }
    }

    struct ReadingList: View {
        @SectionedFetchRequest(sectionIdentifier: \Book.isRead, sortDescriptors: [NSSortDescriptor(key: "isRead", ascending: true), NSSortDescriptor(key: "title", ascending: true)])
        private var sections: SectionedFetchResults<Bool, Book>
        var body: some View {
            VStack {
                ForEach(sections) { section in
                    Text("\(section.id ? "read" : "unread"): \(section.compactMap(\.title).joined(separator: ","))")
                }
            }
        }
    }

    private func texts(_ runtime: Runtime) -> [String] {
        runtime.root.descendants(where: { $0 is TextNode }).compactMap { ($0 as? TextNode)?.view.resolvedString }
    }

    @Test func fetchRequestFollowsInsertsAndSaves() async throws {
        let container = try container()
        let runtime = Runtime()
        runtime.mount(BookTitles().environment(\.managedObjectContext, container.viewContext))
        runtime.layout(in: CGSize(width: 320, height: 400))
        #expect(texts(runtime) == [])

        // An insert in the view context shows in the same turn.
        book("Dune", in: container.viewContext)
        runtime.layout(in: CGSize(width: 320, height: 400))
        #expect(texts(runtime) == ["Dune"])

        // A background context's save shows once the main actor takes it.
        let background = container.newBackgroundContext()
        try background.performAndWait {
            book("Beloved", in: background)
            try background.save()
        }
        await settled { runtime.layout(in: CGSize(width: 320, height: 400)); return texts(runtime).count == 2 }
        #expect(texts(runtime) == ["Beloved", "Dune"])

        // A property set on a shown object re-renders it.
        try books(container.viewContext).first { $0.title == "Dune" }?.title = "Emma"
        runtime.layout(in: CGSize(width: 320, height: 400))
        #expect(texts(runtime) == ["Beloved", "Emma"])
    }

    @Test func sectionedFetchRequestGroupsResults() throws {
        let container = try container()
        let context = container.viewContext
        book("Dune", in: context).isRead = true
        book("Emma", in: context)
        book("Beloved", in: context).isRead = true
        let runtime = Runtime()
        runtime.mount(ReadingList().environment(\.managedObjectContext, context))
        runtime.layout(in: CGSize(width: 320, height: 400))
        #expect(texts(runtime) == ["unread: Emma", "read: Beloved,Dune"])
    }

    @Test func actionsReadTheResultsOfTheLatestBody() throws {
        let container = try container()
        let runtime = Runtime()
        let size = CGSize(width: 320, height: 400)
        runtime.mount(Numbered().environment(\.managedObjectContext, container.viewContext))
        runtime.layout(in: size)
        func add() {
            let frame = runtime.probeFrames["add"]!
            runtime.pointerDown(at: CGPoint(x: frame.midX, y: frame.midY))
            runtime.pointerUp(at: CGPoint(x: frame.midX, y: frame.midY))
            runtime.layout(in: size)
        }
        // The action inserts before it reads the count, and still reads the count it rendered.
        add()
        #expect(texts(runtime).filter { $0.hasPrefix("Book") } == ["Book 1"])
        add()
        #expect(texts(runtime).filter { $0.hasPrefix("Book") } == ["Book 1", "Book 2"])
    }

    @Test func managedObjectsAreIdentifiableByIdentity() throws {
        let context = try container().viewContext
        let dune = book("Dune", in: context)
        let emma = book("Emma", in: context)
        #expect(dune.id == ObjectIdentifier(dune))
        #expect(dune.id != emma.id)
        // `ForEach` over fetched results needs no `id:`, as on Apple platforms.
        let runtime = Runtime()
        runtime.mount(Shelf().environment(\.managedObjectContext, context))
        runtime.layout(in: CGSize(width: 320, height: 400))
        #expect(texts(runtime) == ["Dune", "Emma"])
    }
}

/// Adds a book named for the count shown, inserting before reading the count (as an app's
/// `Note(context:)` then `note.text = "Note \(notes.count + 1)"` does).
private struct Numbered: View {
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "title", ascending: true)]) private var books: FetchedResults<Book>
    var body: some View {
        VStack {
            ForEach(books) { Text($0.title ?? "") }
            Button("Add") {
                let book = Book(context: context)
                book.title = "Book \(books.count + 1)"
            }._probe("add")
        }
    }
}

/// A list of every book by title, with `ForEach` keyed by the objects themselves.
private struct Shelf: View {
    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "title", ascending: true)]) private var books: FetchedResults<Book>
    var body: some View {
        VStack { ForEach(books) { Text($0.title ?? "") } }
    }
}
