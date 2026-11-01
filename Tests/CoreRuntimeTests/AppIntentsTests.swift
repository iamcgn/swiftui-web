// AppIntents (sw-frameworks): an intent's parameters hold what the app set, else their default,
// else nil when optional; running it returns its result; entities and enumerations show
// themselves; a summary and a shortcut phrase keep their text; asking the user for a value
// throws, since no one can be asked on the web; and a button or toggle made with an intent runs
// the intent's perform() when pressed.
import Testing
import Foundation
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless
import AppIntents
#if os(Linux)
import WebFoundation   // LocalizedStringResource
#endif

#if !os(WASI)
@MainActor private final class IntentLog {
    static let shared = IntentLog()
    var entries: [String] = []
    func add(_ entry: String) { entries.append(entry) }
}

private enum Mood: String, AppEnum {
    case calm, busy

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Mood" }
    static var caseDisplayRepresentations: [Mood: DisplayRepresentation] {
        [.calm: DisplayRepresentation(title: "Calm", image: .init(systemName: "leaf")), .busy: "Busy"]
    }
}

private struct Note: AppEntity {
    let id: String
    @Property(title: "Text") var text: String

    init(id: String, text: String) {
        self.id = id
        self.text = text
    }

    static let all = [Note(id: "a", text: "Milk"), Note(id: "b", text: "Bread")]
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Note" }
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: LocalizedStringResource(stringLiteral: text), subtitle: LocalizedStringResource(stringLiteral: "Note " + id))
    }
    static var defaultQuery: NoteQuery { NoteQuery() }
}

private struct NoteQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [Note] { Note.all.filter { identifiers.contains($0.id) } }
    func entities(matching string: String) async throws -> [Note] { Note.all.filter { $0.text.contains(string) } }
    func suggestedEntities() async throws -> [Note] { Note.all }
}

private struct LogIntent: AppIntent {
    static var title: LocalizedStringResource { "Log a mood" }
    static var description: IntentDescription? { IntentDescription("Writes a mood down.", categoryName: "Journal") }

    @Parameter(title: "Mood", default: .calm) var mood: Mood
    @Parameter(title: "Note") var note: Note?
    @Parameter(title: "Times", default: 1, controlStyle: .stepper, inclusiveRange: (1, 5)) var times: Int
    @Parameter(title: "Name", requestValueDialog: "Whose mood?") var name: String

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$mood) for \(\.$name)") {
            \.$times
            \.$note
        }
    }

    init() {}
    init(mood: Mood, name: String) {
        self.mood = mood
        self.name = name
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let line = "\(name) \(mood.rawValue) x\(times) \(note?.text ?? "-")"
        await IntentLog.shared.add(line)
        return .result(value: line, dialog: "Logged \(name)")
    }
}

private struct PingIntent: AppIntent {
    static var title: LocalizedStringResource { "Ping" }
    @Parameter(title: "Label", default: "ping") var label: String
    init() {}
    func perform() async throws -> some IntentResult {
        await IntentLog.shared.add(label)
        return .result()
    }
}

private struct Shortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: LogIntent(), phrases: ["Log my mood in \(.applicationName)", "\(.applicationName) mood"],
                    shortTitle: "Log mood", systemImageName: "face.smiling")
        AppShortcut(intent: PingIntent(), phrases: ["Ping \(.applicationName)"])
    }
}

@Suite(.serialized) @MainActor struct AppIntentsTests {
    private func render<V: View>(_ view: V) -> Runtime {
        let runtime = Runtime()
        runtime.textEngine = MetricsTextEngine()
        runtime.mount(view)
        runtime.layout(in: CGSize(width: 320, height: 480))
        _ = runtime.render(scale: 2)
        return runtime
    }

    /// Lets the tasks a press started run.
    private func settle(until count: Int) async {
        for _ in 0..<200 where IntentLog.shared.entries.count < count { await Task.yield() }
    }

    @Test func parametersHoldWhatTheAppSetElseTheirDefault() async throws {
        let intent = LogIntent(mood: .busy, name: "Sam")
        #expect(intent.mood == .busy)
        #expect(intent.times == 1)
        #expect(intent.note == nil)
        #expect(intent.$note.isOptional)
        #expect(!intent.$name.isOptional)
        #expect(intent.$mood.title.key == "Mood")
        #expect(intent.$times.valueState == .set(1))
        #expect(LogIntent().$name.valueState == .unset)
        #expect(LogIntent().mood == .calm)

        intent.note = Note.all[1]
        intent.times = 3
        let result = try await intent.perform()
        #expect(result.value == "Sam busy x3 Bread")
        #expect(try await intent() == "Sam busy x3 Bread")
        #expect(LogIntent.title.key == "Log a mood")
        #expect(LogIntent.description?.categoryName?.key == "Journal")
        #expect(LogIntent.persistentIdentifier == "LogIntent")
        #expect(!LogIntent.openAppWhenRun)
    }

