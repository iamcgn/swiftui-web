// fileImporter and fileExporter through the runtime's file handlers, onDrop with item providers
// and drop delegates, onScrollVisibilityChange, and the iOS 18-26 presentation and bar modifiers
// apps put on their views (IceCubes, Dime, IcySky, CriticalMaps, OscarWeather).
import Foundation
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless

#if !os(WASI)
@Observable
private final class DialogModel {
    var importing = false
    var exporting = false
    var imported: [URL] = []
    var failures = 0
    var cancellations = 0
    var exported: [URL] = []
}

private struct Importer: View {
    let model: DialogModel
    var multiple = false
    var body: some View {
        let model = self.model
        let completion: (Result<[URL], any Error>) -> Void = { result in
            switch result {
            case .success(let urls): model.imported += urls
            case .failure: model.failures += 1
            }
        }
        return Color.clear.frame(width: 10, height: 10)
            .fileImporter(isPresented: Binding(get: { model.importing }, set: { model.importing = $0 }),
                          allowedContentTypes: [.commaSeparatedText], allowsMultipleSelection: multiple,
                          onCompletion: completion, onCancellation: { model.cancellations += 1 })
    }
}

private struct SingleImporter: View {
    let model: DialogModel
    var body: some View {
        Color.clear.frame(width: 10, height: 10)
            .fileImporter(isPresented: Binding(get: { model.importing }, set: { model.importing = $0 }),
                          allowedContentTypes: [.png, .jpeg]) { result in
                if case .success(let url) = result { model.imported.append(url) } else { model.failures += 1 }
            }
    }
}

