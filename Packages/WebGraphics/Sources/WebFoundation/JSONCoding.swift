// Foundation's `JSONEncoder` and `JSONDecoder` on wasm (decision 0021), over the project's
// coder (JSONCoder.swift) and WebFoundation's `Data`: FoundationEssentials' would return its
// own `Data` (an app's `try encoder.encode(x).write(to:)` then fails to type-check) and bring
// its scanner and writer into the bundle (300 KB, decision 0006). Declared here, they shadow
// FoundationEssentials' for every file that imports this module. The strategies are accepted;
// dates encode as seconds since 2001 (`Codable`'s default) and keys as written.
#if os(WASI)
open class JSONEncoder {
    public struct OutputFormatting: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let prettyPrinted = OutputFormatting(rawValue: 1)
        public static let sortedKeys = OutputFormatting(rawValue: 2)
        public static let withoutEscapingSlashes = OutputFormatting(rawValue: 8)
    }
    public enum DateEncodingStrategy { case deferredToDate, secondsSince1970, millisecondsSince1970, iso8601 }
    public enum KeyEncodingStrategy { case useDefaultKeys, convertToSnakeCase }
    public enum DataEncodingStrategy { case deferredToData, base64 }

    open var outputFormatting: OutputFormatting = []
    open var dateEncodingStrategy: DateEncodingStrategy = .deferredToDate
    open var keyEncodingStrategy: KeyEncodingStrategy = .useDefaultKeys
    open var dataEncodingStrategy: DataEncodingStrategy = .base64
    open var userInfo: [CodingUserInfoKey: Any] = [:]

    public init() {}

    open func encode<T: Encodable>(_ value: T) throws -> Data {
        try _TransferJSONEncoder().encode(value)
    }
}

open class JSONDecoder {
    public enum DateDecodingStrategy { case deferredToDate, secondsSince1970, millisecondsSince1970, iso8601 }
    public enum KeyDecodingStrategy { case useDefaultKeys, convertFromSnakeCase }
    public enum DataDecodingStrategy { case deferredToData, base64 }

    open var dateDecodingStrategy: DateDecodingStrategy = .deferredToDate
    open var keyDecodingStrategy: KeyDecodingStrategy = .useDefaultKeys
    open var dataDecodingStrategy: DataDecodingStrategy = .base64
    open var userInfo: [CodingUserInfoKey: Any] = [:]

    public init() {}

    open func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        var options = _JSONDecodingOptions()
        switch dateDecodingStrategy {
        case .deferredToDate: options.dateStrategy = .deferred
        case .secondsSince1970: options.dateStrategy = .secondsSince1970
        case .millisecondsSince1970: options.dateStrategy = .millisecondsSince1970
        case .iso8601: options.dateStrategy = .iso8601
        }
        options.convertsFromSnakeCase = keyDecodingStrategy == .convertFromSnakeCase
        return try _TransferJSONDecoder().decode(type, from: data, options: options)
    }
}
#endif
