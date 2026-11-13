// `onDrop` (iOS 13-16): a drop destination for content types that hands the action item
// providers, or asks a `DropDelegate` at each step of the drag (validate, enter, update, exit,
// perform). It shares the runtime's drag sessions with `dropDestination`: the app's own drags
// and drags from outside (Runtime/DragDropNodes.swift). An item provider carries the drag's
// representations that conform to the requested types; its bytes load at once.
import WebFoundation
#if !os(WASI)
import Foundation   // on wasm WebFoundation stands in for it
#endif

/// The operation a drop performs, which a delegate proposes while the drag moves.
public enum DropOperation: Hashable, Sendable {
    /// The drop is cancelled: nothing is transferred.
    case cancel
    /// The drop is not allowed here.
    case forbidden
    /// The data is copied to the destination.
    case copy
    /// The data is moved to the destination.
    case move
}

/// What a drop delegate proposes for the drag at its location.
public struct DropProposal: Sendable {
    public let operation: DropOperation
    public init(operation: DropOperation) { self.operation = operation }
}

/// The current state of a drop: where it is, and what it carries.
@MainActor
public struct DropInfo {
    /// The drag's location in the destination's coordinates.
    public let location: CGPoint
    package let item: _TransferItem

    package init(location: CGPoint, item: _TransferItem) {
        self.location = location
        self.item = item
    }

    /// Whether the drag carries an item of one of the types.
    public func hasItemsConforming(to contentTypes: [UTType]) -> Bool { item.conforms(toAnyOf: contentTypes) }

    /// Whether the drag carries an item of one of the type identifiers.
    public func hasItemsConforming(to types: [String]) -> Bool { hasItemsConforming(to: types.map { UTType($0) }) }

    /// Item providers for the drag's items that conform to one of the types.
    public func itemProviders(for contentTypes: [UTType]) -> [NSItemProvider] { item.itemProviders(for: contentTypes) }

    /// Item providers for the drag's items that conform to one of the type identifiers.
    public func itemProviders(for types: [String]) -> [NSItemProvider] { itemProviders(for: types.map { UTType($0) }) }
}

/// An interface that a drop destination's delegate implements to follow and perform the drop.
@MainActor @preconcurrency
public protocol DropDelegate {
    /// Whether a drop with this information can be performed (by default, yes).
    func validateDrop(info: DropInfo) -> Bool
    /// Performs the drop; returns whether it succeeded.
    func performDrop(info: DropInfo) -> Bool
    /// The drag entered the destination.
    func dropEntered(info: DropInfo)
    /// The drag moved inside the destination; a proposal, or nil for the default (copy).
    func dropUpdated(info: DropInfo) -> DropProposal?
    /// The drag left the destination (or was dropped on it).
    func dropExited(info: DropInfo)
}

extension DropDelegate {
    public func validateDrop(info: DropInfo) -> Bool { true }
    public func dropEntered(info: DropInfo) {}
    public func dropUpdated(info: DropInfo) -> DropProposal? { nil }
    public func dropExited(info: DropInfo) {}
}

/// `onDrop`'s action closures as a delegate: the targeted binding follows enter and exit.
private struct _ActionDropDelegate {
    let types: [UTType]
    let isTargeted: Binding<Bool>?
    let action: ([NSItemProvider], CGPoint) -> Bool
}

extension _ActionDropDelegate: DropDelegate {
    func dropEntered(info: DropInfo) { setTargeted(true) }
    func dropExited(info: DropInfo) { setTargeted(false) }
    func performDrop(info: DropInfo) -> Bool {
        setTargeted(false)
        let providers = info.itemProviders(for: types)
        return !providers.isEmpty && action(providers, info.location)
    }

    private func setTargeted(_ targeted: Bool) {
        if let isTargeted, isTargeted.wrappedValue != targeted { isTargeted.wrappedValue = targeted }
    }
}

public struct _OnDropModifier {
    package let types: [UTType]
    package let delegate: any DropDelegate
    package init(types: [UTType], delegate: any DropDelegate) {
        self.types = types
        self.delegate = delegate
    }
}

extension _OnDropModifier: ViewModifier {
    public typealias Body = Never
    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        OnDropNode(context)
    }
}

extension View {
    /// Makes this view a drop destination for items of the types; `action` gets their
    /// providers and returns whether it took them. `isTargeted` is true while a drag is over it.
    nonisolated public func onDrop(of supportedContentTypes: [UTType], isTargeted: Binding<Bool>?,
                                   perform action: @escaping (_ providers: [NSItemProvider]) -> Bool) -> some View {
        modifier(_OnDropModifier(types: supportedContentTypes,
                                 delegate: _ActionDropDelegate(types: supportedContentTypes, isTargeted: isTargeted, action: { providers, _ in action(providers) })))
    }

