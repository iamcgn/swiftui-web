// Storyboards and nibs: Interface Builder archives, which the web has none of (an app's bundle
// here holds no compiled storyboards or nibs). A storyboard opens with no scenes in it and a
// nib loads no objects, so code that builds its interface in code and only names an archive on
// a path it never takes (SwiftyFORM's `storyboard(_:bundle:)` form item, its nib-loading
// helper) compiles and runs; code that does take that path gets what UIKit gives for an
// archive that holds nothing. A storyboard's segues come from its archive too, so a controller
// here has none to perform by identifier; a segue made in code (`UIStoryboardSegue(identifier:
// source:destination:performHandler:)`) performs as UIKit's does.
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif

/// A storyboard: the scenes of an app's interface, made from an Interface Builder archive.
@preconcurrency @MainActor
open class UIStoryboard {
    /// The storyboard's name in its bundle.
    let name: String

    /// The storyboard named `name` in `bundle` (the main bundle when nil). The web has no
    /// archive to read, so it holds no scenes.
    public init(name: String, bundle storyboardBundleOrNil: Bundle?) {
        self.name = name
    }

    /// The storyboard's initial view controller: none, as for a storyboard with no initial scene.
    open func instantiateInitialViewController() -> UIViewController? { nil }

    /// The initial view controller made by `block` from its archive: none, as there is no scene.
    open func instantiateInitialViewController<ViewController: UIViewController>(creator block: ((NSCoder) -> ViewController?)? = nil) -> ViewController? { nil }

    /// The scene with `identifier`. A storyboard with no scenes has none, which UIKit reports by
    /// stopping the app, as this does.
    open func instantiateViewController(withIdentifier identifier: String) -> UIViewController {
        fatalError("Storyboard (\(name)) doesn't contain a view controller with identifier '\(identifier)'")
    }

    /// The scene with `identifier`, made by `block`: there is none, as above.
    open func instantiateViewController<ViewController: UIViewController>(identifier: String, creator block: ((NSCoder) -> ViewController?)? = nil) -> ViewController {
        fatalError("Storyboard (\(name)) doesn't contain a view controller with identifier '\(identifier)'")
    }
}

/// A transition between two view controllers, as a storyboard's segue is: made by UIKit when a
/// controller performs one, or in code. The base class performs nothing unless it was made
/// with a handler; a subclass overrides `perform()`.
@preconcurrency @MainActor
open class UIStoryboardSegue: UIObjectBase {
    /// The segue's identifier in its storyboard, if it has one.
    public let identifier: String?
    /// The controller the segue starts from.
    public let source: UIViewController
    /// The controller the segue leads to.
    public let destination: UIViewController
    private var performHandler: (() -> Void)?

    public init(identifier: String?, source: UIViewController, destination: UIViewController) {
        self.identifier = identifier
        self.source = source
        self.destination = destination
        super.init()
    }

    /// A segue whose `perform()` runs `performHandler`.
    public convenience init(identifier: String?, source: UIViewController, destination: UIViewController,
                            performHandler: @escaping () -> Void) {
        self.init(identifier: identifier, source: source, destination: destination)
        self.performHandler = performHandler
    }

    /// Makes the transition: the handler it was made with, if any.
    open func perform() { performHandler?() }
}

/// A nib: the objects of an Interface Builder archive, which the web has none of.
@preconcurrency @MainActor
open class UINib {
    /// The options `instantiate(withOwner:options:)` and `loadNibNamed` take.
    public struct OptionsKey: Hashable, RawRepresentable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public init(_ rawValue: String) { self.rawValue = rawValue }
        /// Objects outside the nib that it refers to, by name.
        public static let externalObjects = OptionsKey("UINibExternalObjects")
    }

    /// The nib named `name` in `bundle`: one with no objects.
    public init(nibName name: String, bundle bundleOrNil: Bundle?) {}
    /// A nib from archived data: one with no objects, as the web cannot read the archive.
    public init(data: Data, bundle bundleOrNil: Bundle?) {}

    /// The nib's top-level objects: none.
    open func instantiate(withOwner ownerOrNil: Any?, options optionsOrNil: [OptionsKey: Any]? = nil) -> [Any] { [] }
}

extension Bundle {
    /// The top-level objects of the nib named `name`: nil, as for a nib the bundle doesn't hold.
    /// Main-actor isolated as UIKit's is, and `@preconcurrency` as an imported UIKit method is,
    /// so a Swift 5 mode package calling it from nonisolated code (SwiftyFORM's
    /// Bundle+LoadView.swift) builds with a warning, as on iOS, rather than an error.
    @preconcurrency @MainActor
    public func loadNibNamed(_ name: String, owner: Any?, options: [UINib.OptionsKey: Any]? = nil) -> [Any]? { nil }
}

extension UIViewController {
    /// The storyboard the controller came from: none, as no controller here comes from one.
    public var storyboard: UIStoryboard? { nil }
}
