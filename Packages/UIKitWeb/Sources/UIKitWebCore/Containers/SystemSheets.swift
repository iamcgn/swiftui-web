// The system sheets (uk-system-sheets, Docs/elements/UIKit/Presentation.md): the share sheet,
// the document picker and the image picker are the host's — the browser's Web Share, file
// input (an `image/*` input offers the photo library on a phone) and downloads; AppKit's
// sharing picker, open panel and save panel — reached through the scene's handlers
// (`UIKitScene.shareHandler`, `fileOpenHandler`, `fileSaveHandler`). Presenting one of these
// controllers shows nothing of its own: it asks the host and completes when the host answers
// (or at once, dismissed, where the host has nothing to offer).
#if !os(WASI)
import Foundation
#endif
import WebFoundation

/// The activity types the share sheet names (the host decides what it offers).
public struct UIActivityType: Hashable, RawRepresentable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public static let postToFacebook = UIActivityType("com.apple.UIKit.activity.PostToFacebook")
    public static let postToTwitter = UIActivityType("com.apple.UIKit.activity.PostToTwitter")
    public static let message = UIActivityType("com.apple.UIKit.activity.Message")
    public static let mail = UIActivityType("com.apple.UIKit.activity.Mail")
    public static let print = UIActivityType("com.apple.UIKit.activity.Print")
    public static let copyToPasteboard = UIActivityType("com.apple.UIKit.activity.CopyToPasteboard")
    public static let saveToCameraRoll = UIActivityType("com.apple.UIKit.activity.SaveToCameraRoll")
    public static let airDrop = UIActivityType("com.apple.UIKit.activity.AirDrop")
    public static let markupAsPDF = UIActivityType("com.apple.UIKit.activity.MarkupAsPDF")
}

/// An activity an app adds to the share sheet (accepted; hosts show their own sheets, so an
/// app's activities are not offered).
@preconcurrency @MainActor
open class UIActivity {
    public typealias ActivityType = UIActivityType
    public init() {}
    open var activityType: UIActivityType? { nil }
    open var activityTitle: String? { nil }
    open var activityImage: UIImage? { nil }
    open func canPerform(withActivityItems activityItems: [Any]) -> Bool { false }
    open func prepare(withActivityItems activityItems: [Any]) {}
    open func perform() { activityDidFinish(true) }
    open func activityDidFinish(_ completed: Bool) {}
}

/// A view controller that offers the system share sheet for the items.
@preconcurrency @MainActor
open class UIActivityViewController: UIViewController {
    /// No archive to decode on the web: nil, as for an archive this class cannot read.
    public required init?(coder: NSCoder) { return nil }

    public typealias CompletionWithItemsHandler = (UIActivityType?, Bool, [Any]?, Error?) -> Void
    public let activityItems: [Any]
    public let applicationActivities: [UIActivity]?
    open var excludedActivityTypes: [UIActivityType]?
    open var completionWithItemsHandler: CompletionWithItemsHandler?
    /// The request the host was given, for tests and hosts that look.
    public private(set) var lastRequest: HostShareRequest?

    public init(activityItems: [Any], applicationActivities: [UIActivity]?) {
        self.activityItems = activityItems
        self.applicationActivities = applicationActivities
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .formSheet
    }

    /// The items as the host takes them: URLs and strings as links and texts, images as PNG
    /// files, data as files named after their position, anything else by its description.
    public var shareRequest: HostShareRequest {
        var items: [String] = []
        var files: [HostFile] = []
        for (index, item) in activityItems.enumerated() {
            switch item {
            case let url as URL: items.append(url.absoluteString)
            case let text as String: items.append(text)
            case let image as UIImage:
                if let png = image.pngData() { files.append(HostFile(data: png, name: "Image \(index + 1).png", mimeType: "image/png")) }
            case let data as Data: files.append(HostFile(data: data, name: "Item \(index + 1)", mimeType: "application/octet-stream"))
            case let source as any UIActivityItemSource:
                if let value = source.activityViewController(self, itemForActivityType: nil) {
                    switch value {
                    case let url as URL: items.append(url.absoluteString)
                    case let text as String: items.append(text)
                    default: items.append(String(describing: value))
                    }
                }
            default: items.append(String(describing: item))
            }
        }
        let subject = activityItems.lazy.compactMap { ($0 as? any UIActivityItemSource)?.activityViewController(self, subjectForActivityType: nil) }.first { !$0.isEmpty }
        return HostShareRequest(items: items, subject: subject, files: files)
    }

