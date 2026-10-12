// uk-system-sheets (Containers/SystemSheets.swift): the share sheet, document picker and image
// picker ask the host through the scene's handlers and complete with what it answers.
import Testing
import WebGraphics
@testable import UIKitWebCore
import UIKit

@Suite @MainActor struct SystemSheetTests {
    final class Picks: NSObject, UIDocumentPickerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        var urls: [URL] = []
        var cancelled = 0
        var images: [UIImage] = []
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { self.urls = urls }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { cancelled += 1 }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { images.append(image) }
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { cancelled += 1 }
    }

    private func host() -> (UIKitScene, UIViewController) {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        scene.configureScreen(size: CGSize(width: 320, height: 480), scale: 2)
        scene.shareHandler = nil
        scene.fileOpenHandler = nil
        scene.fileSaveHandler = nil
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let root = UIViewController()
        window.rootViewController = root
        window.makeKeyAndVisible()
        scene.layout(in: CGSize(width: 320, height: 480))
        return (scene, root)
    }

    /// A 2 × 2 PNG (the smallest the image decoder's header check accepts).
    static let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0x0D, 0x49, 0x48, 0x44, 0x52, 0, 0, 0, 2, 0, 0, 0, 2, 8, 6, 0, 0, 0, 0x72, 0xB6, 0x0D, 0x24, 0, 0, 0, 0, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82])

    @Test func shareSheetAsksTheHost() {
        let (scene, root) = host()
        var requests: [HostShareRequest] = []
        scene.shareHandler = { requests.append($0) }
        var completions: [(UIActivityType?, Bool)] = []
        let image = UIImage(data: Self.png)!
        let sheet = UIActivityViewController(activityItems: ["Hello", URL(string: "https://example.com")!, image], applicationActivities: nil)
        sheet.completionWithItemsHandler = { type, completed, _, _ in completions.append((type, completed)) }
        root.present(sheet, animated: false)
        _ = scene.advanceFrame(elapsed: 0.5)
        scene.layout(in: CGSize(width: 320, height: 480))
        #expect(requests.count == 1 && requests[0].items == ["Hello", "https://example.com"] && requests[0].files.map(\.mimeType) == ["image/png"])
        #expect(completions.count == 1 && completions[0].0 == nil && completions[0].1 == true)
        #expect(root.presentedViewController == nil)
        // Without a host sharer the sheet completes at once, not completed.
        scene.shareHandler = nil
        let again = UIActivityViewController(activityItems: ["x"], applicationActivities: nil)
        again.completionWithItemsHandler = { _, completed, _, _ in completions.append((nil, completed)) }
        root.present(again, animated: false)
        _ = scene.advanceFrame(elapsed: 0.5)
        scene.layout(in: CGSize(width: 320, height: 480))
        #expect(completions.last?.1 == false && root.presentedViewController == nil)
    }

    @Test func documentPickerOpensAndExports() {
        let (scene, root) = host()
        var opened: [HostFileOpenRequest] = []
        scene.fileOpenHandler = { request, completion in
            opened.append(request)
            completion([HostFile(data: Data("hello".utf8), name: "notes.txt", mimeType: "text/plain")])
        }
        let picks = Picks()
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.plainText, .json])
        picker.delegate = picks
        picker.allowsMultipleSelection = true
        root.present(picker, animated: false)
        _ = scene.advanceFrame(elapsed: 0.5)
        scene.layout(in: CGSize(width: 320, height: 480))
        #expect(opened.count == 1 && opened[0].extensions == ["txt", "json"] && opened[0].allowsMultiple && !opened[0].imagesOnly)
        #expect(picks.urls.count == 1 && picks.urls[0].lastPathComponent == "UIKitWeb-notes.txt")
        #expect(picks.urls.first.flatMap { try? String(contentsOf: $0, encoding: .utf8) } == "hello")
        #expect(root.presentedViewController == nil)
        // Exporting hands the file to the host's saver.
        var saved: [HostFile] = []
        scene.fileSaveHandler = { saved.append($0) }
        let export = UIDocumentPickerViewController(forExporting: picks.urls)
        export.delegate = picks
        root.present(export, animated: false)
        _ = scene.advanceFrame(elapsed: 0.5)
        scene.layout(in: CGSize(width: 320, height: 480))
        #expect(saved.count == 1 && saved[0].name == "UIKitWeb-notes.txt" && saved[0].mimeType == "text/plain")
        // No chooser on the host: cancelled.
        scene.fileOpenHandler = nil
        let none = UIDocumentPickerViewController(forOpeningContentTypes: [.png])
        none.delegate = picks
        root.present(none, animated: false)
        _ = scene.advanceFrame(elapsed: 0.5)
        scene.layout(in: CGSize(width: 320, height: 480))
        #expect(picks.cancelled == 1 && none.imagesOnly)
    }

    @Test func imagePickerPicksAnImage() {
        let (scene, root) = host()
        #expect(!UIImagePickerController.isSourceTypeAvailable(.photoLibrary) && !UIImagePickerController.isSourceTypeAvailable(.camera))
        scene.fileOpenHandler = { request, completion in
            #expect(request.imagesOnly && !request.allowsMultiple)
            completion([HostFile(data: Self.png, name: "photo.png", mimeType: "image/png")])
        }
        #expect(UIImagePickerController.isSourceTypeAvailable(.photoLibrary) && !UIImagePickerController.isSourceTypeAvailable(.camera))
        let picks = Picks()
        let picker = UIImagePickerController()
        picker.delegate = picks
        root.present(picker, animated: false)
        _ = scene.advanceFrame(elapsed: 0.5)
        scene.layout(in: CGSize(width: 320, height: 480))
        #expect(picks.images.count == 1 && picks.images[0].size == CGSize(width: 2, height: 2) && root.presentedViewController == nil)
        // The camera is never a source the hosts offer.
        let camera = UIImagePickerController()
        camera.sourceType = .camera
        camera.delegate = picks
        root.present(camera, animated: false)
        _ = scene.advanceFrame(elapsed: 0.5)
        scene.layout(in: CGSize(width: 320, height: 480))
        #expect(picks.cancelled == 1)
    }
}
