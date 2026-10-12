// Drag and drop inside the app: `draggable` starts a drag session from a press that moves,
// `dropDestination` receives the payload. Payloads are `Transferable` values carried as they are;
// a destination for another type reads them through the payload's proxy representation.
import WebFoundation

// MARK: - Uniform type identifiers (the subset the representations name)

// `UTType` lives in WebGraphics (Input/UTType.swift) so UIKitWeb's document picker can take
// it too; SwiftUIWebCore re-exports WebGraphics, so apps see it here as before.

// MARK: - Transferable

/// A type that can be dragged, dropped, copied and pasted.
public protocol Transferable {
    associatedtype Representation: TransferRepresentation where Representation.Item == Self
    @TransferRepresentationBuilder<Self> static var transferRepresentation: Representation { get }
}

/// How a transferable value is exported to, and imported from, other forms.
public protocol TransferRepresentation<Item> {
    associatedtype Item
    var _exporters: [_TransferExporter<Item>] { get }
}

/// One way of exporting an item: as a value of another type (proxies), or as data.
public struct _TransferExporter<Item> {
    package let contentType: UTType?
    package let exportedType: Any.Type
    package let export: (Item) -> Any?
    package let importer: ((Any) -> Item?)?
}

/// Exports the item as another transferable value (and imports it back).
public struct ProxyRepresentation<Item, ProxyRepresentation: Transferable>: TransferRepresentation {
    package let exporting: (Item) -> ProxyRepresentation
    package let importing: ((ProxyRepresentation) -> Item)?

    public init(exporting: @escaping (Item) -> ProxyRepresentation) {
        self.exporting = exporting
        self.importing = nil
    }

    public init(exporting: @escaping (Item) -> ProxyRepresentation, importing: @escaping (ProxyRepresentation) -> Item) {
        self.exporting = exporting
        self.importing = importing
    }

    public var _exporters: [_TransferExporter<Item>] {
        let exporting = exporting, importing = importing
        return [_TransferExporter(contentType: nil, exportedType: ProxyRepresentation.self,
                                  export: { exporting($0) },
                                  importer: importing.map { imp in { ($0 as? ProxyRepresentation).map(imp) } })]
    }
}

/// Exports the item as JSON (`_TransferJSONEncoder`, the coder of `TransferJSON.swift`).
public struct CodableRepresentation<Item: Codable>: TransferRepresentation {
    package let contentType: UTType
    public init(contentType: UTType = .json) { self.contentType = contentType }
    public var _exporters: [_TransferExporter<Item>] {
        [_TransferExporter(contentType: contentType, exportedType: Data.self,
                           export: { try? _TransferJSONEncoder().encode($0) },
                           importer: { ($0 as? Data).flatMap { try? _TransferJSONDecoder().decode(Item.self, from: $0) } })]
    }
}

/// Exports the item as data through closures.
public struct DataRepresentation<Item>: TransferRepresentation {
    package let contentType: UTType
    package let exporting: (Item) throws -> Data
    package let importing: ((Data) throws -> Item)?

    public init(contentType: UTType, exporting: @escaping (Item) throws -> Data, importing: @escaping (Data) throws -> Item) {
        self.contentType = contentType
        self.exporting = exporting
        self.importing = importing
    }

    public init(exportedContentType: UTType, exporting: @escaping (Item) throws -> Data) {
        self.contentType = exportedContentType
        self.exporting = exporting
        self.importing = nil
    }

    public var _exporters: [_TransferExporter<Item>] {
        let exporting = exporting, importing = importing
        return [_TransferExporter(contentType: contentType, exportedType: Data.self,
                                  export: { try? exporting($0) },
                                  importer: importing.map { imp in { ($0 as? Data).flatMap { try? imp($0) } } })]
    }
}

/// A file sent by a `FileRepresentation` export.
public struct SentTransferredFile: Sendable {
    public let file: URL
    public let allowAccessingOriginalFile: Bool
    public init(_ file: URL, allowAccessingOriginalFile: Bool = false) {
        self.file = file
        self.allowAccessingOriginalFile = allowAccessingOriginalFile
    }
}

/// A file received by a `FileRepresentation` import: a copy the app may read (`Data(contentsOf:)`;
/// on wasm a `memory:` URL, there being no file system).
public struct ReceivedTransferredFile: Sendable {
    public let file: URL
    public let isOriginalFile: Bool
    public init(_ file: URL, isOriginalFile: Bool = false) {
        self.file = file
        self.isOriginalFile = isOriginalFile
    }
}

