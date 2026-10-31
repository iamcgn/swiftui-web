// A Core Data notes list. This file imports only SwiftUI, as an iOS app's views do: the
// `CoreData` trait makes SwiftUI bring `@FetchRequest`, `FetchedResults`, `NSSortDescriptor`
// and `\.managedObjectContext` (decision 0024). It must stay valid, unmodified SwiftUI.
import SwiftUI

@main
struct NotesApp: App {
    var body: some Scene {
        WindowGroup {
            NotesView()
                .environment(\.managedObjectContext, Persistence.container.viewContext)
        }
    }
}

struct NotesView: View {
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Note.created, ascending: true)])
    private var notes: FetchedResults<Note>
    @FetchRequest(sortDescriptors: [], predicate: Filters.endingIn("2"))
    private var twos: FetchedResults<Note>

    var body: some View {
        VStack(spacing: 12) {
            Text("Notes: \(notes.count)")
                .font(.title)
            ForEach(notes) { note in
                Text(note.text ?? "")
            }
            Text("Ending in 2: \(twos.count)")
            HStack {
                Button("Add") { add() }
                Button("Clear") { clear() }
            }
        }
        .padding()
    }

    private func add() {
        let note = Note(context: context)
        note.text = "Note \(notes.count + 1)"
        note.created = Date()
        try? context.save()
    }

    private func clear() {
        for note in notes {
            context.delete(note)
        }
        try? context.save()
    }
}
