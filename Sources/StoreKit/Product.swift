// StoreKit (sw-frameworks): in-app purchases and the App Store, for an app that runs in a
// browser. A web page has no App Store account behind it, so the store is empty: no product
// loads (`Product.products(for:)` answers none), there are no transactions or entitlements, and
// a purchase can't start. Apps that sell things compile unchanged and show their store as
// unavailable, the way they do on a device whose storefront doesn't offer the products.
#if os(WASI)
// Apple's StoreKit re-exports Foundation: a file that imports only StoreKit names `Date` and
// `NSObject` (RevenueCat's StoreKit wrappers, the sweep).
@_exported import WebFoundation
import WebDecimalFormats
#else
import Foundation
#endif

/// Information about a product configured in App Store Connect.
public struct Product: Identifiable, Equatable, Hashable, Sendable {
    public typealias ID = String

    public let id: Product.ID
    public let type: Product.ProductType
    public let displayName: String
    public let description: String
    public let price: Decimal
    public let displayPrice: String
    public let isFamilyShareable: Bool
    public let subscription: Product.SubscriptionInfo?
    /// The currency of `price` (ISO 4217).
    package let currencyCode: String

    /// A product with these details. The App Store makes products; on the web none load, so
    /// only tests and previews make one.
    package init(id: Product.ID, type: Product.ProductType, displayName: String, description: String = "",
                 price: Decimal, displayPrice: String, currencyCode: String = "USD", isFamilyShareable: Bool = false,
                 subscription: Product.SubscriptionInfo? = nil) {
        self.id = id
        self.type = type
        self.displayName = displayName
        self.description = description
        self.price = price
        self.displayPrice = displayPrice
        self.currencyCode = currencyCode
        self.isFamilyShareable = isFamilyShareable
        self.subscription = subscription
    }

    /// The format style that shows `price`, and amounts like it, in the product's currency.
    public var priceFormatStyle: Decimal.FormatStyle.Currency { .currency(code: currencyCode) }

    /// The product's JSON, in the App Store's shape: its identifier and type, and under
    /// `attributes` its name, description and one offer with the price and its currency.
    public var jsonRepresentation: Data {
        func quoted(_ text: String) -> String {
            var out = "\""
            for scalar in text.unicodeScalars {
                switch scalar {
                case "\"": out += "\\\""
                case "\\": out += "\\\\"
                case "\n": out += "\\n"
                case "\r": out += "\\r"
                case "\t": out += "\\t"
                case _ where scalar.value < 0x20:
                    let hex = String(scalar.value, radix: 16)
                    out += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
                default: out.unicodeScalars.append(scalar)
                }
            }
            return out + "\""
        }
        let offer = "{\"currencyCode\":\(quoted(currencyCode)),\"price\":\(quoted("\(price)")),\"priceFormatted\":\(quoted(displayPrice))}"
        let attributes = "{\"name\":\(quoted(displayName)),\"description\":{\"standard\":\(quoted(description))},\"isFamilyShareable\":\(isFamilyShareable ? 1 : 0),\"offers\":[\(offer)]}"
        let json = "{\"id\":\(quoted(id)),\"type\":\(quoted(type.rawValue)),\"attributes\":\(attributes)}"
        return Data(json.utf8)
    }

    /// The format style for a subscription period unit ("month").
    public var subscriptionPeriodUnitFormatStyle: Product.SubscriptionPeriod.Unit.FormatStyle { .init() }

    /// The format style for a subscription period ("1 month").
    public var subscriptionPeriodFormatStyle: Product.SubscriptionPeriod.FormatStyle { .init() }

    /// The products with these identifiers that the App Store offers. On the web the store
    /// offers none, so the answer is empty.
    public static func products<Identifiers: Collection>(for identifiers: Identifiers) async throws -> [Product]
        where Identifiers.Element == Product.ID {
        []
    }

    /// Starts a purchase. On the web there is no store to buy from, so this throws
    /// `Product.PurchaseError.productUnavailable`.
    public func purchase(options: Set<Product.PurchaseOption> = []) async throws -> Product.PurchaseResult {
        throw Product.PurchaseError.productUnavailable
    }

    /// The customer's current entitlement to this product: none on the web.
    public var currentEntitlement: VerificationResult<Transaction>? {
        get async { nil }
    }

