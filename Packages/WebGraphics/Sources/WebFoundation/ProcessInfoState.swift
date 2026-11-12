// The device state `ProcessInfo` reports on Apple's platforms, which FoundationEssentials
// leaves out on wasm: a page runs cool, on mains power, and never on a Mac as an iOS app, so
// the values are constant and the notifications are never posted.
#if os(WASI)
import FoundationEssentials

extension ProcessInfo {
    /// Values that indicate the system's thermal state.
    public enum ThermalState: Int, Sendable {
        case nominal, fair, serious, critical
    }

    /// The current thermal state of the system (always nominal here).
    public var thermalState: ThermalState { .nominal }

    /// Posted when the thermal state of the system changes (never, here).
    public static let thermalStateDidChangeNotification = Notification.Name("NSProcessInfoThermalStateDidChangeNotification")

    /// Whether Low Power Mode is on (never, here).
    public var isLowPowerModeEnabled: Bool { false }

    /// Whether the process is an iPhone or iPad app running on a Mac (never, here).
    public var isiOSAppOnMac: Bool { false }
}

extension Notification.Name {
    /// Posted when the power state (Low Power Mode) of the device changes (never, here).
    public static let NSProcessInfoPowerStateDidChange = Notification.Name("NSProcessInfoPowerStateDidChangeNotification")
}
#endif
