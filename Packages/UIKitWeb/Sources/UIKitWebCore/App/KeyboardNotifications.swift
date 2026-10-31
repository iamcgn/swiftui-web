// The keyboard notifications (decision 0021, uk-app-delegate-adaptor: the Countries app's
// `SystemEventsHandler` observes `keyboardWillShowNotification` and reads the end frame). A
// host that knows the on-screen keyboard's frame sets `UIKitScene.keyboardFrame`; the
// will/did show and hide notifications follow with UIKit's user-info keys. `NSValue` holds the
// rects where there is no Foundation `NSValue` (wasm); `NSNumber` is WebFoundation's there.
import WebFoundation

#if os(WASI)
/// A box for a geometry value in a notification's user info (`cgRectValue` as UIKit's).
public final class NSValue: Hashable, @unchecked Sendable, CustomStringConvertible {
    private enum Stored: Equatable { case rect(CGRect), point(CGPoint), size(CGSize), range(NSRange), double(Double) }
    private let stored: Stored
    public init(cgRect: CGRect) { stored = .rect(cgRect) }
    public init(cgPoint: CGPoint) { stored = .point(cgPoint) }
    public init(cgSize: CGSize) { stored = .size(cgSize) }
    public init(range: NSRange) { stored = .range(range) }
    public var cgRectValue: CGRect { if case .rect(let r) = stored { return r }; return .zero }
    public var cgPointValue: CGPoint { if case .point(let p) = stored { return p }; return .zero }
    public var cgSizeValue: CGSize { if case .size(let s) = stored { return s }; return .zero }
    public var rangeValue: NSRange { if case .range(let r) = stored { return r }; return NSRange(location: NSNotFound, length: 0) }
    public static func == (lhs: NSValue, rhs: NSValue) -> Bool { lhs.stored == rhs.stored }
    public func hash(into hasher: inout Hasher) {
        switch stored {
        case .rect(let r): hasher.combine(r.minX); hasher.combine(r.minY); hasher.combine(r.width); hasher.combine(r.height)
        case .point(let p): hasher.combine(p.x); hasher.combine(p.y)
        case .size(let s): hasher.combine(s.width); hasher.combine(s.height)
        case .range(let r): hasher.combine(r.location); hasher.combine(r.length)
        case .double(let d): hasher.combine(d)
        }
    }
    public var description: String { "\(stored)" }
}

#else
/// Foundation's `NSValue` with the geometry accessors UIKit adds to it.
extension NSValue {
    public convenience init(cgRect: CGRect) { self.init(rect: cgRect) }
    public convenience init(cgPoint: CGPoint) { self.init(point: cgPoint) }
    public convenience init(cgSize: CGSize) { self.init(size: cgSize) }
    public var cgRectValue: CGRect { rectValue }
    public var cgPointValue: CGPoint { pointValue }
    public var cgSizeValue: CGSize { sizeValue }
}
#endif

extension UIResponder {
    nonisolated public static let keyboardFrameBeginUserInfoKey = "UIKeyboardFrameBeginUserInfoKey"
    nonisolated public static let keyboardFrameEndUserInfoKey = "UIKeyboardFrameEndUserInfoKey"
    nonisolated public static let keyboardAnimationDurationUserInfoKey = "UIKeyboardAnimationDurationUserInfoKey"
    nonisolated public static let keyboardAnimationCurveUserInfoKey = "UIKeyboardAnimationCurveUserInfoKey"
    nonisolated public static let keyboardIsLocalUserInfoKey = "UIKeyboardIsLocalUserInfoKey"

    nonisolated public static let keyboardWillShowNotification = Notification.Name("UIKeyboardWillShowNotification")
    nonisolated public static let keyboardDidShowNotification = Notification.Name("UIKeyboardDidShowNotification")
    nonisolated public static let keyboardWillHideNotification = Notification.Name("UIKeyboardWillHideNotification")
    nonisolated public static let keyboardDidHideNotification = Notification.Name("UIKeyboardDidHideNotification")
    nonisolated public static let keyboardWillChangeFrameNotification = Notification.Name("UIKeyboardWillChangeFrameNotification")
    nonisolated public static let keyboardDidChangeFrameNotification = Notification.Name("UIKeyboardDidChangeFrameNotification")
}

extension UIKitScene {
    /// The on-screen keyboard's frame in the screen's space, or nil while it is away. A host
    /// sets it (the browser's keyboard shrinks the visual viewport; `nil` on a desktop); the
    /// notifications go out as UIKit posts them, with the begin and end frames (the hidden
    /// keyboard sits just below the screen), a 0.25 s duration and the ease-in-out curve.
    public var keyboardFrame: CGRect? {
        get { storedKeyboardFrame }
        set {
            let previous = storedKeyboardFrame
            guard previous != newValue else { return }
            storedKeyboardFrame = newValue
            let screen = UIScreen.main.bounds
            let hidden = CGRect(x: 0, y: screen.maxY, width: screen.width, height: previous?.height ?? newValue?.height ?? 0)
            let begin = previous ?? hidden
            let end = newValue ?? hidden
            let info: [AnyHashable: Any] = [
                UIResponder.keyboardFrameBeginUserInfoKey: NSValue(cgRect: begin),
                UIResponder.keyboardFrameEndUserInfoKey: NSValue(cgRect: end),
                UIResponder.keyboardAnimationDurationUserInfoKey: NSNumber(value: 0.25),
                UIResponder.keyboardAnimationCurveUserInfoKey: NSNumber(value: 7),
                UIResponder.keyboardIsLocalUserInfoKey: NSNumber(value: true),
            ]
            let center = NotificationCenter.default
            let showing = newValue != nil && previous == nil, hiding = newValue == nil
            center.post(name: UIResponder.keyboardWillChangeFrameNotification, object: nil, userInfo: info)
            if showing { center.post(name: UIResponder.keyboardWillShowNotification, object: nil, userInfo: info) }
            if hiding { center.post(name: UIResponder.keyboardWillHideNotification, object: nil, userInfo: info) }
            if showing { center.post(name: UIResponder.keyboardDidShowNotification, object: nil, userInfo: info) }
            if hiding { center.post(name: UIResponder.keyboardDidHideNotification, object: nil, userInfo: info) }
            center.post(name: UIResponder.keyboardDidChangeFrameNotification, object: nil, userInfo: info)
        }
    }
}