/// Exports the item as a file and imports it from one. The closures are synchronous here (Apple's
/// are `async`): a drag's payload must be ready when the host hands it to the system.
public struct FileRepresentation<Item>: TransferRepresentation {
    package let contentType: UTType
    package let exporting: ((Item) throws -> SentTransferredFile)?
    package let importing: ((ReceivedTransferredFile) throws -> Item)?
    /// Whether the file is sent as its own bytes (the browser's `DownloadURL`, a pasteboard
    /// file promise) or by its URL alone.
    package let shouldAllowToOpenInPlace: Bool

    public init(contentType: UTType, shouldAllowToOpenInPlace: Bool = false,
                exporting: @escaping (Item) throws -> SentTransferredFile, importing: @escaping (ReceivedTransferredFile) throws -> Item) {
        self.contentType = contentType
        self.shouldAllowToOpenInPlace = shouldAllowToOpenInPlace
        self.exporting = exporting
        self.importing = importing
    }

    public init(exportedContentType: UTType, shouldAllowToOpenInPlace: Bool = false, exporting: @escaping (Item) throws -> SentTransferredFile) {
        contentType = exportedContentType
        self.shouldAllowToOpenInPlace = shouldAllowToOpenInPlace
        self.exporting = exporting
        importing = nil
    }

    public init(importedContentType: UTType, shouldAllowToOpenInPlace: Bool = false, importing: @escaping (ReceivedTransferredFile) throws -> Item) {
        contentType = importedContentType
        self.shouldAllowToOpenInPlace = shouldAllowToOpenInPlace
        exporting = nil
        self.importing = importing
    }

    public var _exporters: [_TransferExporter<Item>] {
        let exporting = exporting, importing = importing
        return [_TransferExporter(contentType: contentType, exportedType: SentTransferredFile.self,
                                  export: exporting.map { exp in { try? exp($0) } } ?? { _ in nil },
                                  importer: importing.map { imp in { ($0 as? ReceivedTransferredFile).flatMap { try? imp($0) } } })]
    }
}

/// Several representations, tried in order.
public struct _TransferRepresentationGroup<Item>: TransferRepresentation {
    public let _exporters: [_TransferExporter<Item>]
}

@resultBuilder
public enum TransferRepresentationBuilder<Item> {
    public static func buildExpression<R: TransferRepresentation>(_ expression: R) -> _TransferRepresentationGroup<Item> where R.Item == Item {
        _TransferRepresentationGroup(_exporters: expression._exporters)
    }
    public static func buildBlock(_ components: _TransferRepresentationGroup<Item>...) -> _TransferRepresentationGroup<Item> {
        _TransferRepresentationGroup(_exporters: components.flatMap(\._exporters))
    }
    public static func buildOptional(_ component: _TransferRepresentationGroup<Item>?) -> _TransferRepresentationGroup<Item> {
        component ?? _TransferRepresentationGroup(_exporters: [])
    }
    public static func buildEither(first component: _TransferRepresentationGroup<Item>) -> _TransferRepresentationGroup<Item> { component }
    public static func buildEither(second component: _TransferRepresentationGroup<Item>) -> _TransferRepresentationGroup<Item> { component }
}

extension String: Transferable {
    public static var transferRepresentation: some TransferRepresentation<String> {
        DataRepresentation(contentType: .utf8PlainText, exporting: { Data($0.utf8) }, importing: { String(decoding: $0, as: UTF8.self) })
    }
}

extension Data: Transferable {
    public static var transferRepresentation: some TransferRepresentation<Data> {
        DataRepresentation(contentType: .data, exporting: { $0 }, importing: { $0 })
    }
}

extension URL: Transferable {
    public static var transferRepresentation: some TransferRepresentation<URL> {
        DataRepresentation(contentType: .url, exporting: { Data($0.absoluteString.utf8) },
                           importing: { URL(string: String(decoding: $0, as: UTF8.self)) ?? URL(string: "about:blank")! })
    }
}

/// A dragged value: the payload as it is, plus its type's representations for destinations of
/// other types; or the items of a drag from outside the app (`external`), typed by what the
/// host reported and loaded through the destination type's importers.
public struct _TransferItem {
    package let value: Any
    package let exporters: [_TransferExporter<Any>]
    /// The items of a drag from outside, else empty.
    package let external: [ExternalDragItem]

    package init<T: Transferable>(_ value: T) {
        self.value = value
        external = []
        exporters = T.transferRepresentation._exporters.map { exporter in
            _TransferExporter<Any>(contentType: exporter.contentType, exportedType: exporter.exportedType,
                                   export: { ($0 as? T).flatMap(exporter.export) }, importer: nil)
        }
    }