private struct NotesDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: FileDocumentReadConfiguration) throws { text = "" }
    func fileWrapper(configuration: FileDocumentWriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

private struct Exporter: View {
    let model: DialogModel
    var body: some View {
        VStack {
            Color.clear.frame(width: 10, height: 10)
                .fileExporter(isPresented: Binding(get: { model.exporting }, set: { model.exporting = $0 }),
                              document: NotesDocument(text: "Buy milk"), contentType: .plainText, defaultFilename: "Notes") { result in
                    if case .success(let url) = result { model.exported.append(url) } else { model.failures += 1 }
                }
        }
    }
}

private struct ItemExporter: View {
    let model: DialogModel
    var body: some View {
        Color.clear.frame(width: 10, height: 10)
            .fileExporter(isPresented: Binding(get: { model.exporting }, set: { model.exporting = $0 }),
                          item: "a,b\n1,2", contentTypes: [.plainText], defaultFilename: "table.csv",
                          onCompletion: { result in
                              if case .success(let url) = result { model.exported.append(url) } else { model.failures += 1 }
                          })
    }
}

@Suite @MainActor struct FileDialogsTests {
    private func run(_ runtime: Runtime) {
        for _ in 0..<3 { runtime.layout(in: CGSize(width: 100, height: 100)) }
    }

    @Test func importerOpensThePanelAndResetsTheBinding() throws {
        let model = DialogModel()
        let runtime = Runtime()
        var requests: [HostFileOpenRequest] = []
        runtime.fileOpenHandler = { request, completion in
            requests.append(request)
            completion([HostFile(data: Data("a,b\n1,2".utf8), name: "table.csv", mimeType: "text/csv"),
                        HostFile(data: Data("c".utf8), name: "more.csv", mimeType: "text/csv")])
        }
        runtime.mount(Importer(model: model, multiple: true))
        run(runtime)
        #expect(requests.isEmpty)
        model.importing = true
        run(runtime)
        #expect(requests.count == 1 && requests[0].extensions == ["csv"] && requests[0].allowsMultiple && !requests[0].imagesOnly)
        #expect(!model.importing)
        #expect(model.imported.count == 2)
        #expect(try Data(contentsOf: model.imported[0]) == Data("a,b\n1,2".utf8))
        #expect(model.imported[0].lastPathComponent == "table.csv")
    }

    @Test func singleImporterTakesTheFirstFileAndAsksForImages() {
        let model = DialogModel()
        let runtime = Runtime()
        var request: HostFileOpenRequest?
        runtime.fileOpenHandler = { asked, completion in
            request = asked
            completion([HostFile(data: Data([1, 2]), name: "a.png", mimeType: "image/png"),
                        HostFile(data: Data([3]), name: "b.png", mimeType: "image/png")])
        }
        runtime.mount(SingleImporter(model: model))
        run(runtime)
        model.importing = true
        run(runtime)
        #expect(request?.imagesOnly == true && request?.allowsMultiple == false)
        #expect(model.imported.map(\.lastPathComponent) == ["a.png"])
    }

    @Test func importerCancelsAndFailsWithoutAPanel() {
        let model = DialogModel()
        let runtime = Runtime()
        runtime.fileOpenHandler = { _, completion in completion([]) }
        runtime.mount(Importer(model: model))
        run(runtime)
        model.importing = true
        run(runtime)
        #expect(model.cancellations == 1 && model.imported.isEmpty && !model.importing)

        let other = DialogModel()
        let bare = Runtime()
        bare.mount(Importer(model: other))
        run(bare)
        other.importing = true
        run(bare)
        #expect(other.failures == 1 && !other.importing)
    }

    @Test func exporterSavesTheDocument() throws {
        let model = DialogModel()
        let runtime = Runtime()
        var saved: [(Data, String, UTType)] = []
        runtime.documentSaveHandler = { data, name, type, _ in saved.append((data, name, type)); return nil }
        runtime.mount(Exporter(model: model))
        run(runtime)
        #expect(saved.isEmpty)
        model.exporting = true
        run(runtime)
        #expect(!model.exporting)
        #expect(saved.count == 1 && saved[0].0 == Data("Buy milk".utf8) && saved[0].1 == "Notes.txt" && saved[0].2 == .plainText)
        // The browser keeps no file: the completion gets a readable copy.
        #expect(model.exported.count == 1)
        #expect(try Data(contentsOf: model.exported[0]) == Data("Buy milk".utf8))
    }

    @Test func exporterSavesATransferableItem() {
        let model = DialogModel()
        let runtime = Runtime()
        var names: [String] = []
        runtime.documentSaveHandler = { _, name, _, _ in names.append(name); return URL(fileURLWithPath: "/tmp/" + name) }
        runtime.mount(ItemExporter(model: model))
        run(runtime)
        model.exporting = true
        run(runtime)
        #expect(names == ["table.csv"])
        #expect(model.exported == [URL(fileURLWithPath: "/tmp/table.csv")])
    }
}

// MARK: - onDrop

private final class DropLog {
    var entered = 0
    var exited = 0
    var updated = 0
    var performed: [CGPoint] = []
    var providers: [[NSItemProvider]] = []
    var accept = true
    var proposal: DropOperation = .move
}

private struct Delegate: DropDelegate {
    let log: DropLog
    func validateDrop(info: DropInfo) -> Bool { log.accept && info.hasItemsConforming(to: [.text]) }
    func dropEntered(info: DropInfo) { log.entered += 1 }
    func dropUpdated(info: DropInfo) -> DropProposal? { log.updated += 1; return DropProposal(operation: log.proposal) }
    func dropExited(info: DropInfo) { log.exited += 1 }
    func performDrop(info: DropInfo) -> Bool {
        log.performed.append(info.location)
        log.providers.append(info.itemProviders(for: [.text]))
        return true
    }
}

@Observable
private final class TargetModel { var targeted = false }

private struct DropBoard: View {
    let log: DropLog
    let model: TargetModel
    var body: some View {
        HStack(spacing: 40) {
            Color.red.frame(width: 40, height: 40).draggable("hello")
            Color.blue.frame(width: 80, height: 80)
                .onDrop(of: [.text], delegate: Delegate(log: log))
            Color.green.frame(width: 80, height: 80)
                .onDrop(of: [.plainText], isTargeted: Binding(get: { model.targeted }, set: { model.targeted = $0 })) { providers in
                    log.providers.append(providers)
                    return true
                }
        }
    }
}

@Suite @MainActor struct OnDropTests {
    private func board(_ log: DropLog, _ model: TargetModel = TargetModel()) -> Runtime {
        let runtime = Runtime()
        runtime.mount(DropBoard(log: log, model: model))
        runtime.layout(in: CGSize(width: 400, height: 200))
        return runtime
    }

    @Test func delegateFollowsTheDragAndPerforms() {
        let log = DropLog()
        let r = board(log)
        // The red source is at x 60-100, the delegate's target at 140-220 (y 60-140), the
        // action's at 260-340.
        r.pointerDown(at: CGPoint(x: 70, y: 100))
        r.pointerMoved(to: CGPoint(x: 80, y: 100))
        r.pointerMoved(to: CGPoint(x: 180, y: 100))
        r.layout(in: CGSize(width: 400, height: 200))
        #expect(log.entered == 1 && log.updated >= 1)
        r.pointerMoved(to: CGPoint(x: 190, y: 110))
        r.pointerUp(at: CGPoint(x: 190, y: 110))
        #expect(log.performed == [CGPoint(x: 50, y: 50)])
        #expect(log.exited == 1)
        let providers = log.providers.first ?? []
        #expect(providers.count == 1)
        #expect(providers.first?.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) == true)
        #if !canImport(Darwin)
        var text: String?
        providers.first?.loadDataRepresentation(for: .text) { data, _ in text = data.map { String(decoding: $0, as: UTF8.self) } }
        #expect(text == "hello")
        var loaded: String?
        providers.first?.loadTransferable(type: String.self) { if case .success(let value) = $0 { loaded = value } }
        #expect(loaded == "hello")
        #endif
    }

    @Test func refusedValidationIsNotATarget() {
        let log = DropLog()
        log.accept = false
        let r = board(log)
        r.pointerDown(at: CGPoint(x: 70, y: 100))
        r.pointerMoved(to: CGPoint(x: 80, y: 100))
        r.pointerMoved(to: CGPoint(x: 180, y: 100))
        r.pointerUp(at: CGPoint(x: 180, y: 100))
        #expect(log.entered == 0 && log.performed.isEmpty)
    }

    @Test func aForbiddenProposalIsNotPerformed() {
        let log = DropLog()
        log.proposal = .forbidden
        let r = board(log)
        r.pointerDown(at: CGPoint(x: 70, y: 100))
        r.pointerMoved(to: CGPoint(x: 80, y: 100))
        r.pointerMoved(to: CGPoint(x: 180, y: 100))
        r.pointerMoved(to: CGPoint(x: 190, y: 110))
        r.pointerUp(at: CGPoint(x: 190, y: 110))
        #expect(log.updated >= 1 && log.performed.isEmpty)
    }

    @Test func actionGetsProvidersAndTheBindingFollows() {
        let log = DropLog()
        let model = TargetModel()
        let r = board(log, model)
        r.pointerDown(at: CGPoint(x: 70, y: 100))
        r.pointerMoved(to: CGPoint(x: 80, y: 100))
        r.pointerMoved(to: CGPoint(x: 300, y: 100))
        r.layout(in: CGSize(width: 400, height: 200))
        #expect(model.targeted)
        r.pointerUp(at: CGPoint(x: 300, y: 100))
        #expect(!model.targeted)
        #expect(log.providers.count == 1 && log.providers[0].count == 1)
    }

    @Test func dropsFromOutsideCarryAProviderPerItem() {
        let log = DropLog()
        let r = board(log)
        #expect(r.externalDrop(items: [ExternalDragItem(type: "text/plain", text: "one"), ExternalDragItem(type: "image/png", data: Data([1]))],
                               at: CGPoint(x: 300, y: 100)))
        // Only the text item conforms to plain text.
        #expect(log.providers.count == 1 && log.providers[0].count == 1)
        #if !canImport(Darwin)
        var text: String?
        log.providers[0][0].loadDataRepresentation(forTypeIdentifier: UTType.plainText.identifier) { data, _ in
            text = data.map { String(decoding: $0, as: UTF8.self) }
        }
        #expect(text == "one")
        #endif
    }
}

