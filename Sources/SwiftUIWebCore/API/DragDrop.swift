// Drag and drop inside the app: `draggable` starts a drag session from a press that moves,
// `dropDestination` receives the payload. Payloads are `Transferable` values carried as they are;
// a destination for another type reads them through the payload's proxy representation.
#if os(WASI)
import FoundationEssentials
#else
import Foundation
#endif

// MARK: - Uniform type identifiers (the subset the representations name)

/// A uniform type identifier.
public struct UTType: Hashable, Sendable {
    public let identifier: String
    public init(_ identifier: String) { self.identifier = identifier }
    public init?(exportedAs identifier: String) { self.identifier = identifier }

    public static let item = UTType("public.item")
    public static let data = UTType("public.data")
    public static let content = UTType("public.content")
    public static let text = UTType("public.text")
    public static let plainText = UTType("public.plain-text")
    public static let utf8PlainText = UTType("public.utf8-plain-text")
    public static let url = UTType("public.url")
    public static let fileURL = UTType("public.file-url")
    public static let json = UTType("public.json")
    public static let image = UTType("public.image")
    public static let png = UTType("public.png")
    public static let jpeg = UTType("public.jpeg")
}

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

/// Exports the item as JSON.
public struct CodableRepresentation<Item: Codable>: TransferRepresentation {
    package let contentType: UTType
    public init(contentType: UTType = .json) { self.contentType = contentType }
    public var _exporters: [_TransferExporter<Item>] {
        [_TransferExporter(contentType: contentType, exportedType: Data.self,
                           export: { try? JSONEncoder().encode($0) },
                           importer: { ($0 as? Data).flatMap { try? JSONDecoder().decode(Item.self, from: $0) } })]
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
/// other types.
public struct _TransferItem {
    package let value: Any
    package let exporters: [_TransferExporter<Any>]

    package init<T: Transferable>(_ value: T) {
        self.value = value
        exporters = T.transferRepresentation._exporters.map { exporter in
            _TransferExporter<Any>(contentType: exporter.contentType, exportedType: exporter.exportedType,
                                   export: { ($0 as? T).flatMap(exporter.export) }, importer: nil)
        }
    }

    /// The item as `T`: the value itself, a proxy export to `T`, a data export `T` can import,
    /// or a proxy export `T` can import.
    package func load<T: Transferable>(as type: T.Type) -> T? {
        if let direct = value as? T { return direct }
        for exporter in exporters where exporter.exportedType == T.self {
            if let exported = exporter.export(value) as? T { return exported }
        }
        let importers: [(Any.Type, (Any) -> T?)] = T.transferRepresentation._exporters.compactMap { exporter in
            exporter.importer.map { importer in (exporter.exportedType, importer) }
        }
        for exporter in exporters {
            guard let exported = exporter.export(value) else { continue }
            for (importedType, importer) in importers where importedType == exporter.exportedType {
                if let imported = importer(exported) { return imported }
            }
        }
        return nil
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