    /// A drag from outside: every item exports its text (`String`), a URL for `text/uri-list`,
    /// its bytes (`Data`) under its content type, and a file as a received file.
    package init(external items: [ExternalDragItem]) {
        value = items
        external = items
        var exporters: [_TransferExporter<Any>] = []
        for item in items {
            let type = UTType(_mime: item.type)
            if let text = item.text, type.isText {
                exporters.append(_TransferExporter(contentType: type, exportedType: String.self, export: { _ in text }, importer: nil))
            }
            if type == .url || type == .fileURL, let text = item.text, let url = URL(string: text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text) {
                exporters.append(_TransferExporter(contentType: type, exportedType: URL.self, export: { _ in url }, importer: nil))
            }
            if let data = item.data ?? item.text.map({ Data($0.utf8) }) {
                exporters.append(_TransferExporter(contentType: type, exportedType: Data.self, export: { _ in data }, importer: nil))
                if let name = item.fileName {
                    // A file: stored where the destination's importer can read it.
                    exporters.append(_TransferExporter(contentType: type, exportedType: SentTransferredFile.self,
                                                       export: { _ in SentTransferredFile(_TransferItem.storeFile(data, name: name)) }, importer: nil))
                }
            }
        }
        self.exporters = exporters
    }

    package var isExternal: Bool { !external.isEmpty }
    /// An outside drag that was only announced: its types are known, its data comes with the drop.
    package var isAnnouncement: Bool { isExternal && external.allSatisfy { ($0.data?.isEmpty ?? true) && ($0.text?.isEmpty ?? true) } }

    /// Whether a destination for `T` takes the item: it loads, or it is an announced outside
    /// drag whose types one of `T`'s importers (or `T` itself, for text, URLs and data) reads.
    package func canLoad<T: Transferable>(as type: T.Type) -> Bool {
        if isAnnouncement {
            let types = external.map { UTType(_mime: $0.type) }
            if T.self == String.self { return types.contains { $0.isText } }
            if T.self == URL.self { return types.contains { $0 == .url || $0 == .fileURL } }
            if T.self == Data.self { return true }
            let wanted = T.transferRepresentation._exporters.filter { $0.importer != nil }.compactMap(\.contentType)
            return types.contains { type in wanted.contains { type.conforms(to: $0) || $0.conforms(to: type) } }
        }
        return load(as: T.self) != nil
    }

    /// The item as `T`: the value itself, a proxy export to `T`, a data export `T` can import,
    /// or a proxy export `T` can import. Data imports match the exporter's content type when
    /// both name one (a JSON importer does not take plain text).
    package func load<T: Transferable>(as type: T.Type) -> T? {
        if let direct = value as? T { return direct }
        for exporter in exporters where exporter.exportedType == T.self {
            if let exported = exporter.export(value) as? T { return exported }
        }
        let importers: [(Any.Type, UTType?, (Any) -> T?)] = T.transferRepresentation._exporters.compactMap { exporter in
            exporter.importer.map { importer in (exporter.exportedType, exporter.contentType, importer) }
        }
        for exporter in exporters {
            // A file representation names `SentTransferredFile` both ways; its importer takes the received file.
            let candidates = importers.filter { $0.0 == exporter.exportedType }
            guard !candidates.isEmpty, let exported = exporter.export(value) else { continue }
            for (_, importedType, importer) in candidates {
                if let importedType, let exportedType = exporter.contentType, !importedType.conforms(to: exportedType), !exportedType.conforms(to: importedType) { continue }
                let payload: Any = (exported as? SentTransferredFile).map { ReceivedTransferredFile($0.file, isOriginalFile: $0.allowAccessingOriginalFile) } ?? exported
                if let imported = importer(payload) { return imported }
            }
        }
        return nil
    }

    /// The item for a host's system drag: its text, URL, bytes under each content type, files.
    package func externalItems() -> [ExternalDragItem] {
        if isExternal { return external }
        var items: [ExternalDragItem] = []
        if let text = value as? String { items.append(ExternalDragItem(type: "text/plain", text: text)) }
        if let url = value as? URL { items.append(ExternalDragItem(type: "text/uri-list", text: url.absoluteString)) }
        for exporter in exporters {
            guard let type = exporter.contentType else { continue }
            if exporter.exportedType == Data.self, let data = exporter.export(value) as? Data {
                let text = type.isText ? String(decoding: data, as: UTF8.self) : nil
                if !(value is String && type.isText) { items.append(ExternalDragItem(type: type._mime, text: text, data: data)) }
            } else if exporter.exportedType == SentTransferredFile.self, let file = exporter.export(value) as? SentTransferredFile {
                items.append(ExternalDragItem(type: type._mime, text: file.file.absoluteString, data: try? Data(contentsOf: file.file), fileName: file.file.lastPathComponent))
            }
        }
        return items
    }

