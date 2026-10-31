// `import CoreData` on wasm: WebCoreData (the managed object model, contexts, stores through
// the host's storage, NSPredicate and NSSortDescriptor, and SwiftUI's `@FetchRequest`) under
// the name an app's source imports. The app's `.xcdatamodeld` becomes Swift through
// SwiftUIWeb's CoreDataModel build plugin. Apple's CoreData re-exports Foundation, and so does
// WebCoreData.
#if os(WASI)
@_exported import WebCoreData
#endif
