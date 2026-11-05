// `Locale.Currency` on wasm, which a transaction's `currency` names: WebFoundation's `Locale`
// stand-in has no currency type. Apple platforms and Linux use Foundation's.
#if os(WASI)
import WebFoundation

extension Locale {
    /// A currency, by its ISO 4217 code ("USD").
    public struct Currency: Hashable, Sendable, Codable, ExpressibleByStringLiteral, CustomStringConvertible {
        public let identifier: String
        public init(_ identifier: String) { self.identifier = identifier }
        public init(stringLiteral value: String) { self.identifier = value }
        public var description: String { identifier }
        /// Whether the code is an ISO 4217 one: three letters.
        public var isISOCurrency: Bool { identifier.count == 3 && identifier.allSatisfy(\.isLetter) }
    }
}
#endif
