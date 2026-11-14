// Translation on the web: sessions translate with the browser's on-device translator (Chrome's
// `Translator`, through TranslationHost), which, like Apple's, downloads a language pair's model
// once and then works offline. A session made with `init(installedSource:target:)` only uses pairs
// already on the device; one a `translationTask` hands the app may download them. A missing source
// language is detected (Chrome's `LanguageDetector`), a missing target is the person's preferred
// language. A browser without a translator (Safari, Firefox, the host tests) supports no pairs:
// every language reads as unsupported and a translation throws, as a device without the
// languages would. The SwiftUI modifiers are in TranslationViews.swift.
#if os(WASI)
import WebFoundation
import WebFoundationFormats
#else
import Foundation
#endif
import TranslationHost

/// Why a translation failed.
public struct TranslationError: Error, Equatable, Hashable, Sendable, CustomStringConvertible {
    enum Kind: Hashable, Sendable {
        case unsupportedSourceLanguage, unsupportedTargetLanguage, unsupportedLanguagePairing
        case unableToIdentifyLanguage, nothingToTranslate, internalError, notInstalled
    }
    let kind: Kind

    /// The source language is not one the translator knows.
    public static let unsupportedSourceLanguage = TranslationError(kind: .unsupportedSourceLanguage)
    /// The target language is not one the translator knows.
    public static let unsupportedTargetLanguage = TranslationError(kind: .unsupportedTargetLanguage)
    /// The translator does not translate between the two languages.
    public static let unsupportedLanguagePairing = TranslationError(kind: .unsupportedLanguagePairing)
    /// The source language was not given and could not be detected.
    public static let unableToIdentifyLanguage = TranslationError(kind: .unableToIdentifyLanguage)
    /// The text is empty.
    public static let nothingToTranslate = TranslationError(kind: .nothingToTranslate)
    /// The translator failed.
    public static let internalError = TranslationError(kind: .internalError)
    /// The pair's model is not on the device, and the session may not download it.
    public static let notInstalled = TranslationError(kind: .notInstalled)

    public var description: String { "TranslationError.\(kind)" }
}

/// What the device can do for a pair of languages.
public final class LanguageAvailability: Sendable {
    /// A pair's state.
    public enum Status: Sendable, Equatable, Hashable {
        /// The pair's model is on the device: it translates offline.
        case installed
        /// The device can translate once it downloads the pair's model.
        case supported
        /// The device does not translate between the two.
        case unsupported
    }

    public init() {}

    /// The state of the pair `source` to `target` (nil: the person's preferred language).
    public func status(from source: Locale.Language, to target: Locale.Language?) async -> Status {
        let target = target ?? _preferredLanguage()
        return Self.status(await _availability(source, target))
    }

    /// The state of translating `text` (its language detected) to `target`.
    public func status(for text: String, to target: Locale.Language?) async throws -> Status {
        guard let source = await _detect(text) else { throw TranslationError.unableToIdentifyLanguage }
        return await status(from: source, to: target)
    }

    /// The languages the browser's translator knows; none without one.
    public var supportedLanguages: [Locale.Language] {
        get async {
            guard _TranslationHost.translate != nil else { return [] }
            return _translatorLanguages.map { Locale.Language(identifier: $0) }
        }
    }

    static func status(_ availability: _TranslationHost.Availability) -> Status {
        switch availability {
        case .available: .installed
        case .downloadable: .supported
        case .unavailable: .unsupported
        }
    }
}

/// Translates text between two languages.
public final class TranslationSession: @unchecked Sendable {
    /// What a `translationTask` translates between. Changing it, or calling `invalidate()`, runs
    /// the task again with a new session.
    public struct Configuration: Equatable, Hashable, Sendable {
        /// The language to translate from; nil detects it from the text.
        public var source: Locale.Language?
        /// The language to translate to; nil is the person's preferred language.
        public var target: Locale.Language?
        /// Counts the calls to `invalidate()`.
        public private(set) var version: Int = 0

        public init(source: Locale.Language? = nil, target: Locale.Language? = nil) {
            self.source = source
            self.target = target
        }

        /// Runs the configuration's task again.
        public mutating func invalidate() { version += 1 }
    }

    /// Text to translate in a batch, with an identifier to match its response.
    public struct Request: Sendable, Hashable {
        public var sourceText: String
        public var clientIdentifier: String?

        public init(sourceText: String, clientIdentifier: String? = nil) {
            self.sourceText = sourceText
            self.clientIdentifier = clientIdentifier
        }
    }

    /// A translation.
    public struct Response: Sendable, Hashable {
        public var sourceLanguage: Locale.Language
        public var targetLanguage: Locale.Language
        public var sourceText: String
        public var targetText: String
        public var clientIdentifier: String?
    }

    /// The responses to a batch, in the order of its requests.
    public struct BatchResponse: AsyncSequence, Sendable {
        public typealias Element = Response
        let stream: AsyncThrowingStream<Response, any Error>

        public struct AsyncIterator: AsyncIteratorProtocol {
            var iterator: AsyncThrowingStream<Response, any Error>.AsyncIterator
            public mutating func next() async throws -> Response? { try await iterator.next() }
        }

        public func makeAsyncIterator() -> AsyncIterator { AsyncIterator(iterator: stream.makeAsyncIterator()) }
    }

    /// The language translated from; nil when each text's language is detected.
    public let sourceLanguage: Locale.Language?
    /// The language translated to; nil when it is the person's preferred language.
    public let targetLanguage: Locale.Language?
    /// Whether the session may download a pair's model (a `translationTask`'s may; one made with
    /// `init(installedSource:target:)` only uses models on the device).
    public let canRequestDownloads: Bool
    private let lock = NSLock()
    private var cancelled = false

