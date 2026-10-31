// Thin module: apps write `import SwiftUI` and get the SwiftUIWeb implementation.
// Foundation and Observation are re-exported because real SwiftUI does the same
// (CGFloat/CGRect, @Observable) and unmodified app sources depend on it.
@_exported import SwiftUIWebCore
@_exported import WebCombine
@_exported import SwiftUIWebUIKit
// SwiftUI re-exports UIKit on iOS (an `import SwiftUI` file can name `UIColor` or write a
// `UIViewRepresentable`); here it re-exports UIKitWeb's `UIKit` everywhere (decision 0014).
@_exported import UIKit
@_exported import Observation
#if canImport(CoreGraphics) && !os(WASI)
// Apple platforms: CGRect.init(x:y:width:height:) etc. live in the CoreGraphics overlay, which
// `import Foundation` alone does not surface. Real SwiftUI re-exports CoreGraphics too.
@_exported import Foundation
@_exported import CoreGraphics
#elseif os(WASI)
// wasm: the SDK's Foundation would add 12 MB of ICU data and a second CGRect (decision 0006);
// WebFoundation is FoundationEssentials plus the stand-ins that keep its heavy members out of
// the bundle (decision 0017), with `DispatchQueue`, `UserDefaults`, `Bundle` and `FileManager`
// (decision 0021); WASILibc is libm and friends, which Apple's Foundation re-exports through
// Darwin. An app's own `import Foundation` and `import Combine` are Packages/Shadows' modules,
// which its Package.swift links (they must stay out of this package's test builds: SwiftPM's
// wasm test discovery imports XCTest, whose module wants the SDK's Foundation).
@_exported import WebFoundation
@_exported import WASILibc
#if CoreData
// The `CoreData` trait (decision 0024): Apple's SwiftUI declares `@FetchRequest`,
// `FetchedResults` and `\.managedObjectContext`, so a file that imports only SwiftUI uses them.
// Only on wasm: on macOS the names would collide with Apple's Foundation (`NSPredicate`, `NSSet`).
@_exported import WebCoreData
#endif
#else
// Linux: Foundation plus the missing Objective-C API value stand-ins.
@_exported import WebFoundation
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
        // The app's scene gets a window in UIKit once its root is mounted (what the app reaches
        // through `UIApplication.shared.connectedScenes`).
        _appDidMount = { runtime in _SwiftUISceneWindow.install(for: runtime) }
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
public typealias ObservableObject = WebCombine.ObservableObject
public typealias ObservableObjectPublisher = WebCombine.ObservableObjectPublisher
public typealias Published = WebCombine.Published
public typealias StateObject = SwiftUIWebCore.StateObject
public typealias ObservedObject = SwiftUIWebCore.ObservedObject
public typealias EnvironmentObject = SwiftUIWebCore.EnvironmentObject
public typealias AnyCancellable = WebCombine.AnyCancellable
