// A view with a `@Query` and a binding, made through its memberwise initializer from another
// file (SwiftDataInferredKindsTests), as PomPadDo's views are: the query's storage must not
// make that initializer private.
import SwiftUI
import SwiftData

#if !os(WASI)
struct QueryMemberwiseView: View {
    @Query var tasks: [InferredTask]
    @Binding var count: Int
    var body: some View { Text("\(tasks.count) of \(count)") }
}
#endif
