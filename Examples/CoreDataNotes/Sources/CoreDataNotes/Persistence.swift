// The store, in a file that imports CoreData as an iOS app's persistence file does.
import CoreData

@MainActor
enum Persistence {
    /// The app's container: the Notes model, stored by name (localStorage in the browser).
    static let container: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "Notes")
        container.loadPersistentStores { _, error in
            if let error { print("Notes: the store did not load: \(error)") }
        }
        return container
    }()
}
