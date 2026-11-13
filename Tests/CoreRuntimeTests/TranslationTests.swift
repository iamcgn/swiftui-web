// Translation over a stand-in for the browser's translator: which pairs are installed, can be
// downloaded or are unsupported, the sessions that may and may not download, language detection,
// batches, cancelling, and the translationTask and translationPresentation modifiers.
#if !os(WASI)
import Foundation
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless
import Translation
import TranslationHost

/// Plays the browser's translator: English to French is on the device, English to German and
/// Japanese to the person's language download, nothing translates to Klingon. A translation is
/// the target's code and the text; Japanese text is detected, other text is not.
@MainActor
private enum StandInTranslator {
    nonisolated(unsafe) static var installed: Set<String> = []
    nonisolated(unsafe) static var downloads: [String] = []
    nonisolated(unsafe) static var translations: [String] = []

    static func install() {
        installed = ["en>fr"]
        downloads = []
        translations = []
        _TranslationHost.availability = { source, target, done in
            let pair = "\(source)>\(target)"
            if target == "tlh" || source == "tlh" { done(.unavailable) }
            else if StandInTranslator.installed.contains(pair) { done(.available) }
            else { done(.downloadable) }
        }
        _TranslationHost.prepare = { source, target, done in
            let pair = "\(source)>\(target)"
            StandInTranslator.downloads.append(pair)
            StandInTranslator.installed.insert(pair)
            done(nil)
        }
        _TranslationHost.translate = { source, target, text, done in
            guard StandInTranslator.installed.contains("\(source)>\(target)") else { done(nil, "NotAllowedError"); return }
            StandInTranslator.translations.append(text)
            done("\(target): \(text)", nil)
        }
        _TranslationHost.detect = { text, done in
            done(text.unicodeScalars.contains { (0x3040...0x30FF).contains($0.value) } ? "ja" : nil)
        }
    }
}

private func code(_ language: Locale.Language?) -> String? { language?.languageCode?.identifier }

/// The person's preferred language's code, as the session reads it.
private var preferred: String {
    Locale.Language(identifier: Locale.preferredLanguages.first ?? "en").languageCode?.identifier ?? "en"
}

@Suite(.serialized) @MainActor
struct TranslationTests {
    init() {
        _TranslationHost.availability = nil
        _TranslationHost.prepare = nil
        _TranslationHost.translate = nil
        _TranslationHost.detect = nil
    }

    /// Yields until `condition` holds (a loaded machine lands task hops late), at most ~2 s.
    private func settle(until condition: @escaping @MainActor () -> Bool) async {
        for _ in 0..<400 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    @Test func aBrowserWithoutATranslatorSupportsNothing() async {
        let english = Locale.Language(identifier: "en"), french = Locale.Language(identifier: "fr")
        #expect(await LanguageAvailability().status(from: english, to: french) == .unsupported)
        #expect(await LanguageAvailability().supportedLanguages.isEmpty)
        await #expect(throws: TranslationError.unableToIdentifyLanguage) {
            _ = try await LanguageAvailability().status(for: "Hello", to: french)
        }
        let session = TranslationSession(installedSource: english, target: french)
        #expect(await !session.isReady)
        await #expect(throws: TranslationError.unsupportedLanguagePairing) { _ = try await session.translate("Hello") }
    }

    @Test func availabilityReadsInstalledSupportedAndUnsupported() async throws {
        StandInTranslator.install()
        let availability = LanguageAvailability()
        let english = Locale.Language(identifier: "en")
        #expect(await availability.status(from: english, to: Locale.Language(identifier: "fr")) == .installed)
        #expect(await availability.status(from: english, to: Locale.Language(identifier: "de")) == .supported)
        #expect(await availability.status(from: english, to: Locale.Language(identifier: "tlh")) == .unsupported)
        #expect(try await availability.status(for: "こんにちは", to: Locale.Language(identifier: "tlh")) == .unsupported)
        let languages = await availability.supportedLanguages
        #expect(languages.contains { code($0) == "fr" } && languages.contains { code($0) == "ja" })
    }

    @Test func anInstalledSourceSessionUsesOnlyModelsOnTheDevice() async throws {
        StandInTranslator.install()
        let english = Locale.Language(identifier: "en")
        let french = TranslationSession(installedSource: english, target: Locale.Language(identifier: "fr"))
        #expect(!french.canRequestDownloads)
        #expect(await french.isReady)
        let response = try await french.translate("Good morning")
        #expect(response.targetText == "fr: Good morning" && response.sourceText == "Good morning")
        #expect(code(response.sourceLanguage) == "en" && code(response.targetLanguage) == "fr")
        // German is not on the device, and this session may not download it.
        let german = TranslationSession(installedSource: english, target: Locale.Language(identifier: "de"))
        #expect(await !german.isReady)
        await #expect(throws: TranslationError.notInstalled) { _ = try await german.translate("Good morning") }
        await #expect(throws: TranslationError.notInstalled) { try await german.prepareTranslation() }
        let klingon = TranslationSession(installedSource: english, target: Locale.Language(identifier: "tlh"))
        await #expect(throws: TranslationError.unsupportedLanguagePairing) { _ = try await klingon.translate("Hello") }
        #expect(StandInTranslator.downloads.isEmpty)
    }

