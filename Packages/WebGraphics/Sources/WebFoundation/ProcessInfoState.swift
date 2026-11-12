// The device state `ProcessInfo` reports on Apple's platforms, which FoundationEssentials
// leaves out on wasm: a page runs cool, on mains power, and never on a Mac as an iOS app, so
// the values are constant and the notifications are never posted.
//
// No type is declared inside `extension ProcessInfo`: a nested type's descriptor names
// ProcessInfo's own, a reference the linker cannot drop, and it brought FoundationEssentials'
// ProcessInfo object file and with it most of the library into every bundle (Counter grew from
// 2.97 MB to 3.93 MB brotli). The thermal state is a top-level enum the extension names.
#if os(WASI)
import FoundationEssentials

/// Values that indicate the system's thermal state (`ProcessInfo.ThermalState`).
public enum _ProcessInfoThermalState: Int, Sendable {
    case nominal, fair, serious, critical
}

extension ProcessInfo {
    /// Values that indicate the system's thermal state.
    public typealias ThermalState = _ProcessInfoThermalState

    /// The current thermal state of the system (always nominal here).
    public var thermalState: ThermalState { .nominal }

    /// Posted when the thermal state of the system changes (never, here).
    public static var thermalStateDidChangeNotification: Notification.Name {
        Notification.Name("NSProcessInfoThermalStateDidChangeNotification")
    }

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
