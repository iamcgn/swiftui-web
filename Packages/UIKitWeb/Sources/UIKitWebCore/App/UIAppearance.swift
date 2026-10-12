// UIAppearance (uk-appearance): `UILabel.appearance().textColor = .red` records the key path and
// value on a proxy; the recorded values are applied to a view of that class (or a subclass) when
// it enters a window, later entries winning over earlier ones and contained ones
// (`appearance(whenContainedInInstancesOf:)`, the containers matched along the responder chain)
// over plain ones. As in UIKit, the proxy writes over values set before the view entered a window.
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif

/// A class whose instances can contain views appearance customisations apply to.
public protocol UIAppearanceContainer: AnyObject {}
extension UIView: UIAppearanceContainer {}
extension UIViewController: UIAppearanceContainer {}

/// A class whose appearance can be customised through a proxy (views here). The factories
/// live in the protocol extension: a class method cannot return a generic over `Self`.
@MainActor
public protocol UIAppearance: UIView {}

extension UIView: UIAppearance {}

extension UIAppearance {
    public static func appearance() -> UIAppearanceProxy<Self> { UIAppearanceProxy(containers: []) }

    public static func appearance(whenContainedInInstancesOf containerTypes: [any UIAppearanceContainer.Type]) -> UIAppearanceProxy<Self> {
        UIAppearanceProxy(containers: containerTypes.map { ObjectIdentifier($0) })
    }
}

/// The appearance proxy of a view class: every settable property of the class reached by key
/// path (`proxy.textColor = .red`) records an entry; reading one gives the recorded value (a
/// property nothing recorded has no proxy value: UIKit returns nil there, Swift's key paths
/// cannot, so the read traps with the key path).
@MainActor @dynamicMemberLookup
public struct UIAppearanceProxy<T: UIView> {
    let containers: [ObjectIdentifier]

    public subscript<V>(dynamicMember keyPath: ReferenceWritableKeyPath<T, V>) -> V {
        get {
            if let recorded = _UIAppearanceRegistry.shared.recordedValue(for: T.self, keyPath: keyPath, containers: containers) as? V { return recorded }
            preconditionFailure("no appearance value recorded for \(T.self) \(keyPath)")
        }
        nonmutating set {
            _UIAppearanceRegistry.shared.record(for: T.self, keyPath: keyPath, containers: containers, value: newValue) { view in
                (view as? T)?[keyPath: keyPath] = newValue
            }
        }
    }
}

/// The recorded appearance entries, applied to views entering a window.
@MainActor
public final class _UIAppearanceRegistry {
    public static let shared = _UIAppearanceRegistry()

    struct Entry {
        let viewType: ObjectIdentifier
        let keyPath: AnyKeyPath
        let containers: [ObjectIdentifier]
        let value: Any
        let apply: (UIView) -> Void
    }
    private(set) var entries: [Entry] = []

    func record(for type: UIView.Type, keyPath: AnyKeyPath, containers: [ObjectIdentifier], value: Any, apply: @escaping (UIView) -> Void) {
        entries.removeAll { $0.viewType == ObjectIdentifier(type) && $0.keyPath == keyPath && $0.containers == containers }
        entries.append(Entry(viewType: ObjectIdentifier(type), keyPath: keyPath, containers: containers, value: value, apply: apply))
    }

    func recordedValue(for type: UIView.Type, keyPath: AnyKeyPath, containers: [ObjectIdentifier]) -> Any? {
        entries.last { $0.viewType == ObjectIdentifier(type) && $0.keyPath == keyPath && $0.containers == containers }?.value
    }

    /// Forgets every entry (tests).
    public func removeAll() { entries.removeAll() }

    /// The class and superclasses of an object, most derived first.
    private static func classChain(of object: AnyObject) -> [ObjectIdentifier] {
        var chain: [ObjectIdentifier] = []
        var mirror: Mirror? = Mirror(reflecting: object)
        while let current = mirror {
            if let type = current.subjectType as? AnyClass { chain.append(ObjectIdentifier(type)) }
            mirror = current.superclassMirror
        }
        return chain
    }

    /// Applies the entries matching `view`: its class chain, and for contained entries the
    /// containers found in order along the responder chain (superviews and their controllers).
    func apply(to view: UIView) {
        guard !entries.isEmpty else { return }
        let classes = Set(Self.classChain(of: view))
        var ancestors: [Set<ObjectIdentifier>] = []
        var responder: UIResponder? = view.next
        while let current = responder {
            ancestors.append(Set(Self.classChain(of: current)))
            responder = current.next
        }
        func contained(in containers: [ObjectIdentifier]) -> Bool {
            // Each container must be found, the innermost first, further out than the previous.
            var position = 0
            for container in containers {
                guard let found = ancestors[position...].firstIndex(where: { $0.contains(container) }) else { return false }
                position = found + 1
            }
            return true
        }
        // Plain entries first, then the contained ones (more specific), in recording order.
        for entry in entries where classes.contains(entry.viewType) && entry.containers.isEmpty { entry.apply(view) }
        for entry in entries where classes.contains(entry.viewType) && !entry.containers.isEmpty && contained(in: entry.containers) { entry.apply(view) }
    }
}
