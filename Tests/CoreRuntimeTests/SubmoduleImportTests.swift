// `import UIKit.UIImage` and the other per-header imports of Apple's UIKit (Nuke, CriticalMaps,
// Harbour) resolve on wasm through UIKitWeb's UIKitSubmodules module map, and still mean `UIKit`.
#if os(WASI)
import Testing
import UIKit.UIImage
import UIKit.UIGestureRecognizerSubclass
import UIKit.UIPasteboard

@Suite struct SubmoduleImportTests {
    @Test func submoduleImportsReachUIKit() {
        #expect(String(describing: UIImage.self) == "UIImage")
        #expect(String(describing: UIGestureRecognizer.self) == "UIGestureRecognizer")
    }
}
#endif