    @Test func aTaskSessionDownloadsTheModelItNeeds() async throws {
        StandInTranslator.install()
        var configuration = TranslationSession.Configuration(source: Locale.Language(identifier: "en"), target: Locale.Language(identifier: "de"))
        let log = SessionLog()
        let runtime = Runtime()
        runtime.textEngine = MetricsTextEngine()
        let model = ConfigurationModel(configuration)
        runtime.mount(Translating(model: model) { log.sessions.append($0) })
        runtime.layout(in: CGSize(width: 320, height: 480))
        await settle(until: { log.sessions.count == 1 })
        let session = try #require(log.sessions.first)
        #expect(session.canRequestDownloads)
        #expect(await !session.isReady)
        try await session.prepareTranslation()
        #expect(StandInTranslator.downloads == ["en>de"])
        #expect(await session.isReady)
        #expect(try await session.translate("Thank you").targetText == "de: Thank you")
        // Invalidating the configuration runs the task again with a new session.
        configuration.invalidate()
        #expect(configuration.version == 1)
        model.configuration = configuration
        runtime.layout(in: CGSize(width: 320, height: 480))
        await settle(until: { log.sessions.count == 2 })
        #expect(log.sessions.count == 2 && log.sessions[1] !== session)
        // No configuration, no task.
        model.configuration = nil
        runtime.layout(in: CGSize(width: 320, height: 480))
        for _ in 0..<20 { await Task.yield() }
        #expect(log.sessions.count == 2)
    }

    @Test func aMissingSourceIsDetectedAndAMissingTargetIsThePreferredLanguage() async throws {
        StandInTranslator.install()
        let session = TranslationSession(installedSource: Locale.Language(identifier: "fr"))
        #expect(session.targetLanguage == nil)
        StandInTranslator.installed.insert("fr>\(preferred)")
        let response = try await session.translate("Bonjour")
        #expect(code(response.targetLanguage) == preferred)
        await #expect(throws: TranslationError.unableToIdentifyLanguage) {
            _ = try await LanguageAvailability().status(for: "Bonjour", to: nil)
        }
    }

    @Test func textInTheTargetLanguageComesBackAndEmptyTextThrows() async throws {
        StandInTranslator.install()
        let session = TranslationSession(installedSource: Locale.Language(identifier: "en"), target: Locale.Language(identifier: "en-GB"))
        let response = try await session.translate("Colour")
        #expect(response.targetText == "Colour")
        #expect(StandInTranslator.translations.isEmpty)
        await #expect(throws: TranslationError.nothingToTranslate) { _ = try await session.translate("  \n") }
    }

    @Test func batchesAnswerInOrderWithTheirIdentifiers() async throws {
        StandInTranslator.install()
        let session = TranslationSession(installedSource: Locale.Language(identifier: "en"), target: Locale.Language(identifier: "fr"))
        let requests = [TranslationSession.Request(sourceText: "One", clientIdentifier: "1"),
                        TranslationSession.Request(sourceText: "Two", clientIdentifier: "2"),
                        TranslationSession.Request(sourceText: "Three")]
        let all = try await session.translations(from: requests)
        #expect(all.map(\.targetText) == ["fr: One", "fr: Two", "fr: Three"])
        #expect(all.map(\.clientIdentifier) == ["1", "2", nil])
        var streamed: [String] = []
        for try await response in session.translate(batch: requests) { streamed.append(response.clientIdentifier ?? "-") }
        #expect(streamed == ["1", "2", "-"])
    }

    @Test func aCancelledSessionThrows() async throws {
        StandInTranslator.install()
        let session = TranslationSession(installedSource: Locale.Language(identifier: "en"), target: Locale.Language(identifier: "fr"))
        _ = try await session.translate("Before")
        session.cancel()
        await #expect(throws: CancellationError.self) { _ = try await session.translate("After") }
        #expect(StandInTranslator.translations == ["Before"])
    }

    @Test func aPresentationShowsTheTranslationAndReplaces() async throws {
        StandInTranslator.install()
        StandInTranslator.installed.insert("ja>\(preferred)")
        let model = PresentationModel()
        let runtime = Runtime()
        runtime.textEngine = MetricsTextEngine()
        runtime.mount(Presenting(model: model))
        let size = CGSize(width: 400, height: 600)
        runtime.layout(in: size)
        #expect(!runtime.hasPresentations)
        model.isPresented = true
        runtime.layout(in: size)
        #expect(runtime.hasPresentations)
        let translated = "\(preferred): こんにちは"
        await settle(until: {
            runtime.layout(in: size)
            return runtime.semanticsTree().contains { $0.label == translated }
        })
        let labels = runtime.semanticsTree().map(\.label)
        #expect(labels.contains("こんにちは") && labels.contains(translated))
        #expect(labels.contains("Copy Translation"))
        let replace = try #require(runtime.semanticsTree().first { $0.label == "Replace with Translation" })
        runtime.activate(semanticsIdentifier: replace.identifier)
        #expect(model.text == translated)
        #expect(!model.isPresented)
    }
}

@MainActor
private final class SessionLog {
    var sessions: [TranslationSession] = []
}

@Observable
private final class ConfigurationModel: @unchecked Sendable {
    var configuration: TranslationSession.Configuration?
    init(_ configuration: TranslationSession.Configuration?) { self.configuration = configuration }
}

private struct Translating: View {
    let model: ConfigurationModel
    let action: @MainActor @Sendable (TranslationSession) -> Void
    var body: some View {
        Text("Translating")
            .translationTask(model.configuration) { session in action(session) }
    }
}

@Observable
private final class PresentationModel: @unchecked Sendable {
    var isPresented = false
    var text = "こんにちは"
}

private struct Presenting: View {
    let model: PresentationModel
    var body: some View {
        Text(model.text)
            .translationPresentation(isPresented: Binding(get: { model.isPresented }, set: { model.isPresented = $0 }),
                                     text: model.text) { translation in model.text = translation }
    }
}
#endif
