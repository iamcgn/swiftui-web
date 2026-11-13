// The browser's on-device translator as the Translation framework reads it: the hook
// SwiftUIWebCanvas installs (TranslationHost.swift there, over Chrome's `Translator` and
// `LanguageDetector`) and Translation uses. A module of its own, depending on nothing, so
// installing the hook links only this into an app that never translates (decision 0006).

public enum _TranslationHost {
    /// Whether the browser can translate between two languages (BCP 47 codes, "en", "zh-Hant").
    public enum Availability: Sendable, Equatable {
        /// The browser has no translator for the pair.
        case unavailable
        /// The browser can translate once it downloads the pair's model.
        case downloadable
        /// The pair's model is on the device.
        case available
    }

    /// Asks whether the browser translates `source` to `target`.
    nonisolated(unsafe) public static var availability: ((_ source: String, _ target: String,
                                                         _ done: @escaping (Availability) -> Void) -> Void)?
    /// Readies the pair's translator, downloading its model; `done` gets nil or the error's name.
    nonisolated(unsafe) public static var prepare: ((_ source: String, _ target: String,
                                                    _ done: @escaping (_ error: String?) -> Void) -> Void)?
    /// Translates `text`; `done` gets the translation, or nil and the error's name.
    nonisolated(unsafe) public static var translate: ((_ source: String, _ target: String, _ text: String,
                                                      _ done: @escaping (_ translation: String?, _ error: String?) -> Void) -> Void)?
    /// The language `text` is in, or nil when the browser cannot tell.
    nonisolated(unsafe) public static var detect: ((_ text: String, _ done: @escaping (String?) -> Void) -> Void)?
}
