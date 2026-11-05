// The App Store storefront: the country or region a customer buys in. On the web there is no
// App Store account, so there is no current storefront and the updates end without one.
// A transaction still names a storefront, as StoreKit's always does; only tests make one.
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif

/// An App Store country or region.
public struct Storefront: Identifiable, Hashable, Sendable {
    /// The App Store's identifier for the storefront.
    public let id: String
    /// The three-letter ISO 3166-1 code of the country or region.
    public let countryCode: String
    /// The storefront's currency, when known.
    public let currency: Locale.Currency?

    package init(id: String, countryCode: String, currency: Locale.Currency? = nil) {
        self.id = id
        self.countryCode = countryCode
        self.currency = currency
    }

    /// The customer's current storefront: none on the web.
    public static var current: Storefront? {
        get async { nil }
    }

    /// Changes to the customer's storefront. On the web the sequence ends without one.
    public struct Storefronts: AsyncSequence, Sendable {
        public typealias Element = Storefront
        public typealias Failure = Never
        public struct AsyncIterator: AsyncIteratorProtocol {
            public typealias Failure = Never
            public mutating func next() async -> Storefront? { nil }
        }
        public func makeAsyncIterator() -> AsyncIterator { AsyncIterator() }
    }

    /// The storefront's changes, as they happen.
    public static var updates: Storefronts { Storefronts() }
}
