// A `Sendable` class whose superclass is `NSObject`, as apps declare their session delegates
// and observers (IceCubes' upload progress delegate, swift-sharing's user defaults observer).
// Swift allows it only for an `NSObject` from Foundation, ObjectiveC or SwiftFoundation, so this
// file compiling is most of the test; on wasm without the runtime NSObject is SwiftFoundation's.
import Testing
import WebFoundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class ProgressDelegate: NSObject, Sendable {
    let label: String
    init(label: String) {
        self.label = label
        super.init()
    }
}

@Suite struct SendableObjectTests {
    @Test func aSendableObjectCrossesIntoATask() async {
        let delegate = ProgressDelegate(label: "upload")
        let label = await Task.detached { delegate.label }.value
        #expect(label == "upload")
        #expect(delegate.isEqual(delegate) && !delegate.isEqual(ProgressDelegate(label: "upload")))
        #expect(delegate.responds(to: Selector(("cancel"))) == false)
    }
}
