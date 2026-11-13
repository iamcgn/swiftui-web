// The newer StoreKit names a purchase library builds against: a subscription's billing plans
// (paying up front or monthly over a commitment), purchase intents from the App Store, and the
// external purchase custom link. On the web nothing can be bought, so no product has billing
// plans, no purchase intent arrives, and the custom link is not eligible.
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif

extension Product.SubscriptionInfo {
    /// How a subscription with a commitment is billed.
    public struct BillingPlanType: RawRepresentable, Equatable, Hashable, Sendable, CustomStringConvertible {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        /// The whole commitment is paid at once.
        public static let upFront = BillingPlanType(rawValue: "upFront")
        /// The commitment is paid in monthly installments.
        public static let monthly = BillingPlanType(rawValue: "monthly")
        public var description: String { rawValue }
    }

    /// One billing plan of a subscription: how it is billed, what each payment costs, the
    /// commitment it pays for, and the offers on it.
    public struct PricingTerms: Equatable, Hashable, Sendable {
        /// The period the customer commits to.
        public struct CommitmentInfo: Equatable, Hashable, Sendable {
            public let period: Product.SubscriptionPeriod
            public init(period: Product.SubscriptionPeriod) { self.period = period }
        }

        public let billingPlanType: BillingPlanType
        public let billingPrice: Decimal
        public let billingDisplayPrice: String
        public let commitmentInfo: CommitmentInfo
        public let subscriptionOffers: [Product.SubscriptionOffer]

        package init(billingPlanType: BillingPlanType, billingPrice: Decimal, billingDisplayPrice: String,
                     commitmentInfo: CommitmentInfo, subscriptionOffers: [Product.SubscriptionOffer] = []) {
            self.billingPlanType = billingPlanType
            self.billingPrice = billingPrice
            self.billingDisplayPrice = billingDisplayPrice
            self.commitmentInfo = commitmentInfo
            self.subscriptionOffers = subscriptionOffers
        }
    }
}

/// A purchase the customer started on the App Store (a promoted in-app purchase, a win-back
/// offer) for the app to complete. None reach a web page.
public struct PurchaseIntent: Identifiable, Equatable, Hashable, Sendable {
    public let product: Product
    public let offer: Product.SubscriptionOffer?
    public var id: Product.ID { product.id }

    package init(product: Product, offer: Product.SubscriptionOffer? = nil) {
        self.product = product
        self.offer = offer
    }

    /// The purchase intents as they arrive: none ever does on the web, so the sequence waits.
    public static var intents: PurchaseIntents { PurchaseIntents() }

    /// The sequence of purchase intents.
    public struct PurchaseIntents: AsyncSequence, Sendable {
        public typealias Element = PurchaseIntent

        public struct AsyncIterator: AsyncIteratorProtocol {
            public mutating func next() async -> PurchaseIntent? {
                // Waits until the task is cancelled, as Apple's sequence waits for an intent.
                while !Task.isCancelled { try? await Task.sleep(nanoseconds: 3_600_000_000_000) }
                return nil
            }
        }

        public func makeAsyncIterator() -> AsyncIterator { AsyncIterator() }
    }
}

/// A link out of the app to buy elsewhere, with the notice Apple shows first. A web page is
/// never eligible: there is no App Store account to report the purchase to.
public enum ExternalPurchaseCustomLink {
    /// Whether the app may link out to purchases: never on the web.
    public static var isEligible: Bool {
        get async { false }
    }

    /// The notices shown before leaving the app.
    public enum NoticeType: Equatable, Hashable, Sendable {
        case browser
        case withinApp
    }

    /// What the customer chose in the notice.
    public enum NoticeResult: Equatable, Hashable, Sendable {
        case continued
        case cancelled
    }

    /// A token reporting an external purchase to Apple.
    public struct Token: Equatable, Hashable, Sendable {
        public let value: String
        public let tokenType: String
    }

    /// The token of the type ("ACQUISITION", "SERVICES"): none, as the app is not eligible.
    public static func token(for tokenType: String) async throws -> Token? { nil }

    /// Shows the notice: the app is not eligible, so the call fails without showing anything.
    public static func showNotice(type: NoticeType) async throws -> NoticeResult {
        throw StoreKitError.notAvailableInStorefront
    }
}
