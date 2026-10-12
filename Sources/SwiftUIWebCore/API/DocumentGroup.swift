// DocumentGroup (Docs/elements/Windows.md, sw-windows): a scene whose windows each show a
// document — a `FileDocument` value read from and written to files through the host's open and
// save panels (the browser's file input and downloads, AppKit's panels). The main window opens
// a new document; File > New opens another window, Open… reads a file into a new window, Save
// and Save As… write the frontmost document's file.
#if os(WASI) || os(Linux)
import WebFoundation   // its FileWrapper: FoundationEssentials and corelibs Foundation have none
#else
import Foundation
#endif

/// A type that you use to serialize documents to and from file.
public protocol FileDocument {
    static var readableContentTypes: [UTType] { get }
    static var writableContentTypes: [UTType] { get }
    init(configuration: FileDocumentReadConfiguration) throws
    func fileWrapper(configuration: FileDocumentWriteConfiguration) throws -> FileWrapper
}

extension FileDocument {
    public static var writableContentTypes: [UTType] { readableContentTypes }
}

/// The configuration for reading file contents.
public struct FileDocumentReadConfiguration {
    public let contentType: UTType
    public let file: FileWrapper
    public init(contentType: UTType, file: FileWrapper) {
        self.contentType = contentType
        self.file = file
    }
}

/// The configuration for serializing document contents.
public struct FileDocumentWriteConfiguration {
    public let contentType: UTType
    public let existingFile: FileWrapper?
    public init(contentType: UTType, existingFile: FileWrapper?) {
        self.contentType = contentType
        self.existingFile = existingFile
    }
}

/// The properties of an open file document.
@MainActor @propertyWrapper
public struct FileDocumentConfiguration<Document: FileDocument> {
    /// The current document model.
    @Binding public var document: Document
    public var wrappedValue: Document {
        get { document }
        nonmutating set { document = newValue }
    }
    public var projectedValue: Binding<Document> { $document }
    /// The URL of the open file document, nil for a new one.
    public var fileURL: URL?
    /// A Boolean that indicates whether you can edit the document.
    public var isEditable: Bool

    package init(document: Binding<Document>, fileURL: URL?, isEditable: Bool) {
        _document = document
        self.fileURL = fileURL
        self.isEditable = isEditable
    }
}

/// A scene that enables support for opening, creating, and saving documents.
public struct DocumentGroup<Document, Content: View>: Scene {
    package let descriptor: _WindowDescriptor

    public typealias Body = Never
    public var body: Never { fatalError("DocumentGroup has no body") }
    public static func _windows(of scene: DocumentGroup<Document, Content>) -> [_WindowDescriptor] { [scene.descriptor] }
}

extension DocumentGroup where Document: FileDocument {
    /// Creates a document group for creating and editing file documents.
    public init(newDocument: @autoclosure @escaping () -> Document, @ViewBuilder editor: @escaping (FileDocumentConfiguration<Document>) -> Content) {
        descriptor = Self.descriptor(newDocument: newDocument, isEditable: true, content: editor)
    }

    /// Creates a document group that is able to view file documents.
    public init(viewing documentType: Document.Type, @ViewBuilder viewer: @escaping (FileDocumentConfiguration<Document>) -> Content) {
        descriptor = Self.descriptor(newDocument: nil, isEditable: false, content: viewer)
    }

    private static func descriptor(newDocument: (() -> Document)?, isEditable: Bool, content: @escaping (FileDocumentConfiguration<Document>) -> Content) -> _WindowDescriptor {
        let make: @MainActor (_WindowValueBox?) -> AnyView = { box in
            // Each window's box holds its `_DocumentState`; the main window makes a new document.
            let state: _DocumentState<Document>
            if let existing = box?.value as? _DocumentState<Document> {
                state = existing
            } else {
                let fresh: Document? = newDocument?()
                state = _DocumentState(document: fresh, url: nil)
                box?.value = state
            }
            return AnyView(_DocumentWindow(state: state, isEditable: isEditable, content: content))
        }
        var descriptor = _WindowDescriptor(kind: .windowGroup, id: "document", title: nil, valueType: nil, make: make)
        var makeNew: (@MainActor () -> _DocumentState<Document>)?
        if let newDocument {
            makeNew = { _DocumentState(document: newDocument(), url: nil) }
        }
        let read: @MainActor (Data, UTType, URL?, String?) throws -> _DocumentState<Document> = { data, type, url, name in
            let document = try Document(configuration: FileDocumentReadConfiguration(contentType: type, file: FileWrapper(regularFileWithContents: data)))
            return _DocumentState(document: document, url: url, fileName: name)
        }
        descriptor.documentType = _DocumentTypeBox(Document.self, makeNew: makeNew, read: read)
        return descriptor
    }
}

