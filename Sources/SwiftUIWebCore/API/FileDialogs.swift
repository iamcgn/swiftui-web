// File dialogs a view presents with a binding (iOS 14-17): `fileImporter` shows the host's
// open panel (a browser's file input) and hands back URLs of the chosen files; `fileExporter`
// writes a document or a transferable item through the host's save panel (a download in a
// browser). Both read the runtime's file handlers through the environment, so a view without
// a host (a headless test runtime with none installed) reports a failure and resets the binding.
import WebFoundation
#if !os(WASI)
import Foundation   // on wasm WebFoundation stands in for it
#endif

/// The runtime whose host shows the file panels, for the file dialog modifiers.
package struct _FileDialogs {
    package weak var runtime: Runtime?
    package init(runtime: Runtime? = nil) { self.runtime = runtime }
}

package struct FileDialogsKey: EnvironmentKey {
    package static let defaultValue = _FileDialogs()
}

extension EnvironmentValues {
    package var _fileDialogs: _FileDialogs {
        get { self[FileDialogsKey.self] }
        set { self[FileDialogsKey.self] = newValue }
    }
}

/// Why a file dialog could not run: the host has no panel for it.
public struct _FileDialogError: Error, CustomStringConvertible {
    public let description: String
}

/// Holds a file dialog's callbacks (a class so the runtime's field reflection ignores them).
package final class _FileDialogBox {
    package let completion: (Result<[URL], any Error>) -> Void
    package let cancellation: () -> Void
    package init(completion: @escaping (Result<[URL], any Error>) -> Void, cancellation: @escaping () -> Void) {
        self.completion = completion
        self.cancellation = cancellation
    }
}

// MARK: - Importer

/// Runs `present` with the host's runtime when the binding turns true (and at appearance when
/// it already is): the view that reads the environment for the file dialog modifiers.
package struct _FileDialogTrigger<Content: View>: View {
    let content: Content
    let isPresented: Binding<Bool>
    let present: _FileDialogPresenter
    @Environment(\._fileDialogs) var dialogs

    package init(content: Content, isPresented: Binding<Bool>, present: _FileDialogPresenter) {
        self.content = content
        self.isPresented = isPresented
        self.present = present
    }

    package var body: some View {
        let dialogs = self.dialogs, present = self.present
        return content.onChange(of: isPresented.wrappedValue, initial: true) { _, shown in
            if shown { present.run(dialogs.runtime) }
        }
    }
}

/// A file dialog's presentation, given the runtime (a class so field reflection ignores it).
package final class _FileDialogPresenter {
    package let run: @MainActor (Runtime?) -> Void
    package init(_ run: @escaping @MainActor (Runtime?) -> Void) { self.run = run }
}

/// `fileImporter`: when the binding turns true, the host's open panel for the types; the
/// chosen files arrive as URLs `Data(contentsOf:)` reads (the host's own, or copies: a
/// temporary file, a `memory:` file on wasm). The binding is reset when the panel closes.
public struct _FileImporterModifier {
    package let isPresented: Binding<Bool>
    package let types: [UTType]
    package let allowsMultiple: Bool
    package let box: _FileDialogBox

    package init(isPresented: Binding<Bool>, types: [UTType], allowsMultiple: Bool, box: _FileDialogBox) {
        self.isPresented = isPresented
        self.types = types
        self.allowsMultiple = allowsMultiple
        self.box = box
    }
}

extension _FileImporterModifier: ViewModifier {
    public func body(content: Content) -> some View {
        let isPresented = self.isPresented, types = self.types, multiple = allowsMultiple, box = self.box
        return _FileDialogTrigger(content: content, isPresented: isPresented, present: _FileDialogPresenter { runtime in
            _FileImporterModifier.present(isPresented: isPresented, types: types, allowsMultiple: multiple, box: box, runtime: runtime)
        })
    }

    @MainActor
    package static func present(isPresented: Binding<Bool>, types: [UTType], allowsMultiple: Bool, box: _FileDialogBox, runtime: Runtime?) {
        guard let open = runtime?.fileOpenHandler else {
            isPresented.wrappedValue = false
            box.completion(.failure(_FileDialogError(description: "No open panel: the host installs none.")))
            return
        }
        let extensions = types.compactMap(\.preferredFilenameExtension)
        let imagesOnly = !types.isEmpty && types.allSatisfy { $0.conforms(to: .image) }
        open(HostFileOpenRequest(extensions: extensions, allowsMultiple: allowsMultiple, imagesOnly: imagesOnly)) { files in
            isPresented.wrappedValue = false
            let urls = files.map { $0.url ?? _TransferItem.storeFile($0.data, name: $0.name) }
            if urls.isEmpty { box.cancellation() } else { box.completion(.success(allowsMultiple ? urls : [urls[0]])) }
        }
    }
}

// MARK: - Exporter

/// `fileExporter`: when the binding turns true, the bytes `make` gives go through the host's
/// save panel under their name; the completion gets where they went (a copy readable with
/// `Data(contentsOf:)` when the host keeps no file, as a browser's download does).
public struct _FileExporterModifier {
    package let isPresented: Binding<Bool>
    package let make: _FileExportBox
    package let box: _FileDialogBox

    package init(isPresented: Binding<Bool>, make: _FileExportBox, box: _FileDialogBox) {
        self.isPresented = isPresented
        self.make = make
        self.box = box
    }
}