    /// Stores a received file's bytes where `Data(contentsOf:)` reads them: a temporary file, or
    /// an in-memory file on wasm.
    package static func storeFile(_ data: Data, name: String) -> URL {
        #if os(WASI)
        return _MemoryFiles.store(data, name: name)
        #else
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("swiftui-web-drops-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try? data.write(to: url)
        return url
        #endif
    }
}

extension UTType {
    /// The MIME type a browser's `DataTransfer` names, or the identifier itself for the rest.
    package var _mime: String {
        switch identifier {
        case "public.plain-text", "public.text": return "text/plain"
        case "public.utf8-plain-text": return "text/plain"
        case "public.url", "public.file-url": return "text/uri-list"
        case "public.html": return "text/html"
        case "public.json": return "application/json"
        case "public.png": return "image/png"
        case "public.jpeg": return "image/jpeg"
        case "public.rtf": return "text/rtf"
        case "public.xml": return "application/xml"
        case "public.comma-separated-values-text": return "text/csv"
        case "public.data", "public.item", "public.content": return "application/octet-stream"
        default: return identifier
        }
    }

    /// The type for a MIME type (or an identifier) a host reported.
    package init(_mime mime: String) {
        let lower = mime.lowercased()
        let identifier: String
        switch lower.split(separator: ";").first.map(String.init) ?? lower {
        case "text/plain", "text": identifier = "public.utf8-plain-text"
        case "text/uri-list", "url": identifier = "public.url"
        case "text/html": identifier = "public.html"
        case "application/json": identifier = "public.json"
        case "image/png": identifier = "public.png"
        case "image/jpeg", "image/jpg": identifier = "public.jpeg"
        case "text/rtf", "application/rtf": identifier = "public.rtf"
        case "application/xml", "text/xml": identifier = "public.xml"
        case "text/csv": identifier = "public.comma-separated-values-text"
        case "application/octet-stream", "files": identifier = "public.data"
        default: identifier = mime
        }
        self.init(identifier)
    }

    /// Whether the type is text (its bytes are UTF-8 to read as a string).
    package var isText: Bool {
        identifier.hasPrefix("public.") && (identifier.contains("text") || identifier == "public.json" || identifier == "public.html" || identifier == "public.xml" || identifier == "public.url")
    }

    /// A coarse conformance: the same identifier; the plain-text types to `plain-text`; the
    /// text types (but URLs) to `text`; PNG and JPEG to `image`; everything to `data`, `item`
    /// and `content`.
    package func conforms(to other: UTType) -> Bool {
        if self == other { return true }
        if other == .data || other == .item || other == .content { return true }
        if other == .plainText { return self == .utf8PlainText }
        if other == .text { return isText && self != .url && self != .fileURL }
        if other == .image { return self == .png || self == .jpeg }
        return false
    }
}

// MARK: - Modifiers

public struct _DraggableModifier<Payload: Transferable, Preview: View> {
    package let payload: () -> Payload
    package let preview: (() -> Preview)?
}

extension _DraggableModifier: ViewModifier {
    public typealias Body = Never
    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        DraggableNode(context)
    }
}

public struct _DropDestinationModifier<T: Transferable> {
    package let action: ([T], CGPoint) -> Bool
    package let isTargeted: (Bool) -> Void
}

extension _DropDestinationModifier: ViewModifier {
    public typealias Body = Never
    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        DropDestinationNode(context)
    }
}

extension View {
    /// macOS Services: accepted for API compatibility; there are no system services in a browser,
    /// and the native host does not register with them.
    nonisolated public func exportableToServices<T: Transferable>(_ payload: @autoclosure @escaping () -> [T]) -> some View { self }
    nonisolated public func exportableToServices<T: Transferable>(_ payload: @autoclosure @escaping () -> [T], onEdit: @escaping ([T]) -> Bool) -> some View { self }

    /// Makes this view a drag source for `payload`; the view itself is the drag preview.
    nonisolated public func draggable<T: Transferable>(_ payload: @autoclosure @escaping () -> T) -> some View {
        modifier(_DraggableModifier<T, EmptyView>(payload: payload, preview: nil))
    }

    /// Makes this view a drag source for `payload`, dragging `preview`.
    nonisolated public func draggable<T: Transferable, V: View>(_ payload: @autoclosure @escaping () -> T, @ViewBuilder preview: @escaping () -> V) -> some View {
        modifier(_DraggableModifier(payload: payload, preview: preview))
    }

    /// Makes this view a drop destination for dragged values of `payloadType`. `action` gets the
    /// values and the drop point in the view's coordinates and returns whether it took them.
    nonisolated public func dropDestination<T: Transferable>(for payloadType: T.Type = T.self,
                                                             action: @escaping ([T], CGPoint) -> Bool,
                                                             isTargeted: @escaping (Bool) -> Void = { _ in }) -> some View {
        modifier(_DropDestinationModifier(action: action, isTargeted: isTargeted))
    }
}
