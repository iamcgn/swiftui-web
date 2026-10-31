// UIDevice (Docs/coverage.md: 5 apps, most reading `userInterfaceIdiom` to lay out a phone or a
// pad, a few `systemVersion` or `identifierForVendor`). A page runs on no particular device, so
// the answers come from the screen the host gave: the idiom the size classes chose
// (UIKitScene.applySizeClasses), the orientation from the screen's shape, the model from the
// idiom. The vendor identifier is a UUID made once and kept in the standard defaults, so it
// stays the same across launches as long as the browser keeps the page's storage. There is no
// battery or proximity sensor to read: monitoring stays off and the state unknown, as on a
// simulator.
import WebFoundation

/// The physical orientation of the device.
public enum UIDeviceOrientation: Int, Sendable {
    case unknown = 0, portrait, portraitUpsideDown, landscapeLeft, landscapeRight, faceUp, faceDown

    public var isPortrait: Bool { self == .portrait || self == .portraitUpsideDown }
    public var isLandscape: Bool { self == .landscapeLeft || self == .landscapeRight }
    public var isFlat: Bool { self == .faceUp || self == .faceDown }
    public var isValidInterfaceOrientation: Bool { isPortrait || isLandscape }
}

/// A representation of the current device.
@preconcurrency @MainActor
open class UIDevice {
    /// The battery's charge state.
    public enum BatteryState: Int, Sendable { case unknown = 0, unplugged, charging, full }

    /// The device the app runs on.
    public static let current = UIDevice()

    /// The device's name: its model, as iOS 16 and later answer without the entitlement.
    open var name: String { model }
    /// The model, iPhone or iPad by the idiom the screen's width gives.
    open var model: String { userInterfaceIdiom == .pad ? "iPad" : "iPhone" }
    open var localizedModel: String { model }
    open var systemName: String { "iOS" }
    /// The iOS release whose SwiftUI and UIKit this runtime follows.
    open var systemVersion: String { "18.0" }
    /// The style of interface, from the screen's trait collection.
    open var userInterfaceIdiom: UIUserInterfaceIdiom { UIScreen.main.traitCollection.userInterfaceIdiom }

    /// The orientation the screen's shape gives (wider than tall is landscape).
    open private(set) var orientation: UIDeviceOrientation = .portrait
    open private(set) var isGeneratingDeviceOrientationNotifications = false
    open var isMultitaskingSupported: Bool { true }

    open var isBatteryMonitoringEnabled = false
    /// -1 while the level is unknown, as UIKit answers without monitoring.
    open var batteryLevel: Float { -1 }
    open var batteryState: BatteryState { .unknown }

    open var isProximityMonitoringEnabled: Bool {
        get { false }
        set {}
    }
    open var proximityState: Bool { false }

    /// An identifier for this app on this device, made once and kept with the page's defaults.
    open var identifierForVendor: UUID? {
        let key = "UIDeviceIdentifierForVendor"
        if let stored = UserDefaults.standard.string(forKey: key), let id = UUID(uuidString: stored) { return id }
        let id = UUID()
        UserDefaults.standard.set(id.uuidString, forKey: key)
        return id
    }

    public init() {}

    open func beginGeneratingDeviceOrientationNotifications() { isGeneratingDeviceOrientationNotifications = true }
    open func endGeneratingDeviceOrientationNotifications() { isGeneratingDeviceOrientationNotifications = false }

    /// Plays the keyboard click: there is none to play.
    open func playInputClick() {}

    /// The host resized the screen: the orientation follows its shape, with a notification
    /// when it changed and the app asked for them.
    func screenDidResize(to size: CGSize) {
        let next: UIDeviceOrientation = size.width > size.height ? .landscapeLeft : .portrait
        guard next != orientation else { return }
        orientation = next
        if isGeneratingDeviceOrientationNotifications {
            NotificationCenter.default.post(name: UIDevice.orientationDidChangeNotification, object: self)
        }
    }

    nonisolated public static let orientationDidChangeNotification = Notification.Name("UIDeviceOrientationDidChangeNotification")
    nonisolated public static let batteryStateDidChangeNotification = Notification.Name("UIDeviceBatteryStateDidChangeNotification")
    nonisolated public static let batteryLevelDidChangeNotification = Notification.Name("UIDeviceBatteryLevelDidChangeNotification")
    nonisolated public static let proximityStateDidChangeNotification = Notification.Name("UIDeviceProximityStateDidChangeNotification")
}

extension UIApplication {
    /// Alternate app icons: a page has one icon, its favicon, so none can be chosen.
    public var supportsAlternateIcons: Bool { false }
    public var alternateIconName: String? { nil }

    /// Answers with an error, as iOS does for an app that declares no alternate icons.
    public func setAlternateIconName(_ alternateIconName: String?, completionHandler: ((Error?) -> Void)? = nil) {
        completionHandler?(alternateIconName == nil ? nil : Self.alternateIconsUnsupported)
    }

    public func setAlternateIconName(_ alternateIconName: String?) async throws {
        if alternateIconName != nil { throw Self.alternateIconsUnsupported }
    }

    private static var alternateIconsUnsupported: NSError {
        NSError(domain: "NSCocoaErrorDomain", code: 3328, userInfo: [NSLocalizedDescriptionKey: "The requested operation couldn’t be completed because the feature is not supported."])
    }
}
