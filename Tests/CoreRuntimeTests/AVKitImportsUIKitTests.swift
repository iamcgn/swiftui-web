// A file with only `import AVKit` names UIKit's views, as on iOS, where AVKit imports UIKit
// (Nuke's NukeVideo subclasses UIView for its player view with no UIKit import).
#if !os(WASI)
import AVKit
import Testing

@MainActor private final class PlayerHostView: UIView {}

@MainActor
struct AVKitImportsUIKitTests {
    @Test func aPlayerViewIsAUIView() {
        let view = PlayerHostView(frame: CGRect(x: 0, y: 0, width: 4, height: 3))
        #expect(view.bounds.width == 4 && view.bounds.height == 3)
    }
}
#endif
