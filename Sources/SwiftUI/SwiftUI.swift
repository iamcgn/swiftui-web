// Thin module: apps write `import SwiftUI` and get the SwiftUIWeb implementation.
// Foundation and Observation are re-exported because real SwiftUI does the same
// (CGFloat/CGRect, @Observable) and unmodified app sources depend on it.
@_exported import SwiftUIWebCore
@_exported import Observation
#if canImport(CoreGraphics)
// Apple platforms: CGRect.init(x:y:width:height:) etc. live in the CoreGraphics overlay, which
// `import Foundation` alone does not surface. Real SwiftUI re-exports CoreGraphics too.
@_exported import Foundation
@_exported import CoreGraphics
#elseif os(WASI)
// wasm: Foundation would add 12 MB of ICU data and a second CGRect (decision 0006).
@_exported import FoundationEssentials
#else
@_exported import Foundation
#endif

/// Marker used by the module-shadowing spike (Docs/decisions/0001-module-name.md).
public struct SwiftUIWebMarker: Sendable {
    public init() {}
    public static let implementation = "SwiftUIWeb"
}

#if os(WASI)
import SwiftUIWebCanvas
#elseif canImport(AppKit)
import SwiftUIWebNative
#endif

extension App {
    /// Launches the app: in the browser, mounts the first window's root view in a canvas host;
    /// on macOS in an AppKit window painted with CoreGraphics (`SwiftUIWebNative`); elsewhere
    /// (CLIs) lays it out headlessly once and returns.
    public static func main() {
        #if os(WASI)
        CanvasHost.launch(windows: Self._windows()) { Self._rootView() }
        #elseif canImport(AppKit)
        NativeHost.launch(windows: Self._windows()) { Self._rootView() }
        #else
        MainActor.assumeIsolated {
            let runtime = Runtime()
            runtime.installWindows(Self._windows())
            runtime.mount(Self._rootView())
            runtime.layout(in: CGSize(width: 800, height: 600))
            print("SwiftUIWeb: no window host on this platform; laid out \(Self.self) headlessly.")
        }
        #endif
    }
}

// The Combine-free ObservableObject family: on Apple platforms Foundation re-exports Combine's
// names, so the module declares these to shadow them (declarations beat re-exports).
public typealias ObservableObject = SwiftUIWebCore.ObservableObject
public typealias ObservableObjectPublisher = SwiftUIWebCore.ObservableObjectPublisher
public typealias Published = SwiftUIWebCore.Published
public typealias StateObject = SwiftUIWebCore.StateObject
public typealias ObservedObject = SwiftUIWebCore.ObservedObject
public typealias EnvironmentObject = SwiftUIWebCore.EnvironmentObject
public typealias AnyCancellable = SwiftUIWebCore.AnyCancellable