    @Test func askingForAValueThrows() async {
        let intent = LogIntent()
        let error = intent.$name.needsValueError()
        #expect(error.description == "The intent needs a value for 'Name': Whose mood?")
        await #expect(throws: AppIntentError.self) { _ = try await intent.$name.requestValue() }
        await #expect(throws: AppIntentError.self) { _ = try await intent.$mood.requestDisambiguation(among: [.calm, .busy]) }
        await #expect(throws: AppIntentError.self) { try await intent.requestConfirmation() }
    }

    @Test func entitiesAndEnumsShowThemselves() async throws {
        #expect(Mood.calm.localizedStringResource.key == "Calm")
        #expect(Mood.busy.localizedStringResource.key == "Busy")
        #expect(Mood.caseDisplayRepresentations[.calm]?.image == DisplayRepresentation.Image(systemName: "leaf"))
        #expect(Mood.typeDisplayRepresentation.name.key == "Mood")

        let note = Note.all[0]
        #expect(note.text == "Milk")
        #expect(note.$text.title.key == "Text")
        #expect(note.localizedStringResource.key == "Milk")
        #expect(note.displayRepresentation.subtitle?.key == "Note a")
        #expect(note.id.entityIdentifierString == "a")

        let query = Note.defaultQuery
        #expect(try await query.entities(for: ["b"]).map(\.text) == ["Bread"])
        #expect(try await query.entities(matching: "Mi").map(\.id) == ["a"])
        #expect(try await query.results().count == 2)
        #expect(String.entityIdentifier(for: "x") == "x")
        #expect(Int.entityIdentifier(for: "42") == 42)
    }

    @Test func summaryAndPhrasesKeepTheirText() {
        let summary = LogIntent.parameterSummary
        #expect(summary.text.hasPrefix("Log ${"))
        #expect(summary.text.contains(" for ${"))
        #expect(summary.additionalParameters.count == 2)

        let shortcuts = Shortcuts.appShortcuts
        #expect(shortcuts.count == 2)
        #expect(shortcuts[0].intentIdentifier == "LogIntent")
        #expect(shortcuts[0].phrases == ["Log my mood in ${applicationName}", "${applicationName} mood"])
        #expect(shortcuts[0].shortTitle?.key == "Log mood")
        #expect(shortcuts[1].phrases == ["Ping ${applicationName}"])
        #expect(Shortcuts.shortcutTileColor == .navy)

        let dialog: IntentDialog = "Hi \(3)"
        #expect(dialog.full.key == "Hi 3")
        #expect(IntentCollectionSize(exactly: 2) == IntentCollectionSize(min: 2, max: 2))
    }

    @Test func buttonWithAnIntentRunsIt() async {
        IntentLog.shared.entries = []
        let runtime = render(VStack {
            Button(intent: PingIntent()) { Text("Ping") }
            Button("Log", intent: LogIntent(mood: .busy, name: "Ada"))
            SiriTipView(intent: PingIntent())
            ShortcutsLink()
        })
        let tree = runtime.semanticsTree()
        #expect(tree.map(\.label) == ["Ping", "Log"])
        runtime.activate(semanticsIdentifier: tree[0].identifier)
        await settle(until: 1)
        #expect(IntentLog.shared.entries == ["ping"])
        runtime.activate(semanticsIdentifier: tree[1].identifier)
        await settle(until: 2)
        #expect(IntentLog.shared.entries == ["ping", "Ada busy x1 -"])
    }

    @Test func toggleWithAnIntentRunsItWhenFlipped() async {
        IntentLog.shared.entries = []
        let runtime = render(Toggle("Ping", isOn: false, intent: PingIntent()))
        let toggle = runtime.semanticsTree().first { $0.label == "Ping" }
        #expect(toggle != nil)
        if let toggle { runtime.activate(semanticsIdentifier: toggle.identifier) }
        await settle(until: 1)
        #expect(IntentLog.shared.entries == ["ping"])
    }
}
#endif
