import Testing
import UIKit

@Suite @MainActor struct UIKitWebTests {
    @Test func moduleIsOurs() {
        #expect(UIKitWebMarker.implementation == "UIKitWeb")
    }
}
