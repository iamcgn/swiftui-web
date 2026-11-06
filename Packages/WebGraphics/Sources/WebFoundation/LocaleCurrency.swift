// `Locale.Currency` on wasm: a currency by its ISO 4217 code. It lives here, beside `Locale`,
// so every module sees one type (StoreKit's transactions name it); the locale's own currency
// and the list of codes come with WebFoundationFormats, which holds the region table.
#if os(WASI)
extension Locale {
    /// A currency, by its ISO 4217 code ("USD").
    public struct Currency: Hashable, Sendable, Codable, ExpressibleByStringLiteral, CustomStringConvertible, CustomDebugStringConvertible {
        public let identifier: String
        public init(_ identifier: String) { self.identifier = identifier }
        public init(stringLiteral value: String) { self.identifier = value }
        public var description: String { identifier }
        public var debugDescription: String { identifier }
        /// Whether the code is an ISO 4217 one: three letters.
        public var isISOCurrency: Bool { identifier.count == 3 && identifier.allSatisfy(\.isLetter) }
    }
}
#endif