    /// The latest transaction for this product: none on the web.
    public var latestTransaction: VerificationResult<Transaction>? {
        get async { nil }
    }

    // MARK: Types

    /// The kind of in-app purchase.
    public struct ProductType: RawRepresentable, Equatable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }

        public static let consumable = ProductType(rawValue: "Consumable")
        public static let nonConsumable = ProductType(rawValue: "Non-Consumable")
        public static let nonRenewable = ProductType(rawValue: "Non-Renewing Subscription")
        public static let autoRenewable = ProductType(rawValue: "Auto-Renewable Subscription")

        /// The type's name for display.
        public var localizedDescription: String { rawValue }
    }

    /// The result of a purchase.
    public enum PurchaseResult: Equatable, Sendable {
        case success(VerificationResult<Transaction>)
        case userCancelled
        case pending
    }

    /// An option for a purchase (an app account token, a quantity, a promotional offer).
    public struct PurchaseOption: Hashable, Sendable {
        package let name: String
        package let value: String

        public static func appAccountToken(_ token: UUID) -> PurchaseOption { PurchaseOption(name: "appAccountToken", value: token.uuidString) }
        public static func quantity(_ quantity: Int) -> PurchaseOption { PurchaseOption(name: "quantity", value: String(quantity)) }
        public static let simulatesAskToBuyInSandbox = PurchaseOption(name: "simulatesAskToBuyInSandbox", value: "true")
        public static func custom(key: String, value: String) -> PurchaseOption { PurchaseOption(name: key, value: value) }
        /// Applies a win-back offer to the purchase.
        public static func winBackOffer(_ offer: Product.SubscriptionOffer) -> PurchaseOption {
            PurchaseOption(name: "winBackOffer", value: offer.id ?? "")
        }
        /// Says, with a signature from the app's server, whether the customer may take the
        /// introductory offer.
        public static func introductoryOfferEligibility(compactJWS: String) -> PurchaseOption {
            PurchaseOption(name: "introductoryOfferEligibility", value: compactJWS)
        }
        /// Applies a promotional offer signed by the app's server as a compact JWS. The App Store
        /// takes it as more than one option, so this answers a list.
        public static func promotionalOffer(_ offerID: String, compactJWS: String) -> [PurchaseOption] {
            [PurchaseOption(name: "promotionalOfferID", value: offerID),
             PurchaseOption(name: "promotionalOfferJWS", value: compactJWS)]
        }
        /// Applies a promotional offer with the signature the app's server made for it.
        public static func promotionalOffer(offerID: String, keyID: String, nonce: UUID, signature: Data, timestamp: Int) -> PurchaseOption {
            PurchaseOption(name: "promotionalOffer", value: [offerID, keyID, nonce.uuidString, signature.base64EncodedString(), String(timestamp)].joined(separator: ":"))
        }
        /// Buys the subscription with one of its billing plans.
        public static func billingPlanType(_ type: Product.SubscriptionInfo.BillingPlanType) -> PurchaseOption {
            PurchaseOption(name: "billingPlanType", value: type.rawValue)
        }
    }

    /// The errors a purchase throws.
    public enum PurchaseError: Error, Equatable, Hashable, Sendable {
        case invalidQuantity
        case productUnavailable
        case purchaseNotAllowed
        case ineligibleForOffer
        case invalidOfferIdentifier
        case invalidOfferPrice
        case invalidOfferSignature
        case missingOfferParameters
        /// The purchase needs a payment method set up for its billing plan.
        case paymentMethodBindingConfigurationRequired
    }

    /// The loading state of a product a store view shows.
    public enum TaskState: Sendable {
        case loading
        case unavailable
        case success(Product)
        case failure(any Error)
    }

    /// The relationships a subscription store shows, relative to the customer's subscription.
    public struct SubscriptionRelationship: Hashable, Sendable {
        package let name: String
        public static let upgrade = SubscriptionRelationship(name: "upgrade")
        public static let downgrade = SubscriptionRelationship(name: "downgrade")
        public static let crossgrade = SubscriptionRelationship(name: "crossgrade")
        public static let current = SubscriptionRelationship(name: "current")
        public static let all = SubscriptionRelationship(name: "all")
    }

    /// The length of a subscription period.
    public struct SubscriptionPeriod: Equatable, Hashable, Sendable {
        public let unit: Unit
        public let value: Int

        package init(value: Int, unit: Unit) {
            self.value = value
            self.unit = unit
        }

        public static let weekly = SubscriptionPeriod(value: 1, unit: .week)
        public static let monthly = SubscriptionPeriod(value: 1, unit: .month)
        public static let everyTwoMonths = SubscriptionPeriod(value: 2, unit: .month)
        public static let everyThreeMonths = SubscriptionPeriod(value: 3, unit: .month)
        public static let everySixMonths = SubscriptionPeriod(value: 6, unit: .month)
        public static let yearly = SubscriptionPeriod(value: 1, unit: .year)

        /// A unit of time in a subscription period.
        public enum Unit: Int, Equatable, Hashable, Sendable, CaseIterable {
            case day = 0
            case week = 1
            case month = 2
            case year = 3

            /// The unit's name ("Month").
            public var localizedDescription: String {
                switch self {
                case .day: "Day"
                case .week: "Week"
                case .month: "Month"
                case .year: "Year"
                }
            }

            /// Formats a subscription period unit as its lowercase name ("month").
            public struct FormatStyle: Codable, Hashable, Sendable {
                public init() {}
                public func format(_ value: Unit) -> String { value.localizedDescription.lowercased() }
            }
        }

        /// Formats a subscription period as a count and a unit ("1 month", "3 months").
        public struct FormatStyle: Codable, Hashable, Sendable {
            public init() {}
            public func format(_ value: SubscriptionPeriod) -> String {
                let unit = value.unit.localizedDescription.lowercased()
                return "\(value.value) \(unit)\(value.value == 1 ? "" : "s")"
            }
        }
    }

    /// An introductory or promotional offer on a subscription.
    public struct SubscriptionOffer: Equatable, Hashable, Sendable {
        public let id: String?
        public let type: OfferType
        public let price: Decimal
        public let displayPrice: String
        public let period: SubscriptionPeriod
        public let periodCount: Int
        public let paymentMode: PaymentMode

        /// An offer with these details. The App Store makes offers; on the web none load, so
        /// only tests and previews make one.
        package init(id: String?, type: OfferType, price: Decimal, displayPrice: String, period: SubscriptionPeriod,
                     periodCount: Int, paymentMode: PaymentMode) {
            self.id = id
            self.type = type
            self.price = price
            self.displayPrice = displayPrice
            self.period = period
            self.periodCount = periodCount
            self.paymentMode = paymentMode
        }

        public struct OfferType: RawRepresentable, Equatable, Hashable, Sendable {
            public let rawValue: String
            public init(rawValue: String) { self.rawValue = rawValue }
            public static let introductory = OfferType(rawValue: "introductory")
            public static let promotional = OfferType(rawValue: "promotional")
            public static let winBack = OfferType(rawValue: "winBack")
        }

        public struct PaymentMode: RawRepresentable, Equatable, Hashable, Sendable {
            public let rawValue: String
            public init(rawValue: String) { self.rawValue = rawValue }
            public static let freeTrial = PaymentMode(rawValue: "freeTrial")
            public static let payAsYouGo = PaymentMode(rawValue: "payAsYouGo")
            public static let payUpFront = PaymentMode(rawValue: "payUpFront")
        }
    }

    /// The subscription details of an auto-renewable product.
    public struct SubscriptionInfo: Equatable, Hashable, Sendable {
        public let subscriptionGroupID: String
        public let subscriptionPeriod: Product.SubscriptionPeriod
        public let groupLevel: Int
        public let groupDisplayName: String
        public let introductoryOffer: Product.SubscriptionOffer?
        public let promotionalOffers: [Product.SubscriptionOffer]
        /// The billing plans the subscription is sold with (paying up front, or monthly over a
        /// commitment), each with its price and offers.
        public let pricingTerms: [Product.SubscriptionInfo.PricingTerms]
        /// The win-back offers for customers whose subscription lapsed.
        public let winBackOffers: [Product.SubscriptionOffer]

        package init(subscriptionGroupID: String, subscriptionPeriod: Product.SubscriptionPeriod, groupLevel: Int = 1,
                     groupDisplayName: String = "", introductoryOffer: Product.SubscriptionOffer? = nil,
                     promotionalOffers: [Product.SubscriptionOffer] = [],
                     pricingTerms: [Product.SubscriptionInfo.PricingTerms] = [],
                     winBackOffers: [Product.SubscriptionOffer] = []) {
            self.pricingTerms = pricingTerms
            self.winBackOffers = winBackOffers
            self.subscriptionGroupID = subscriptionGroupID
            self.subscriptionPeriod = subscriptionPeriod
            self.groupLevel = groupLevel
            self.groupDisplayName = groupDisplayName
            self.introductoryOffer = introductoryOffer
            self.promotionalOffers = promotionalOffers
        }

        /// Whether the customer can take the introductory offer: never on the web, where
        /// nothing can be bought.
        public var isEligibleForIntroOffer: Bool {
            get async { false }
        }

        public static func isEligibleForIntroOffer(for groupID: String) async -> Bool { false }

        /// The statuses of this subscription for the customer and their family: none on the web.
        public var status: [Product.SubscriptionInfo.Status] {
            get async throws { [] }
        }

        /// The statuses of a subscription group: none on the web.
        public static func status(for groupID: String) async throws -> [Product.SubscriptionInfo.Status] { [] }

        /// The renewal state of a subscription.
        public struct RenewalState: RawRepresentable, Equatable, Hashable, Sendable {
            public let rawValue: Int
            public init(rawValue: Int) { self.rawValue = rawValue }
            public static let subscribed = RenewalState(rawValue: 1)
            public static let expired = RenewalState(rawValue: 2)
            public static let inBillingRetryPeriod = RenewalState(rawValue: 3)
            public static let inGracePeriod = RenewalState(rawValue: 4)
            public static let revoked = RenewalState(rawValue: 5)

            public var localizedDescription: String {
                switch self {
                case .subscribed: "Subscribed"
                case .expired: "Expired"
                case .inBillingRetryPeriod: "In Billing Retry Period"
                case .inGracePeriod: "In Grace Period"
                case .revoked: "Revoked"
                default: "Unknown"
                }
            }
        }

        /// Renewal details of a subscription.
        public struct RenewalInfo: Equatable, Hashable, Sendable {
            public let originalTransactionID: UInt64
            public let currentProductID: String
            public let willAutoRenew: Bool
            public let autoRenewPreference: String?
            public let renewalDate: Date?
            public let isInBillingRetry: Bool
            public let gracePeriodExpirationDate: Date?
            /// The win-back offers the customer may take: the App Store names them, so none here.
            public var eligibleWinBackOfferIDs: [String] { [] }
        }

        /// The renewal state, transaction and renewal details of a subscription.
        public struct Status: Equatable, Hashable, Sendable {
            public let state: RenewalState
            public let transaction: VerificationResult<Transaction>
            public let renewalInfo: VerificationResult<RenewalInfo>

            /// Status changes as they happen. On the web there are none, so the sequence ends
            /// without an element.
            public static var updates: AsyncStream<Product.SubscriptionInfo.Status> {
                AsyncStream { $0.finish() }
            }

            /// All subscription statuses for the customer: none on the web.
            public static var all: AsyncStream<(groupID: String, statuses: [Product.SubscriptionInfo.Status])> {
                AsyncStream { $0.finish() }
            }
        }
    }
}

// The format styles conform to Foundation's `FormatStyle` (WebFoundation's on wasm); inside
// the types above, `FormatStyle` names the nested struct, so the conformances are spelled here.
#if os(WASI)
extension Product.SubscriptionPeriod.Unit.FormatStyle: WebFoundation.FormatStyle {}
extension Product.SubscriptionPeriod.FormatStyle: WebFoundation.FormatStyle {}
extension Product.SubscriptionPeriod.Unit {
    public func formatted<S: WebFoundation.FormatStyle>(_ style: S) -> S.FormatOutput where S.FormatInput == Self { style.format(self) }
}
#else
extension Product.SubscriptionPeriod.Unit.FormatStyle: Foundation.FormatStyle {}
extension Product.SubscriptionPeriod.FormatStyle: Foundation.FormatStyle {}
extension Product.SubscriptionPeriod.Unit {
    public func formatted<S: Foundation.FormatStyle>(_ style: S) -> S.FormatOutput where S.FormatInput == Self { style.format(self) }
}
#endif

/// The renewal state of a subscription.
public typealias RenewalState = Product.SubscriptionInfo.RenewalState
/// Renewal details of a subscription.
public typealias RenewalInfo = Product.SubscriptionInfo.RenewalInfo
