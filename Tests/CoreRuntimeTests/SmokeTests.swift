import Testing
import SwiftUI

@Suite struct SmokeTests {
    @Test func moduleShadowing() {
        // Spike 0.3: on macOS this must resolve to SwiftUIWeb's module, not Apple's framework.
        #expect(SwiftUIWebMarker.implementation == "SwiftUIWeb")
        #expect(SwiftUIWebVersion.string.hasPrefix("0."))
    }
}