    /// A session over models already on the device.
    public init(installedSource: Locale.Language, target: Locale.Language? = nil) {
        sourceLanguage = installedSource
        targetLanguage = target
        canRequestDownloads = false
    }

    init(configuration: Configuration) {
        sourceLanguage = configuration.source
        targetLanguage = configuration.target
        canRequestDownloads = true
    }

    /// Whether the session translates without a download: both languages known and their model
    /// on the device.
    public var isReady: Bool {
        get async {
            guard let source = sourceLanguage else { return false }
            return await _availability(source, targetLanguage ?? _preferredLanguage()) == .available
        }
    }

    /// Downloads the pair's model when the session may and it is not on the device yet.
    public func prepareTranslation() async throws {
        guard let source = sourceLanguage else { return }
        try await ready(source, targetLanguage ?? _preferredLanguage())
    }

    /// Translates `string`.
    public func translate(_ string: String) async throws -> Response {
        try checkCancelled()
        guard !string.allSatisfy(\.isWhitespace) else { throw TranslationError.nothingToTranslate }
        let source: Locale.Language
        if let sourceLanguage {
            source = sourceLanguage
        } else if let detected = await _detect(string) {
            source = detected
        } else {
            throw TranslationError.unableToIdentifyLanguage
        }
        let target = targetLanguage ?? _preferredLanguage()
        // The same language needs no translator.
        if _code(source) == _code(target) {
            return Response(sourceLanguage: source, targetLanguage: target, sourceText: string, targetText: string)
        }
        try await ready(source, target)
        try checkCancelled()
        guard let translate = _TranslationHost.translate else { throw TranslationError.unsupportedLanguagePairing }
        let (text, error): (String?, String?) = await withCheckedContinuation { continuation in
            translate(_code(source), _code(target), string) { continuation.resume(returning: ($0, $1)) }
        }
        try checkCancelled()
        guard let text else { throw Self.error(error) }
        return Response(sourceLanguage: source, targetLanguage: target, sourceText: string, targetText: text)
    }

    /// Translates `string` for a request's client identifier.
    func translate(_ request: Request) async throws -> Response {
        var response = try await translate(request.sourceText)
        response.clientIdentifier = request.clientIdentifier
        return response
    }

    /// Translates each request, all before returning.
    public func translations(from batch: [Request]) async throws -> [Response] {
        var responses: [Response] = []
        for request in batch { responses.append(try await translate(request)) }
        return responses
    }

    /// Translates each request, handing out each response as it comes.
    public func translate(batch: [Request]) -> BatchResponse {
        let stream = AsyncThrowingStream<Response, any Error> { continuation in
            let task = Task {
                do {
                    for request in batch { continuation.yield(try await self.translate(request)) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        return BatchResponse(stream: stream)
    }

    /// Stops the session: translations not finished, and later ones, throw `CancellationError`.
    public func cancel() {
        lock.lock(); cancelled = true; lock.unlock()
    }

    private func checkCancelled() throws {
        lock.lock(); let cancelled = cancelled; lock.unlock()
        if cancelled { throw CancellationError() }
    }

    /// Makes sure the pair translates: on the device, or downloaded when the session may.
    private func ready(_ source: Locale.Language, _ target: Locale.Language) async throws {
        switch await _availability(source, target) {
        case .available:
            return
        case .unavailable:
            throw TranslationError.unsupportedLanguagePairing
        case .downloadable:
            guard canRequestDownloads else { throw TranslationError.notInstalled }
            guard let prepare = _TranslationHost.prepare else { throw TranslationError.unsupportedLanguagePairing }
            let error: String? = await withCheckedContinuation { continuation in
                prepare(_code(source), _code(target)) { continuation.resume(returning: $0) }
            }
            if let error { throw Self.error(error) }
        }
    }

    static func error(_ name: String?) -> TranslationError {
        switch name {
        case "NotSupportedError": .unsupportedLanguagePairing
        case "NotAllowedError": .notInstalled
        default: .internalError
        }
    }
}

// MARK: - The browser

/// The languages Chrome's translator knows (its BCP 47 codes).
let _translatorLanguages = ["ar", "bg", "bn", "cs", "da", "de", "el", "en", "es", "fi", "fr", "hi", "hr", "hu", "id", "it",
                            "he", "ja", "kn", "ko", "lt", "mr", "nl", "no", "pl", "pt", "ro", "ru", "sk", "sl", "sv", "ta",
                            "te", "th", "tr", "uk", "vi", "zh", "zh-Hant"]

/// The browser's code for a language: its language code, with the script where the translator
/// tells scripts apart (Chinese).
func _code(_ language: Locale.Language) -> String {
    let code = language.languageCode?.identifier ?? language.minimalIdentifier
    if code == "zh", language.script?.identifier == "Hant" { return "zh-Hant" }
    return code
}

/// The person's preferred language.
func _preferredLanguage() -> Locale.Language {
    Locale.Language(identifier: Locale.preferredLanguages.first ?? "en")
}

func _availability(_ source: Locale.Language, _ target: Locale.Language) async -> _TranslationHost.Availability {
    guard let availability = _TranslationHost.availability else { return .unavailable }
    return await withCheckedContinuation { continuation in
        availability(_code(source), _code(target)) { continuation.resume(returning: $0) }
    }
}

func _detect(_ text: String) async -> Locale.Language? {
    guard let detect = _TranslationHost.detect else { return nil }
    let code: String? = await withCheckedContinuation { continuation in
        detect(text) { continuation.resume(returning: $0) }
    }
    return code.map { Locale.Language(identifier: $0) }
}