// MARK: - Scroll visibility and the presentation modifiers

private final class VisibilityLog { var events: [String] = [] }

private struct VisibilityRows: View {
    let log: VisibilityLog
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(0..<30, id: \.self) { index in
                    Color.blue.frame(width: 100, height: 20)
                        .onScrollVisibilityChange(threshold: 0.5) { visible in
                            if index == 0 || index == 20 { log.events.append("\(index) \(visible)") }
                        }
                }
            }
        }
    }
}

// Deprecated API in a deprecated context: no warnings (the package treats them as errors).
@available(*, deprecated)
private struct Modern: View {
    @Namespace private var namespace
    @State private var text = ""
    var body: some View {
        TabView {
            VStack {
                Color.red.frame(width: 20, height: 20).matchedTransitionSource(id: 1, in: namespace)
                Color.red.frame(width: 20, height: 20)
                    .matchedTransitionSource(id: 2, in: namespace) { $0.background(.black).clipShape(.rect(cornerRadius: 4)) }
                TextField("Email", text: $text).autocapitalization(.none).focusEffectDisabled()
            }
            .navigationTransition(.zoom(sourceID: 1, in: namespace))
            .navigationTransition(.automatic)
            .presentationSizing(.page)
            .presentationSizing(.fitted)
            .presentationSizing(FormPresentationSizing().fitted(horizontal: false, vertical: true).sticky(vertical: true))
            .safeAreaBar(edge: .bottom) { Color.green.frame(height: 30)._probe("bar") }
            .tabItem { Text("One") }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}

@Suite @MainActor struct ScrollVisibilityTests {
    @Test func visibilityFollowsTheScroll() {
        let log = VisibilityLog()
        let runtime = Runtime()
        let size = CGSize(width: 100, height: 200)
        runtime.mount(VisibilityRows(log: log))
        runtime.layout(in: size)
        runtime.layout(in: size)
        // Row 0 shows at appearance; row 20 (at 400) is out of view and reports nothing.
        #expect(log.events == ["0 true"])
        runtime.scrollWheel(by: CGSize(width: 0, height: 300), at: CGPoint(x: 50, y: 100))
        runtime.layout(in: size)
        runtime.layout(in: size)
        #expect(log.events == ["0 true", "0 false", "20 true"])
    }

    @available(*, deprecated)
    @Test func modernModifiersKeepTheView() {
        let runtime = Runtime()
        runtime.mount(Modern())
        runtime.layout(in: CGSize(width: 300, height: 400))
        // The bar sits in the safe area at the bottom of the tab's content, as an inset does.
        let bar = runtime.probeFrames["bar"]
        #expect(bar != nil && bar!.height == 30)
    }
}
#endif