/// A document window's model: the document value and where it came from (shared with the
/// editor's binding through the window's value box).
@MainActor
public final class _DocumentState<Document: FileDocument>: _AnyDocumentState, Hashable {
    nonisolated public static func == (lhs: _DocumentState, rhs: _DocumentState) -> Bool { lhs === rhs }
    nonisolated public func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }

    public var document: Document?
    public var url: URL?
    /// The file's name when it was opened without a URL (a browser's file input).
    public var fileName: String?
    package var onChange: (() -> Void)?
    package init(document: Document?, url: URL?, fileName: String? = nil) {
        self.document = document
        self.url = url
        self.fileName = fileName
    }

    /// The document's bytes for saving, its content type and a name for the file.
    public func serialized() throws -> (data: Data, type: UTType, name: String)? {
        guard let document else { return nil }
        let type = Document.writableContentTypes.first ?? Document.readableContentTypes.first ?? .data
        let wrapper = try document.fileWrapper(configuration: FileDocumentWriteConfiguration(contentType: type, existingFile: nil))
        guard let data = wrapper.regularFileContents else { return nil }
        let name = url?.lastPathComponent ?? fileName ?? wrapper.preferredFilename ?? "Untitled.\(type.preferredFilenameExtension ?? "txt")"
        return (data, type, name)
    }

    public var fileURL: URL? { url }
    public func setFileURL(_ url: URL?) { self.url = url }
    /// The state as a window value (windows are keyed by their value).
    public var windowValue: AnyHashable { AnyHashable(self) }
}

/// What the runtime knows of a document window's state without the document's type.
@MainActor
public protocol _AnyDocumentState: AnyObject {
    func serialized() throws -> (data: Data, type: UTType, name: String)?
    var fileURL: URL? { get }
    func setFileURL(_ url: URL?)
    var windowValue: AnyHashable { get }
}

/// A document group's type-erased document operations.
public struct _DocumentTypeBox {
    public let readableTypes: [UTType]
    /// A new, empty document state (nil for a viewing group).
    public let makeNew: (@MainActor () -> any _AnyDocumentState)?
    /// A document state read from a file's bytes.
    public let read: @MainActor (Data, UTType, URL?, String?) throws -> any _AnyDocumentState

    @MainActor init<D: FileDocument>(_ type: D.Type, makeNew: (@MainActor () -> _DocumentState<D>)?, read: @escaping @MainActor (Data, UTType, URL?, String?) throws -> _DocumentState<D>) {
        readableTypes = D.readableContentTypes
        if let makeNew {
            let erased: @MainActor () -> any _AnyDocumentState = { makeNew() }
            self.makeNew = erased
        } else {
            self.makeNew = nil
        }
        let erasedRead: @MainActor (Data, UTType, URL?, String?) throws -> any _AnyDocumentState = { data, type, url, name in
            let state: _DocumentState<D> = try read(data, type, url, name)
            return state
        }
        self.read = erasedRead
    }
}

/// A document window's content: the editor over the state's document binding.
struct _DocumentWindow<Document: FileDocument, Content: View>: View {
    let state: _DocumentState<Document>
    let isEditable: Bool
    let content: (FileDocumentConfiguration<Document>) -> Content
    @State private var revision = 0

    var body: some View {
        let _ = revision
        if let document = state.document {
            let binding = Binding<Document>(get: { state.document ?? document }, set: { state.document = $0; revision += 1; state.onChange?() })
            content(FileDocumentConfiguration(document: binding, fileURL: state.url, isEditable: isEditable))
        } else {
            Text("No Document").foregroundStyle(.secondary)
        }
    }
}

extension UTType {
    /// The file extension for the common types (the download's name, the open panel's filter).
    public var preferredFilenameExtension: String? {
        switch identifier {
        case "public.plain-text", "public.utf8-plain-text", "public.text": return "txt"
        case "public.json": return "json"
        case "public.png": return "png"
        case "public.jpeg": return "jpg"
        case "public.rtf": return "rtf"
        case "public.html": return "html"
        case "public.xml": return "xml"
        case "public.comma-separated-values-text": return "csv"
        default:
            // An exported type's identifier ends with its extension by convention ("com.example.notes").
            let last = identifier.split(separator: ".").last.map(String.init)
            return identifier.hasPrefix("public.") || identifier.hasPrefix("com.apple.") ? nil : last
        }
    }

    public static let rtf = UTType("public.rtf")
    public static let html = UTType("public.html")
    public static let xml = UTType("public.xml")
    public static let commaSeparatedText = UTType("public.comma-separated-values-text")
}
