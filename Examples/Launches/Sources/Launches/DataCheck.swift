// SwiftData as an app writes it (pf-swiftdata): two @Model classes with a unique attribute and
// an inverse relationship, a named container that persists (localStorage in the browser), one
// Visit with a Note inserted per launch and the whole table read back — and, in the same
// process, a second container of the same name opened to count what the first one saved.
import Foundation
import SwiftData
import SwiftUI

@Model final class Visit {
    @Attribute(.unique) var number: Int
    var at: Date
    @Relationship(inverse: \Note.visit) var notes: [Note] = []
    init(number: Int, at: Date) {
        self.number = number
        self.at = at
    }
}

@Model final class Note {
    var text: String
    var visit: Visit?
    init(text: String) { self.text = text }
}

@MainActor
enum DataCheck {
    static func run() -> String {
        do {
            let container = try ModelContainer(for: Visit.self, Note.self, configurations: ModelConfiguration("launches"))
            let context = container.mainContext
            let visits = try context.fetch(FetchDescriptor<Visit>(sortBy: [SortDescriptor(\.number)]))
            let visit = Visit(number: (visits.last?.number ?? 0) + 1, at: Date())
            visit.notes = [Note(text: "launch \(visit.number)")]
            context.insert(visit)
            try context.save()
            let all = try context.fetch(FetchDescriptor<Visit>(sortBy: [SortDescriptor(\.number)]))
            let notes = try context.fetch(FetchDescriptor<Note>(predicate: #Predicate { $0.visit != nil }))
            let linked = notes.allSatisfy { note in note.visit?.notes.contains { $0 === note } == true }
            // A second container of the same name: what the first saved, with its relationships.
            let reopened = try ModelContainer(for: Visit.self, Note.self, configurations: ModelConfiguration("launches"))
            let again = try reopened.mainContext.fetch(FetchDescriptor<Visit>())
            let lastNote = again.first { $0.number == visit.number }?.notes.first?.text ?? "no note"
            return "data: \(all.count) visits, \(notes.count) notes\(linked ? " linked" : " unlinked"), last \(visit.number), reopened \(again.count) \(lastNote)"
        } catch {
            return "data: error \(error)"
        }
    }
}