extension _FileExporterModifier: ViewModifier {
    public func body(content: Content) -> some View {
        let isPresented = self.isPresented, make = self.make, box = self.box
        return _FileDialogTrigger(content: content, isPresented: isPresented, present: _FileDialogPresenter { runtime in
            isPresented.wrappedValue = false
            guard let save = runtime?.documentSaveHandler else {
                box.completion(.failure(_FileDialogError(description: "No save panel: the host installs none.")))
                return
            }
            do {
                guard let file = try make.make() else { box.cancellation(); return }
                let url = save(file.data, file.name, file.type, nil) ?? _TransferItem.storeFile(file.data, name: file.name)
                box.completion(.success([url]))
            } catch {
                box.completion(.failure(error))
            }
        })
    }
}

/// Makes an export's bytes, content type and file name when the panel is asked for.
package final class _FileExportBox {
    package let make: () throws -> (data: Data, type: UTType, name: String)?
    package init(_ make: @escaping () throws -> (data: Data, type: UTType, name: String)?) { self.make = make }
}

extension _TransferItem {
    /// The item's bytes for one of `types` (the first exporter of data that conforms, else its
    /// text), with the type they were exported as.
    package func exportedData(for types: [UTType]) -> (Data, UTType)? {
        for exporter in exporters where exporter.exportedType == Data.self {
            guard let type = exporter.contentType, types.isEmpty || types.contains(where: { type.conforms(to: $0) }) else { continue }
            if let data = exporter.export(value) as? Data { return (data, type) }
        }
        for exporter in exporters where exporter.exportedType == SentTransferredFile.self {
            guard let type = exporter.contentType, types.isEmpty || types.contains(where: { type.conforms(to: $0) }) else { continue }
            if let file = exporter.export(value) as? SentTransferredFile, let data = try? Data(contentsOf: file.file) { return (data, type) }
        }
        if let text = value as? String { return (Data(text.utf8), types.first ?? .plainText) }
        return nil
    }
}

extension View {
    /// Presents the host's open panel for one file of the given types. The completion gets the
    /// file's URL; when the panel is dismissed without a choice it does not run.
    nonisolated public func fileImporter(isPresented: Binding<Bool>, allowedContentTypes: [UTType],
                                         onCompletion: @escaping (_ result: Result<URL, any Error>) -> Void) -> some View {
        modifier(_FileImporterModifier(isPresented: isPresented, types: allowedContentTypes, allowsMultiple: false,
                                       box: _FileDialogBox(completion: { onCompletion($0.map { $0[0] }) }, cancellation: {})))
    }

    /// Presents the host's open panel for files of the given types, one or several.
    nonisolated public func fileImporter(isPresented: Binding<Bool>, allowedContentTypes: [UTType], allowsMultipleSelection: Bool,
                                         onCompletion: @escaping (_ result: Result<[URL], any Error>) -> Void) -> some View {
        modifier(_FileImporterModifier(isPresented: isPresented, types: allowedContentTypes, allowsMultiple: allowsMultipleSelection,
                                       box: _FileDialogBox(completion: onCompletion, cancellation: {})))
    }

    /// Presents the host's open panel for files of the given types; `onCancellation` runs when
    /// the panel closes without a choice.
    nonisolated public func fileImporter(isPresented: Binding<Bool>, allowedContentTypes: [UTType], allowsMultipleSelection: Bool,
                                         onCompletion: @escaping (_ result: Result<[URL], any Error>) -> Void,
                                         onCancellation: @escaping () -> Void) -> some View {
        modifier(_FileImporterModifier(isPresented: isPresented, types: allowedContentTypes, allowsMultiple: allowsMultipleSelection,
                                       box: _FileDialogBox(completion: onCompletion, cancellation: onCancellation)))
    }

    /// Writes `document` through the host's save panel as `contentType`, named `defaultFilename`
    /// (else "Untitled" with the type's extension). A nil document saves nothing.
    nonisolated public func fileExporter<D: FileDocument>(isPresented: Binding<Bool>, document: D?, contentType: UTType,
                                                          defaultFilename: String? = nil,
                                                          onCompletion: @escaping (_ result: Result<URL, any Error>) -> Void) -> some View {
        modifier(_FileExporterModifier(isPresented: isPresented, make: _FileExportBox {
            guard let document else { return nil }
            let wrapper = try document.fileWrapper(configuration: FileDocumentWriteConfiguration(contentType: contentType, existingFile: nil))
            guard let data = wrapper.regularFileContents else { return nil }
            return (data, contentType, _exportName(defaultFilename ?? wrapper.preferredFilename, contentType))
        }, box: _FileDialogBox(completion: { onCompletion($0.map { $0[0] }) }, cancellation: {})))
    }

    /// Writes a transferable `item` through the host's save panel, as the first of
    /// `contentTypes` it exports (any of its types when empty). A nil item saves nothing and
    /// runs `onCancellation`.
    nonisolated public func fileExporter<T: Transferable>(isPresented: Binding<Bool>, item: T?, contentTypes: [UTType] = [],
                                                          defaultFilename: String? = nil,
                                                          onCompletion: @escaping (_ result: Result<URL, any Error>) -> Void,
                                                          onCancellation: @escaping () -> Void = {}) -> some View {
        modifier(_FileExporterModifier(isPresented: isPresented, make: _FileExportBox {
            guard let item, let exported = _TransferItem(item).exportedData(for: contentTypes) else { return nil }
            return (exported.0, exported.1, _exportName(defaultFilename, exported.1))
        }, box: _FileDialogBox(completion: { onCompletion($0.map { $0[0] }) }, cancellation: onCancellation)))
    }
}

/// A saved file's name: the one given (with the type's extension when it has none), else
/// "Untitled" with it.
private func _exportName(_ name: String?, _ type: UTType) -> String {
    let ext = type.preferredFilenameExtension
    guard let name, !name.isEmpty else { return "Untitled" + (ext.map { "." + $0 } ?? "") }
    if let ext, !name.utf8.contains(UInt8(ascii: ".")) { return name + "." + ext }
    return name
}
