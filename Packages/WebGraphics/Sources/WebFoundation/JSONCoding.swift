// Foundation's `JSONEncoder` and `JSONDecoder` on wasm (decision 0021), over the project's
// coder (JSONCoder.swift) and WebFoundation's `Data`: FoundationEssentials' would return its
// own `Data` (an app's `try encoder.encode(x).write(to:)` then fails to type-check) and bring
// its scanner and writer into the bundle (300 KB, decision 0006). Declared here, they shadow
// FoundationEssentials' for every file that imports this module. Every strategy writes and
// reads what Foundation's does: dates, data, keys, non-conforming floats and the output
// formatting, a `URL` as its absolute string, and `userInfo` reaches the values' coders. The
// one gap is `Decimal`, whose own keyed `Codable` is written: naming it would link Foundation's
// Decimal machinery into every app (WebDecimalFormats).
#if os(WASI)
open class JSONEncoder: @unchecked Sendable {
    public struct OutputFormatting: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let prettyPrinted = OutputFormatting(rawValue: 1)
        public static let sortedKeys = OutputFormatting(rawValue: 2)
        public static let withoutEscapingSlashes = OutputFormatting(rawValue: 8)
    }
    /// How dates are written. `.iso8601` is UTC to the second, `2023-11-14T22:13:20Z`.
    public enum DateEncodingStrategy: @unchecked Sendable {
        case deferredToDate, secondsSince1970, millisecondsSince1970, iso8601
        case formatted(DateFormatter)
        case custom(@Sendable (Date, any Encoder) throws -> Void)
    }
    public enum DataEncodingStrategy: Sendable {
        case deferredToData, base64
        case custom(@Sendable (Data, any Encoder) throws -> Void)
    }
    public enum KeyEncodingStrategy: Sendable {
        case useDefaultKeys, convertToSnakeCase
        case custom(@Sendable (_ codingPath: [any CodingKey]) -> any CodingKey)
    }
    public enum NonConformingFloatEncodingStrategy: Sendable {
        case `throw`
        case convertToString(positiveInfinity: String, negativeInfinity: String, nan: String)
    }

    open var outputFormatting: OutputFormatting = []
    open var dateEncodingStrategy: DateEncodingStrategy = .deferredToDate
    open var dataEncodingStrategy: DataEncodingStrategy = .base64
    open var keyEncodingStrategy: KeyEncodingStrategy = .useDefaultKeys
    open var nonConformingFloatEncodingStrategy: NonConformingFloatEncodingStrategy = .throw
    open var userInfo: [CodingUserInfoKey: Any] = [:]

    public init() {}

    open func encode<T: Encodable>(_ value: T) throws -> Data {
        var options = _JSONEncodingOptions()
        switch dateEncodingStrategy {
        case .deferredToDate: options.dateStrategy = .deferred
        case .secondsSince1970: options.dateStrategy = .secondsSince1970
        case .millisecondsSince1970: options.dateStrategy = .millisecondsSince1970
        case .iso8601: options.dateStrategy = .iso8601
        case .formatted(let formatter): options.dateStrategy = .formatted(formatter)
        case .custom(let encode): options.dateStrategy = .custom(encode)
        }
        switch dataEncodingStrategy {
        case .deferredToData: options.dataStrategy = .deferred
        case .base64: options.dataStrategy = .base64
        case .custom(let encode): options.dataStrategy = .custom(encode)
        }
        switch keyEncodingStrategy {
        case .useDefaultKeys: options.keyStrategy = .useDefault
        case .convertToSnakeCase: options.keyStrategy = .snakeCase
        case .custom(let convert): options.keyStrategy = .custom(convert)
        }
        if case .convertToString(let positive, let negative, let nan) = nonConformingFloatEncodingStrategy {
            options.nonConformingFloats = (positive, negative, nan)
        }
        options.urlsAsStrings = true
        options.userInfo = userInfo
        var format = _JSONFormat()
        format.prettyPrinted = outputFormatting.contains(.prettyPrinted)
        format.sortedKeys = outputFormatting.contains(.sortedKeys)
        format.escapesSlashes = !outputFormatting.contains(.withoutEscapingSlashes)
        return try _TransferJSONEncoder().encode(value, options: options, format: format)
    }
}

open class JSONDecoder: @unchecked Sendable {
    /// How dates are read. `.iso8601` also takes a fraction of a second.
    public enum DateDecodingStrategy: @unchecked Sendable {
        case deferredToDate, secondsSince1970, millisecondsSince1970, iso8601
        case formatted(DateFormatter)
        case custom(@Sendable (_ decoder: any Decoder) throws -> Date)
    }
    public enum DataDecodingStrategy: Sendable {
        case deferredToData, base64
        case custom(@Sendable (_ decoder: any Decoder) throws -> Data)
    }
    public enum KeyDecodingStrategy: Sendable {
        case useDefaultKeys, convertFromSnakeCase
        case custom(@Sendable (_ codingPath: [any CodingKey]) -> any CodingKey)
    }
    public enum NonConformingFloatDecodingStrategy: Sendable {
        case `throw`
        case convertFromString(positiveInfinity: String, negativeInfinity: String, nan: String)
    }

    open var dateDecodingStrategy: DateDecodingStrategy = .deferredToDate
    open var dataDecodingStrategy: DataDecodingStrategy = .base64
    open var keyDecodingStrategy: KeyDecodingStrategy = .useDefaultKeys
    open var nonConformingFloatDecodingStrategy: NonConformingFloatDecodingStrategy = .throw
    open var userInfo: [CodingUserInfoKey: Any] = [:]
    /// Reads JSON5 too (comments, trailing commas, unquoted keys; JSON5.swift).
    open var allowsJSON5 = false
    /// With `allowsJSON5`, takes a top-level object without its braces.
    open var assumesTopLevelDictionary = false

    public init() {}

    open func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        if allowsJSON5 {
            guard let json = _JSON5.json(Array(data), assumesTopLevelDictionary: assumesTopLevelDictionary) else {
                throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "The given data was not valid JSON5."))
            }
            return try _decode(type, from: Data(json))
        }
        return try _decode(type, from: data)
    }

    private func _decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        var options = _JSONDecodingOptions()
        switch dateDecodingStrategy {
        case .deferredToDate: options.dateStrategy = .deferred
        case .secondsSince1970: options.dateStrategy = .secondsSince1970
        case .millisecondsSince1970: options.dateStrategy = .millisecondsSince1970
        case .iso8601: options.dateStrategy = .iso8601
        case .formatted(let formatter): options.dateStrategy = .formatted(formatter)
        case .custom(let decode): options.dateStrategy = .custom(decode)
        }
        switch dataDecodingStrategy {
        case .deferredToData: options.dataStrategy = .deferred
        case .base64: options.dataStrategy = .base64
        case .custom(let decode): options.dataStrategy = .custom(decode)
        }
        switch keyDecodingStrategy {
        case .useDefaultKeys: break
        case .convertFromSnakeCase: options.convertsFromSnakeCase = true
        case .custom(let convert): options.keyConverter = convert
        }
        if case .convertFromString(let positive, let negative, let nan) = nonConformingFloatDecodingStrategy {
            options.nonConformingFloats = (positive, negative, nan)
        }
        options.userInfo = userInfo
        return try _TransferJSONDecoder().decode(type, from: data, options: options)
    }
}
#endif