    /// Makes this view a drop destination for items of the types; `action` gets their
    /// providers and the drop's location in the view's coordinates.
    nonisolated public func onDrop(of supportedContentTypes: [UTType], isTargeted: Binding<Bool>?,
                                   perform action: @escaping (_ providers: [NSItemProvider], _ location: CGPoint) -> Bool) -> some View {
        modifier(_OnDropModifier(types: supportedContentTypes,
                                 delegate: _ActionDropDelegate(types: supportedContentTypes, isTargeted: isTargeted, action: action)))
    }

    /// Makes this view a drop destination for items of the types, following the drag through
    /// `delegate`.
    nonisolated public func onDrop(of supportedContentTypes: [UTType], delegate: some DropDelegate) -> some View {
        modifier(_OnDropModifier(types: supportedContentTypes, delegate: delegate))
    }

    /// Makes this view a drop destination for items of the type identifiers.
    nonisolated public func onDrop(of supportedTypes: [String], isTargeted: Binding<Bool>?,
                                   perform action: @escaping (_ providers: [NSItemProvider]) -> Bool) -> some View {
        onDrop(of: supportedTypes.map { UTType($0) }, isTargeted: isTargeted, perform: action)
    }

    /// Makes this view a drop destination for items of the type identifiers; `action` also gets
    /// the location.
    nonisolated public func onDrop(of supportedTypes: [String], isTargeted: Binding<Bool>?,
                                   perform action: @escaping (_ providers: [NSItemProvider], _ location: CGPoint) -> Bool) -> some View {
        onDrop(of: supportedTypes.map { UTType($0) }, isTargeted: isTargeted, perform: action)
    }

    /// Makes this view a drop destination for items of the type identifiers, following the
    /// drag through `delegate`.
    nonisolated public func onDrop(of supportedTypes: [String], delegate: some DropDelegate) -> some View {
        onDrop(of: supportedTypes.map { UTType($0) }, delegate: delegate)
    }
}

// MARK: - Item providers

extension _TransferItem {
    /// The content types the item offers: an outside drag's announced types, else its exports.
    package var offeredTypes: [UTType] {
        if isExternal { return external.map { UTType(_mime: $0.type) } }
        var types = exporters.compactMap(\.contentType)
        if value is String { types.append(.plainText) }
        if value is URL { types.append(.url) }
        return types
    }

    /// Whether one of the item's types conforms to one of `types`.
    package func conforms(toAnyOf types: [UTType]) -> Bool {
        offeredTypes.contains { offered in types.contains { offered.conforms(to: $0) } }
    }

    /// Providers for the item's representations that conform to one of `types`: one for each
    /// item of an outside drag, one for an app's own drag.
    package func itemProviders(for types: [UTType]) -> [NSItemProvider] {
        func wanted(_ type: UTType) -> Bool { types.contains { type.conforms(to: $0) } }
        if isExternal {
            return external.compactMap { item in
                let type = UTType(_mime: item.type)
                guard wanted(type) else { return nil }
                let provider = NSItemProvider()
                if let name = item.fileName, let data = item.data {
                    provider._register(_TransferItem.storeFile(data, name: name), as: type)
                } else if type == .url || type == .fileURL, let text = item.text,
                          let url = URL(string: text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text) {
                    provider._register(url, as: type)
                } else if let data = item.data {
                    provider._register(data, as: type)
                } else if let text = item.text {
                    provider._register(text, as: type)
                }
                return provider
            }
        }
        let provider = NSItemProvider()
        var registered: Set<String> = []
        if let text = value as? String, wanted(.plainText) {
            provider._register(text, as: .plainText)
            registered.insert(UTType.plainText.identifier)
        }
        if let url = value as? URL, wanted(.url) {
            provider._register(url, as: .url)
            registered.insert(UTType.url.identifier)
        }
        for exporter in exporters {
            guard let type = exporter.contentType, wanted(type), !registered.contains(type.identifier),
                  let exported = exporter.export(value) else { continue }
            if let file = exported as? SentTransferredFile {
                provider._register(file.file, as: type)
            } else if exported is Data || exported is String || exported is URL {
                provider._register(exported, as: type)
            } else {
                continue
            }
            registered.insert(type.identifier)
        }
        return registered.isEmpty ? [] : [provider]
    }
}

extension NSItemProvider {
    /// Registers a value (bytes, text, a URL, a file's URL) under the type.
    package func _register(_ value: Any, as type: UTType) {
        #if canImport(Darwin)
        let data: Data?
        if let bytes = value as? Data { data = bytes }
        else if let text = value as? String { data = Data(text.utf8) }
        else if let url = value as? URL { data = url.isFileURL ? (try? Data(contentsOf: url)) : Data(url.absoluteString.utf8) }
        else { data = nil }
        guard let data else { return }
        registerDataRepresentation(forTypeIdentifier: type.identifier, visibility: .all) { completion in
            completion(data, nil)
            return nil
        }
        #else
        registerItem(value, typeIdentifier: type.identifier)
        #endif
    }
}

#if !canImport(Darwin)
/// Why an item provider could not load a representation.
public struct _ItemProviderError: Error, CustomStringConvertible {
    public let description: String
}

