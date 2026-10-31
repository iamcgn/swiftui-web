// A file that imports only Foundation and builds predicates, as an iOS app's model code does:
// Apple's Foundation declares NSPredicate, so the `CoreData` trait on Shadows makes the
// Foundation shadow bring it (decision 0024).
import Foundation

enum Filters {
    /// The notes whose text ends with the suffix.
    static func endingIn(_ suffix: String) -> NSPredicate {
        NSPredicate(format: "text ENDSWITH %@", suffix)
    }
}