    /// Presenting asks the host to share; the controller dismisses itself once it has (the
    /// host's sheet is its own, so nothing of the controller's is on screen), completing with
    /// no activity type: hosts do not say which service the user chose.
    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        let request = shareRequest
        lastRequest = request
        let shared = UIKitScene.shared.shareHandler != nil
        UIKitScene.shared.shareHandler?(request)
        let completion = completionWithItemsHandler
        dismiss(animated: false) { completion?(nil, shared, nil, nil) }
    }
}

/// An object that provides the share sheet's items lazily, per activity.
@preconcurrency @MainActor
public protocol UIActivityItemSource: AnyObject {
    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any
    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivityType?) -> Any?
    func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivityType?) -> String
}

extension UIActivityItemSource {
    public func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivityType?) -> String { "" }
}

// MARK: - Documents

/// The methods a document picker's delegate implements.
@preconcurrency @MainActor
public protocol UIDocumentPickerDelegate: AnyObject {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL])
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController)
}

extension UIDocumentPickerDelegate {
    public func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {}
}

/// A view controller that offers the host's file chooser for the types (opening), or its file
/// saver for a document (exporting). Picked files land in the app's temporary directory and
/// are handed to the delegate as URLs, as UIKit does with copies.
@preconcurrency @MainActor
open class UIDocumentPickerViewController: UIViewController {
    /// No archive to decode on the web: nil, as for an archive this class cannot read.
    public required init?(coder: NSCoder) { return nil }

    public enum Mode: Sendable { case open, export }
    public let mode: Mode
    /// The extensions opened (empty: any file; "jpg", "png"… for images).
    public let extensions: [String]
    /// Whether the chooser is the photo library (every type an image).
    public let imagesOnly: Bool
    public let exportedFiles: [HostFile]
    open weak var delegate: (any UIDocumentPickerDelegate)?
    open var allowsMultipleSelection = false
    open var shouldShowFileExtensions = false
    open var directoryURL: URL?
    public private(set) var pickedURLs: [URL] = []

    /// Opens documents of the types (the host's chooser filters by their extensions, where
    /// the types are known here; `public.image` and the image types ask for images).
    public init(forOpeningContentTypes contentTypes: [UTType], asCopy: Bool = true) {
        mode = .open
        let known: [String: [String]] = ["public.png": ["png"], "public.jpeg": ["jpg", "jpeg"], "public.plain-text": ["txt"], "public.utf8-plain-text": ["txt"], "public.text": ["txt"],
                                         "com.adobe.pdf": ["pdf"], "public.json": ["json"], "public.comma-separated-values-text": ["csv"], "public.rtf": ["rtf"], "public.html": ["html", "htm"],
                                         "public.image": ["png", "jpg", "jpeg", "gif", "heic"]]
        extensions = contentTypes.flatMap { known[$0.identifier] ?? [] }
        imagesOnly = !contentTypes.isEmpty && contentTypes.allSatisfy { ["public.image", "public.png", "public.jpeg"].contains($0.identifier) }
        exportedFiles = []
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .formSheet
    }

