// `#Preview` (Phase 3): preview blocks compile in a module that imports SwiftUI and expand to
// nothing; a PreviewProvider conformance compiles too.
import Testing
import SwiftUI

#Preview {
    Text("Hello preview")
}

#Preview("Named", traits: .sizeThatFitsLayout) {
    VStack { Text("One"); Text("Two") }
}

struct SamplePreviews: PreviewProvider {
    static var previews: some View { Text("Sample") }
}

@Suite struct PreviewTests {
    @Test func previewsExpandToNothing() {
        // Compiling this file is the test; the previews leave no declarations behind.
        #expect(true)
    }
}
