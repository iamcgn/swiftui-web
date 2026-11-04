// Offers and storefronts in both StoreKit APIs. On the web there is no App Store, so no product
// carries a discount, the payment queue has no storefront, and `Storefront.current` is nil;
// the types exist so code that reads them (subscription SDKs, paywalls) builds and runs.
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif

// MARK: - Original API

/// A discount a product offers: an introductory price or a promotional offer.
open class SKProductDiscount: NSObject {
    public enum PaymentMode: UInt, Sendable {
        case payAsYouGo = 0, payUpFront, freeTrial
    }
    public enum `Type`: UInt, Sendable {
        case introductory = 0, subscription
    }

    open private(set) var identifier: String?
    open private(set) var price: NSDecimalNumber
    open private(set) var priceLocale: Locale
    open private(set) var paymentMode: PaymentMode
    open private(set) var numberOfPeriods: Int
    open private(set) var subscriptionPeriod: SKProductSubscriptionPeriod
    open private(set) var type: `Type`

    package init(identifier: String?, price: NSDecimalNumber, priceLocale: Locale, paymentMode: PaymentMode,
                 numberOfPeriods: Int, subscriptionPeriod: SKProductSubscriptionPeriod, type: `Type`) {
        self.identifier = identifier
        self.price = price
        self.priceLocale = priceLocale
        self.paymentMode = paymentMode
        self.numberOfPeriods = numberOfPeriods
        self.subscriptionPeriod = subscriptionPeriod
        self.type = type
        super.init()
    }
}

/// A signed promotional offer attached to a payment.
open class SKPaymentDiscount: NSObject {
    public let identifier: String
    public let keyIdentifier: String
    public let nonce: UUID
    public let signature: String
    public let timestamp: NSNumber

    public init(identifier: String, keyIdentifier: String, nonce: UUID, signature: String, timestamp: NSNumber) {
        self.identifier = identifier
        self.keyIdentifier = keyIdentifier
        self.nonce = nonce
        self.signature = signature
        self.timestamp = timestamp
        super.init()
    }
}

/// The App Store country a payment queue sells in.
open class SKStorefront: NSObject {
    /// The three-letter country code ("USA").
    open private(set) var countryCode: String
    /// The store's identifier.
    open private(set) var identifier: String

    package init(countryCode: String, identifier: String) {
        self.countryCode = countryCode
        self.identifier = identifier
        super.init()
    }
}

/// The object a payment queue asks before it continues a transaction.
public protocol SKPaymentQueueDelegate: AnyObject {
    func paymentQueue(_ paymentQueue: SKPaymentQueue, shouldContinue transaction: SKPaymentTransaction,
                      in newStorefront: SKStorefront) -> Bool
    func paymentQueueShouldShowPriceConsent(_ paymentQueue: SKPaymentQueue) -> Bool
}

extension SKPaymentQueueDelegate {
    public func paymentQueue(_ paymentQueue: SKPaymentQueue, shouldContinue transaction: SKPaymentTransaction,
                             in newStorefront: SKStorefront) -> Bool { true }
    public func paymentQueueShouldShowPriceConsent(_ paymentQueue: SKPaymentQueue) -> Bool { true }
}

// MARK: - Current API

/// The App Store country the customer buys from. The web has none, so `current` is nil and
/// `updates` ends without yielding.
public struct Storefront: Identifiable, Equatable, Hashable, Sendable {
    /// The three-letter country code ("USA").
    public let countryCode: String
    public let id: String

    package init(countryCode: String, id: String) {
        self.countryCode = countryCode
        self.id = id
    }

    public static var current: Storefront? { get async { nil } }

    /// Storefront changes: none on the web, so the sequence ends at once.
    public static var updates: AsyncStream<Storefront> { AsyncStream { _ in } }
}
