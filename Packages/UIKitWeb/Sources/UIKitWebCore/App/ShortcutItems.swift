// Home screen quick actions (UIApplicationShortcutItem). A web page has no home screen icon to
// long-press, so an app's dynamic items are kept and handed back, and no scene ever connects or
// is asked to act for one: `ConnectionOptions.shortcutItem` is nil, as for a launch from the
// icon itself. Declared in extensions and outside the classes' vtables, so an app that never
// names them does not ship them.
import WebFoundation   // NSSecureCoding

/// An icon for a home screen quick action.
public final class UIApplicationShortcutIcon: @unchecked Sendable {
    /// The system's quick action icons.
    public enum IconType: Int, Sendable {
        case compose, play, pause, add, location, search, share, prohibit, contact, home, markLocation,
             favorite, love, cloud, invitation, confirmation, mail, message, date, time, capturePhoto,
             captureVideo, task, taskCompleted, alarm, bookmark, shuffle, audio, update
    }

    /// The system icon, when the icon is one.
    public let type: IconType?
    /// The SF Symbol or template image name, when the icon is one.
    public let imageName: String?

    public init(type: IconType) { self.type = type; imageName = nil }
    public init(systemImageName: String) { type = nil; imageName = systemImageName }
    public init(templateImageName: String) { type = nil; imageName = templateImageName }
}

/// A home screen quick action.
open class UIApplicationShortcutItem: @unchecked Sendable {
    var _type: String
    var _localizedTitle: String
    var _localizedSubtitle: String?
    var _icon: UIApplicationShortcutIcon?
    var _userInfo: [String: any NSSecureCoding]?
    var _targetContentIdentifier: Any?

    /// The app's own string that says which action this is.
    open var type: String { _type }
    open var localizedTitle: String { _localizedTitle }
    open var localizedSubtitle: String? { _localizedSubtitle }
    open var icon: UIApplicationShortcutIcon? { _icon }
    open var userInfo: [String: any NSSecureCoding]? { _userInfo }
    /// The object the item stands for, when it is one.
    open var targetContentIdentifier: Any? { _targetContentIdentifier }

    public init(type: String, localizedTitle: String, localizedSubtitle: String? = nil,
                icon: UIApplicationShortcutIcon? = nil, userInfo: [String: any NSSecureCoding]? = nil) {
        _type = type
        _localizedTitle = localizedTitle
        _localizedSubtitle = localizedSubtitle
        _icon = icon
        _userInfo = userInfo
    }

    public convenience init(type: String, localizedTitle: String) {
        self.init(type: type, localizedTitle: localizedTitle, localizedSubtitle: nil, icon: nil, userInfo: nil)
    }
}

/// A quick action whose properties can be changed.
open class UIMutableApplicationShortcutItem: UIApplicationShortcutItem, @unchecked Sendable {
    open override var type: String { get { _type } set { _type = newValue } }
    open override var localizedTitle: String { get { _localizedTitle } set { _localizedTitle = newValue } }
    open override var localizedSubtitle: String? { get { _localizedSubtitle } set { _localizedSubtitle = newValue } }
    open override var icon: UIApplicationShortcutIcon? { get { _icon } set { _icon = newValue } }
    open override var userInfo: [String: any NSSecureCoding]? { get { _userInfo } set { _userInfo = newValue } }
    open override var targetContentIdentifier: Any? { get { _targetContentIdentifier } set { _targetContentIdentifier = newValue } }
}

@MainActor private var dynamicShortcutItems: [UIApplicationShortcutItem]?

extension UIApplication {
    /// The app's dynamic quick actions: kept as set, with nowhere to show them.
    public var shortcutItems: [UIApplicationShortcutItem]? {
        get { dynamicShortcutItems }
        set { dynamicShortcutItems = newValue }
    }
}

extension UIScene.ConnectionOptions {
    /// The quick action that launched the app: never one on the web.
    public var shortcutItem: UIApplicationShortcutItem? { nil }
}
