// Core Telephony on the web (OldOS's status bar and phone): a page has no cellular radio, so the
// network info answers no carriers and no radio technology, as an iPhone with no SIM does, and
// its update notifiers and notifications never fire. Cellular data is reported as not
// restricted, as the browser decides what the network allows.
#if os(WASI)
@_exported import WebFoundation
#else
import Foundation
#endif

/// The radio technologies Core Telephony names (`CTRadioAccessTechnologyLTE` and the rest).
public let CTRadioAccessTechnologyGPRS = "CTRadioAccessTechnologyGPRS"
public let CTRadioAccessTechnologyEdge = "CTRadioAccessTechnologyEdge"
public let CTRadioAccessTechnologyWCDMA = "CTRadioAccessTechnologyWCDMA"
public let CTRadioAccessTechnologyHSDPA = "CTRadioAccessTechnologyHSDPA"
public let CTRadioAccessTechnologyHSUPA = "CTRadioAccessTechnologyHSUPA"
public let CTRadioAccessTechnologyCDMA1x = "CTRadioAccessTechnologyCDMA1x"
public let CTRadioAccessTechnologyCDMAEVDORev0 = "CTRadioAccessTechnologyCDMAEVDORev0"
public let CTRadioAccessTechnologyCDMAEVDORevA = "CTRadioAccessTechnologyCDMAEVDORevA"
public let CTRadioAccessTechnologyCDMAEVDORevB = "CTRadioAccessTechnologyCDMAEVDORevB"
public let CTRadioAccessTechnologyeHRPD = "CTRadioAccessTechnologyeHRPD"
public let CTRadioAccessTechnologyLTE = "CTRadioAccessTechnologyLTE"
public let CTRadioAccessTechnologyNRNSA = "CTRadioAccessTechnologyNRNSA"
public let CTRadioAccessTechnologyNR = "CTRadioAccessTechnologyNR"

extension Notification.Name {
    /// Posted when a service's radio technology changes (never, here).
    public static let CTServiceRadioAccessTechnologyDidChange = Notification.Name("kCTServiceRadioAccessTechnologyDidChangeNotification")
    /// Posted when the radio technology changes (never, here).
    public static let CTRadioAccessTechnologyDidChange = Notification.Name("kCTRadioAccessTechnologyDidChangeNotification")
}

/// A cellular service provider's details. A page has no SIM, so none is ever made here.
open class CTCarrier: NSObject, @unchecked Sendable {
    open var carrierName: String? { nil }
    open var mobileCountryCode: String? { nil }
    open var mobileNetworkCode: String? { nil }
    open var isoCountryCode: String? { nil }
    open var allowsVOIP: Bool { false }
}

/// Hears that a service's radio technology changed.
public protocol CTTelephonyNetworkInfoDelegate: AnyObject {
    func dataServiceIdentifierDidChange(_ identifier: String)
}

extension CTTelephonyNetworkInfoDelegate {
    public func dataServiceIdentifierDidChange(_ identifier: String) {}
}

/// The device's cellular services: none on the web, so every answer is nil.
open class CTTelephonyNetworkInfo: NSObject, @unchecked Sendable {
    /// Each service's provider, by service identifier (nil: there are no services).
    open var serviceSubscriberCellularProviders: [String: CTCarrier]? { nil }
    /// Called when a service's provider changes (never, here).
    open var serviceSubscriberCellularProvidersDidUpdateNotifier: ((String) -> Void)?
    /// Each service's radio technology, by service identifier (nil: there are no services).
    open var serviceCurrentRadioAccessTechnology: [String: String]? { nil }
    /// The identifier of the service that carries data (nil: there is none).
    open var dataServiceIdentifier: String? { nil }
    open weak var delegate: (any CTTelephonyNetworkInfoDelegate)?
    /// The provider of the one service (deprecated on iOS for the per-service dictionary).
    open var subscriberCellularProvider: CTCarrier? { nil }
    /// Called when the provider changes (never, here).
    open var subscriberCellularProviderDidUpdateNotifier: ((CTCarrier) -> Void)?
    /// The radio technology of the one service (deprecated on iOS for the per-service dictionary).
    open var currentRadioAccessTechnology: String? { nil }
}

/// Whether the app may use cellular data.
public enum CTCellularDataRestrictedState: UInt, Sendable {
    case restrictedStateUnknown, restricted, notRestricted
}

/// The app's cellular data setting: not restricted, as the browser decides what the network allows.
open class CTCellularData: NSObject, @unchecked Sendable {
    open var restrictedState: CTCellularDataRestrictedState { .notRestricted }
    /// Called when the setting changes (never, here).
    open var cellularDataRestrictionDidUpdateNotifier: ((CTCellularDataRestrictedState) -> Void)?
}
