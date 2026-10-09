// Accessibility beyond the element properties (uk-accessibility, Docs/elements/Accessibility.md):
// `UIAccessibility.post` (announcements and focus moves the host's overlay delivers), the
// assistive settings, custom actions (`accessibilityCustomActions`, buttons in the overlay
// the host runs by name), and the escape and magic-tap actions.
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif

/// Notifications an app posts for assistive technology, and the assistive settings.
@MainActor
public enum UIAccessibility {
    public struct Notification: RawRepresentable, Hashable, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }
        /// A string to speak (the host announces it in a live region).
        public static let announcement = Notification(rawValue: 1008)
        /// The layout changed; a view argument moves assistive focus to it.
        public static let layoutChanged = Notification(rawValue: 1000)
        /// A new screen; a view argument moves assistive focus to it.
        public static let screenChanged = Notification(rawValue: 1001)
        public static let pageScrolled = Notification(rawValue: 1002)
        public static let pauseAssistiveTechnology = Notification(rawValue: 1010)
        public static let resumeAssistiveTechnology = Notification(rawValue: 1011)
    }

    /// Posts a notification: an announcement is queued for the host to speak, a layout or
    /// screen change with a view (or a string) moves assistive focus to that element at the
    /// next frame (or announces the string).
    public static func post(notification: Notification, argument: Any?) {
        switch notification {
        case .announcement:
            if let text = argument as? String, !text.isEmpty { UIKitScene.shared.accessibilityEvents.append(.announce(text)) }
        case .layoutChanged, .screenChanged:
            if let view = argument as? UIView {
                UIKitScene.shared.accessibilityEvents.append(.focus(view.semanticsIdentifier))
            } else if let text = argument as? String, !text.isEmpty {
                UIKitScene.shared.accessibilityEvents.append(.announce(text))
            }
            UIKitScene.shared.accessibilityEvents.append(notification == .screenChanged ? .screenChanged : .layoutChanged)
        default: break
        }
        UIKitScene.shared.setNeedsFrame()
    }

    /// The host cannot tell whether a screen reader runs: false, as UIKit answers without one.
    public static var isVoiceOverRunning: Bool { false }
    public static var isSwitchControlRunning: Bool { false }
    /// The host's reduce-motion setting (`prefers-reduced-motion`).
    public static var isReduceMotionEnabled: Bool { UIKitScene.shared.hostReducesMotion }
    public static var prefersCrossFadeTransitions: Bool { UIKitScene.shared.hostReducesMotion }
    public static var isReduceTransparencyEnabled: Bool { false }
    public static var isBoldTextEnabled: Bool { false }
    public static var isDarkerSystemColorsEnabled: Bool { false }
    public static var isInvertColorsEnabled: Bool { false }
    public static var isGrayscaleEnabled: Bool { false }
    public static var buttonShapesEnabled: Bool { false }
    public static var shouldDifferentiateWithoutColor: Bool { false }
    public static var isOnOffSwitchLabelsEnabled: Bool { false }
}

/// A named action assistive technology offers on an element (a button in the overlay).
@MainActor
open class UIAccessibilityCustomAction {
    public typealias Handler = (UIAccessibilityCustomAction) -> Bool
    open var name: String
    open var actionHandler: Handler?
    open var attributedName: NSAttributedString? { didSet { if let attributedName { name = attributedName.string } } }
    open var image: UIImage?

    public init(name: String, actionHandler: @escaping Handler) {
        self.name = name
        self.actionHandler = actionHandler
    }
    public init(name: String) { self.name = name }
    public init(attributedName: NSAttributedString, actionHandler: @escaping Handler) {
        name = attributedName.string
        self.attributedName = attributedName
        self.actionHandler = actionHandler
    }

    /// Runs the handler; true when it reports success.
    @discardableResult
    func perform() -> Bool { actionHandler?(self) ?? false }
}

/// How a container's children are presented (`accessibilityContainerType`; stored).
public enum UIAccessibilityContainerType: Int, Sendable {
    case none = 0, dataTable, list, landmark, semanticGroup
}

/// A navigation style for a container's children (stored).
public enum UIAccessibilityNavigationStyle: Int, Sendable {
    case automatic = 0, separate, combined
}

/// The accessibility properties a view stores beyond its element ones.
@MainActor
final class ViewAccessibilityState {
    var customActions: [UIAccessibilityCustomAction]?
    var elements: [Any]?
    var isModal = false
    var frame: CGRect?
    var groupsChildren = false
    var containerType: UIAccessibilityContainerType = .none
    var navigationStyle: UIAccessibilityNavigationStyle = .automatic
    var ignoresInvertColors = false
    var language: String?
}
