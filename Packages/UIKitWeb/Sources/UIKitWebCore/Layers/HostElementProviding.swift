// A view or layer the host shows as an element of its own where it is (a `WKWebView`'s page in
// the host's `<iframe>`, a camera preview layer's stream in a `<video>`). The SwiftUI hosting
// tree collects them when it paints a representable (SwiftUIWebUIKit's RepresentableTree); a
// change of what to show asks for a repaint (`setNeedsDisplay`).
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif

/// The kind says what the host shows, nil says nothing yet.
@MainActor
public protocol _UIHostElementProviding: AnyObject {
    var _hostElementKind: HostElement.Kind? { get }
}
