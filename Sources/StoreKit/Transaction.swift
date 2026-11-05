// Transactions, verification, the App Store and the app's own purchase record. On the web the
// customer has bought nothing in the app: the transaction sequences end without an element,
// there is no entitlement, and `AppTransaction.shared` throws because no App Store signed one.
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif
#if canImport(FoundationNetworking)
import FoundationNetworking   // Linux keeps URLError's networking codes here
#endif
import SwiftUI

/// The result of StoreKit verifying a signed value (a transaction, renewal details, the app
/// transaction).
public enum VerificationResult<SignedType> {
    case unverified(SignedType, VerificationResult<SignedType>.VerificationError)
    case verified(SignedType)

    /// The reason StoreKit couldn't verify a value.
    public enum VerificationError: Error, Equatable, Hashable, Sendable {
        case revokedCertificate
        case invalidCertificateChain
        case invalidDeviceVerification
        case invalidEncoding
        case invalidSignature
        case missingRequiredProperties
    }

    /// The verified value; throws the verification error for an unverified one.
    public var payloadValue: SignedType {
        get throws {
            switch self {
            case .verified(let value): return value
            case .unverified(_, let error): throw error
            }
        }
    }

    /// The value, whether or not StoreKit verified it.
    public var unsafePayloadValue: SignedType {
        switch self {
        case .verified(let value), .unverified(let value, _): return value
        }
    }

    /// The signed value as a JSON web signature. Nothing on the web is signed, so it is empty.
    public var jwsRepresentation: String { "" }
}

extension VerificationResult: Sendable where SignedType: Sendable {}
extension VerificationResult: Equatable where SignedType: Equatable {}
extension VerificationResult: Hashable where SignedType: Hashable {}

/// A purchase the customer made in the app.
public struct Transaction: Identifiable, Equatable, Hashable, Sendable {
    public let id: UInt64
    public let originalID: UInt64
    public let productID: String
    public let productType: Product.ProductType
    public let subscriptionGroupID: String?
    public let appBundleID: String
    public let purchaseDate: Date
    public let originalPurchaseDate: Date
    public let expirationDate: Date?
    public let purchasedQuantity: Int
    public let isUpgraded: Bool
    public let ownershipType: OwnershipType
    public let signedDate: Date
    public let revocationDate: Date?
    public let revocationReason: RevocationReason?
    public let appAccountToken: UUID?
    public let environment: AppStore.Environment
    /// What the customer paid, in `currency`: nil when the App Store didn't say.
    public let price: Decimal?
    /// The currency of `price`.
    public let currency: Locale.Currency?
    /// The offer the purchase redeemed, if any.
    public let offer: Offer?
    /// Why the transaction happened.
    public let reason: Reason

    /// The ISO 4217 code of `currency`.
    public var currencyCode: String? { currency?.identifier }
    /// The type of `offer`.
    public var offerType: OfferType? { offer?.type }
    /// The identifier of `offer`.
    public var offerID: String? { offer?.id }
    /// The payment mode of `offer`, as its raw string.
    public var offerPaymentModeStringRepresentation: String? { offer?.paymentMode?.rawValue }

    /// A transaction with these details. Only the App Store makes transactions; on the web none
    /// exist, so only tests make one.
    package init(id: UInt64, productID: String, productType: Product.ProductType, purchaseDate: Date,
                 expirationDate: Date? = nil, purchasedQuantity: Int = 1, subscriptionGroupID: String? = nil,
                 revocationDate: Date? = nil, revocationReason: RevocationReason? = nil) {
        self.id = id
        self.originalID = id
        self.productID = productID
        self.productType = productType
        self.subscriptionGroupID = subscriptionGroupID
        self.appBundleID = ""
        self.purchaseDate = purchaseDate
        self.originalPurchaseDate = purchaseDate
        self.expirationDate = expirationDate
        self.purchasedQuantity = purchasedQuantity
        self.isUpgraded = false
        self.ownershipType = .purchased
        self.signedDate = purchaseDate
        self.revocationDate = revocationDate
        self.revocationReason = revocationReason
        self.appAccountToken = nil
        self.environment = .production
        self.price = nil
        self.currency = nil
        self.offer = nil
        self.reason = .purchase
    }