extension NSItemProvider {
    /// The content types the provider has items for.
    public var registeredContentTypes: [UTType] { registeredTypeIdentifiers.map { UTType($0) } }

    /// The registered identifier that names `contentType` or one of its subtypes.
    private func _identifier(conformingTo contentType: UTType) -> String? {
        registeredTypeIdentifiers.first { UTType($0).conforms(to: contentType) }
            ?? (hasItemConformingToTypeIdentifier(contentType.identifier) ? contentType.identifier : nil)
    }

    /// The item registered for the identifier as bytes (text as UTF-8, a file's contents).
    private func _data(forTypeIdentifier identifier: String) -> Data? {
        var result: Data?
        loadItem(forTypeIdentifier: identifier) { item, _ in
            if let data = item as? Data { result = data }
            else if let text = item as? String { result = Data(text.utf8) }
            else if let url = item as? URL { result = url.isFileURL || url.scheme == "memory" ? (try? Data(contentsOf: url)) : Data(url.absoluteString.utf8) }
        }
        return result
    }

    /// Loads the bytes of the item of a type that conforms to `typeIdentifier`; the handler runs
    /// at once.
    @discardableResult
    public func loadDataRepresentation(forTypeIdentifier typeIdentifier: String,
                                       completionHandler: @escaping (Data?, (any Error)?) -> Void) -> Progress {
        loadDataRepresentation(for: UTType(typeIdentifier), completionHandler: completionHandler)
    }

    /// Loads the bytes of the item of a type that conforms to `contentType`; the handler runs
    /// at once.
    @discardableResult
    public func loadDataRepresentation(for contentType: UTType,
                                       completionHandler: @escaping (Data?, (any Error)?) -> Void) -> Progress {
        let progress = Progress(totalUnitCount: 1)
        let data = _identifier(conformingTo: contentType).flatMap(_data(forTypeIdentifier:))
        progress.completedUnitCount = 1
        completionHandler(data, data == nil ? _ItemProviderError(description: "No item conforms to \(contentType.identifier).") : nil)
        return progress
    }

    /// Loads the item as a transferable value: the value itself, or one of `T`'s importers fed
    /// with an item's bytes, text or file. The handler runs at once.
    @discardableResult
    public func loadTransferable<T: Transferable>(type: T.Type, completionHandler: @escaping (Result<T, any Error>) -> Void) -> Progress {
        let progress = Progress(totalUnitCount: 1)
        defer { progress.completedUnitCount = 1 }
        for identifier in registeredTypeIdentifiers {
            var item: Any?
            loadItem(forTypeIdentifier: identifier) { loaded, _ in item = loaded }
            if let value = item as? T {
                completionHandler(.success(value))
                return progress
            }
            let type = UTType(identifier)
            let external: ExternalDragItem
            if let url = item as? URL, url.isFileURL || url.scheme == "memory" {
                external = ExternalDragItem(type: type._mime, data: try? Data(contentsOf: url), fileName: url.lastPathComponent)
            } else if let url = item as? URL {
                external = ExternalDragItem(type: type._mime, text: url.absoluteString)
            } else if let text = item as? String {
                external = ExternalDragItem(type: type._mime, text: text)
            } else if let data = item as? Data {
                external = ExternalDragItem(type: type._mime, data: data)
            } else {
                continue
            }
            if let value = _TransferItem(external: [external]).load(as: T.self) {
                completionHandler(.success(value))
                return progress
            }
        }
        completionHandler(.failure(_ItemProviderError(description: "No item loads as \(T.self).")))
        return progress
    }
}
#endif

// MARK: - Node

@MainActor
package final class OnDropNode<Content: View>: UnaryLayoutModifierNode<Content, _OnDropModifier>, _DropTarget {
    private var targeted = false
    private var item: _TransferItem?
    private var location: CGPoint = .zero

    private func info(_ item: _TransferItem) -> DropInfo { DropInfo(location: location, item: item) }

    package func accepts(_ item: _TransferItem) -> Bool {
        guard item.conforms(toAnyOf: modifier.types) else { return false }
        self.item = item
        return modifier.delegate.validateDrop(info: info(item))
    }

    package func setTargeted(_ targeted: Bool) {
        guard targeted != self.targeted else { return }
        self.targeted = targeted
        if let item {
            if targeted { modifier.delegate.dropEntered(info: info(item)) } else { modifier.delegate.dropExited(info: info(item)) }
        }
        runtime.requestLayout()
    }

    package func dragUpdated(_ item: _TransferItem, at point: CGPoint) {
        self.item = item
        location = point
        _ = modifier.delegate.dropUpdated(info: info(item))
    }

    package func perform(_ item: _TransferItem, at point: CGPoint) -> Bool {
        self.item = item
        location = point
        return modifier.delegate.performDrop(info: info(item))
    }

    override package var nodeDescription: String { "OnDrop" }
}