    /// Exports (saves) a document: the host's saver takes its bytes under its name.
    public init(forExporting urls: [URL], asCopy: Bool = true) {
        mode = .export
        extensions = []
        imagesOnly = false
        exportedFiles = urls.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return HostFile(data: data, name: url.lastPathComponent, mimeType: Self.mimeType(for: url.pathExtension), url: url)
        }
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .formSheet
    }

    static func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "txt": return "text/plain"
        case "json": return "application/json"
        case "pdf": return "application/pdf"
        case "csv": return "text/csv"
        case "html", "htm": return "text/html"
        default: return "application/octet-stream"
        }
    }

    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        let scene = UIKitScene.shared
        switch mode {
        case .open:
            guard let open = scene.fileOpenHandler else {
                dismiss(animated: false) { [weak self] in if let self { self.delegate?.documentPickerWasCancelled(self) } }
                return
            }
            open(HostFileOpenRequest(extensions: extensions, allowsMultiple: allowsMultipleSelection, imagesOnly: imagesOnly)) { [weak self] files in
                guard let self else { return }
                let urls = files.compactMap { $0.url ?? Self.temporaryURL(for: $0) }
                self.pickedURLs = urls
                self.dismiss(animated: false) {
                    if urls.isEmpty { self.delegate?.documentPickerWasCancelled(self) } else { self.delegate?.documentPicker(self, didPickDocumentsAt: urls) }
                }
            }
        case .export:
            let saver = scene.fileSaveHandler
            for file in exportedFiles { saver?(file) }
            let urls = exportedFiles.compactMap(\.url)
            dismiss(animated: false) { [weak self] in
                guard let self else { return }
                if saver == nil { self.delegate?.documentPickerWasCancelled(self) } else { self.delegate?.documentPicker(self, didPickDocumentsAt: urls) }
            }
        }
    }

    /// A picked file stored where `Data(contentsOf:)` reads it (the host gave only bytes): a
    /// temporary file, or an in-memory `memory:` file on wasm, named after the original.
    static func temporaryURL(for file: HostFile) -> URL? {
        #if os(WASI)
        return _MemoryFiles.store(file.data, name: "UIKitWeb-" + file.name)
        #else
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("UIKitWeb-" + file.name)
        return (try? file.data.write(to: url)) != nil ? url : nil
        #endif
    }
}

// MARK: - Images

/// The methods an image picker's delegate implements.
@preconcurrency @MainActor
public protocol UIImagePickerControllerDelegate: AnyObject {
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any])
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController)
}

extension UIImagePickerControllerDelegate {
    public func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {}
}

/// A view controller that offers the host's image chooser (a phone's photo library through
/// the browser's `image/*` input; the open panel on the Mac). The camera is not a source the
/// hosts offer: `isSourceTypeAvailable(.camera)` is false.
@preconcurrency @MainActor
open class UIImagePickerController: UIViewController {
    /// No archive to decode on the web: nil, as for an archive this class cannot read.
    public required init?(coder: NSCoder) { return nil }

    public enum SourceType: Int, Sendable { case photoLibrary = 0, camera, savedPhotosAlbum }
    public struct InfoKey: Hashable, RawRepresentable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let originalImage = InfoKey(rawValue: "UIImagePickerControllerOriginalImage")
        public static let editedImage = InfoKey(rawValue: "UIImagePickerControllerEditedImage")
        public static let imageURL = InfoKey(rawValue: "UIImagePickerControllerImageURL")
        public static let mediaType = InfoKey(rawValue: "UIImagePickerControllerMediaType")
    }
    open var sourceType: SourceType = .photoLibrary
    open var allowsEditing = false
    open var mediaTypes: [String] = ["public.image"]
    open weak var delegate: (any UIImagePickerControllerDelegate & UINavigationControllerDelegate)?
    public private(set) var pickedImage: UIImage?

    public override init(nibName: String? = nil, bundle: Any? = nil) {
        super.init(nibName: nibName, bundle: bundle)
        modalPresentationStyle = .fullScreen
    }

    public class func isSourceTypeAvailable(_ sourceType: SourceType) -> Bool {
        sourceType != .camera && UIKitScene.shared.fileOpenHandler != nil
    }

    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard let open = UIKitScene.shared.fileOpenHandler, sourceType != .camera else {
            dismiss(animated: false) { [weak self] in if let self { self.delegate?.imagePickerControllerDidCancel(self) } }
            return
        }
        open(HostFileOpenRequest(extensions: [], allowsMultiple: false, imagesOnly: true)) { [weak self] files in
            guard let self else { return }
            guard let file = files.first, let image = UIImage(data: file.data) else {
                self.dismiss(animated: false) { self.delegate?.imagePickerControllerDidCancel(self) }
                return
            }
            self.pickedImage = image
            var info: [InfoKey: Any] = [.originalImage: image, .mediaType: "public.image"]
            if self.allowsEditing { info[.editedImage] = image }
            if let url = file.url ?? UIDocumentPickerViewController.temporaryURL(for: file) { info[.imageURL] = url }
            self.dismiss(animated: false) { self.delegate?.imagePickerController(self, didFinishPickingMediaWithInfo: info) }
        }
    }
}