    /// The kind of offer a transaction redeemed.
    public struct OfferType: RawRepresentable, Equatable, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let introductory = OfferType(rawValue: 1)
        public static let promotional = OfferType(rawValue: 2)
        public static let code = OfferType(rawValue: 3)
        public static let winBack = OfferType(rawValue: 4)
    }

    /// How the customer pays for an offer.
    public struct OfferPaymentMode: RawRepresentable, Equatable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let freeTrial = OfferPaymentMode(rawValue: "FREE_TRIAL")
        public static let payAsYouGo = OfferPaymentMode(rawValue: "PAY_AS_YOU_GO")
        public static let payUpFront = OfferPaymentMode(rawValue: "PAY_UP_FRONT")
    }

    /// The offer a transaction redeemed.
    public struct Offer: Equatable, Hashable, Sendable {
        public let id: String?
        public let type: OfferType
        public let paymentMode: OfferPaymentMode?
        package init(id: String?, type: OfferType, paymentMode: OfferPaymentMode?) {
            self.id = id
            self.type = type
            self.paymentMode = paymentMode
        }
    }

    /// Why a transaction happened: a purchase, or the renewal of a subscription.
    public struct Reason: RawRepresentable, Equatable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let purchase = Reason(rawValue: "PURCHASE")
        public static let renewal = Reason(rawValue: "RENEWAL")
    }

    /// Tells the App Store the app delivered the purchase. Nothing is waiting on the web.
    public func finish() async {}

    /// The transaction's JSON. Nothing on the web is signed, so it is empty.
    public var jsonRepresentation: Data { Data() }

    // MARK: Sequences

    /// A sequence of transactions. On the web every one of them is empty: it ends without an
    /// element.
    public struct Transactions: AsyncSequence, Sendable {
        public typealias Element = VerificationResult<Transaction>
        public typealias Failure = Never
        public struct AsyncIterator: AsyncIteratorProtocol {
            public typealias Failure = Never
            public mutating func next() async -> VerificationResult<Transaction>? { nil }
        }
        public func makeAsyncIterator() -> AsyncIterator { AsyncIterator() }
    }

    /// Transactions made outside the app or on another device, as they arrive.
    public static var updates: Transactions { Transactions() }
    /// Every transaction the customer made in the app.
    public static var all: Transactions { Transactions() }
    /// The transactions that entitle the customer to products now.
    public static var currentEntitlements: Transactions { Transactions() }
    /// Transactions the app hasn't finished.
    public static var unfinished: Transactions { Transactions() }

    /// The transactions that entitle the customer to one product now.
    public static func currentEntitlements(for productID: String) -> Transactions { Transactions() }
    /// All transactions for one product.
    public static func all(for productID: String) -> Transactions { Transactions() }

    /// The transaction that entitles the customer to a product: none on the web.
    public static func currentEntitlement(for productID: String) async -> VerificationResult<Transaction>? { nil }

    /// The customer's latest transaction for a product: none on the web.
    public static func latest(for productID: String) async -> VerificationResult<Transaction>? { nil }

    /// Asks the App Store for a refund of a transaction. There is no App Store on the web, so
    /// this throws `RefundRequestError.failed`.
    @MainActor
    public static func beginRefundRequest(for transactionID: UInt64, in scene: UIWindowScene) async throws -> RefundRequestStatus {
        throw RefundRequestError.failed
    }

    /// Asks the App Store for a refund of this transaction (throws on the web).
    @MainActor
    public func beginRefundRequest(in scene: UIWindowScene) async throws -> RefundRequestStatus {
        throw RefundRequestError.failed
    }

    // MARK: Types

    /// Whether the customer bought the product or a family member shared it.
    public struct OwnershipType: RawRepresentable, Equatable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let purchased = OwnershipType(rawValue: "PURCHASED")
        public static let familyShared = OwnershipType(rawValue: "FAMILY_SHARED")
    }

    /// Why the App Store refunded or revoked a transaction.
    public struct RevocationReason: RawRepresentable, Equatable, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let developerIssue = RevocationReason(rawValue: 1)
        public static let other = RevocationReason(rawValue: 0)

        public var localizedDescription: String {
            self == .developerIssue ? "Developer issue" : "Other"
        }
    }

    /// How a refund request ended.
    public enum RefundRequestStatus: Equatable, Hashable, Sendable {
        case success
        case userCancelled
    }

    /// Why a refund request failed.
    public enum RefundRequestError: Error, Equatable, Hashable, Sendable {
        case duplicateRequest
        case failed
    }
}

/// The App Store: syncing purchases, the review prompt, managing subscriptions.
public enum AppStore {
    /// The server environment a transaction comes from.
    public struct Environment: RawRepresentable, Equatable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let production = Environment(rawValue: "Production")
        public static let sandbox = Environment(rawValue: "Sandbox")
        public static let xcode = Environment(rawValue: "Xcode")
    }

    /// Whether the customer can make payments: never on the web.
    public static var canMakePayments: Bool { false }

    /// Syncs the customer's transactions with the App Store. There is nothing to sync on the
    /// web, so this returns at once.
    public static func sync() async throws {}

    /// Asks for an App Store rating. The web has no rating prompt, so nothing is shown.
    @MainActor
    public static func requestReview(in scene: UIWindowScene) {}

    /// Shows the App Store's subscription management. The web has none, so nothing is shown.
    @MainActor
    public static func showManageSubscriptions(in scene: UIWindowScene) async throws {}

    /// Shows the App Store's subscription management for one group (nothing on the web).
    @MainActor
    public static func showManageSubscriptions(in scene: UIWindowScene, subscriptionGroupID: String) async throws {}

    /// Shows the App Store's offer code redemption. The web has none, so this throws.
    @MainActor
    public static func presentOfferCodeRedeemSheet(in scene: UIWindowScene) async throws {
        throw StoreKitError.unsupported
    }
}

/// The App Store's signed record of the customer's purchase of the app itself.
public struct AppTransaction: Equatable, Hashable, Sendable {
    public let environment: AppStore.Environment
    public let appVersion: String
    public let originalAppVersion: String
    public let bundleID: String
    public let originalPurchaseDate: Date
    public let signedDate: Date

    /// The app transaction. No App Store signed one for a web page, so this throws
    /// `StoreKitError.unsupported`.
    public static var shared: VerificationResult<AppTransaction> {
        get async throws { throw StoreKitError.unsupported }
    }

    /// Asks the App Store for the app transaction again (throws on the web).
    public static func refresh() async throws -> VerificationResult<AppTransaction> {
        throw StoreKitError.unsupported
    }
}

/// The errors StoreKit throws.
public enum StoreKitError: Error, Sendable {
    case unknown
    case userCancelled
    case networkError(URLError)
    case systemError(any Error)
    case notAvailableInStorefront
    case notEntitled
    case unsupported
}
