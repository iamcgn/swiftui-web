// The system sheets (uk-system-sheets, Docs/elements/UIKit/Presentation.md): buttons that
// present the share sheet, the document picker and the image picker, and a status line that
// says what came back. The rest state is compared; `Playwright/uikit-sheets-probe.mjs`
// drives the browser's file input and Web Share on the gallery.
#if canImport(UIKit)
import UIKit
import UIKitFixtureKit
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

@MainActor final class SystemSheetModel: NSObject, UIDocumentPickerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    weak var presenter: UIViewController?
    let status = UILabel()

    func say(_ text: String) {
        status.text = text
        status.sizeToFit()
    }

    func share() {
        let sheet = UIActivityViewController(activityItems: ["Shared text", URL(string: "https://example.com")!], applicationActivities: nil)
        sheet.completionWithItemsHandler = { [weak self] _, completed, _, _ in self?.say(completed ? "Shared" : "Share unavailable") }
        presenter?.present(sheet, animated: true)
    }

    func pickDocument() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.plainText, .json])
        picker.delegate = self
        presenter?.present(picker, animated: true)
    }

    func pickImage() {
        let picker = UIImagePickerController()
        picker.delegate = self
        presenter?.present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        say("Picked " + urls.map(\.lastPathComponent).joined(separator: ", "))
    }
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { say("Cancelled") }
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        if let image = info[.originalImage] as? UIImage { say("Image \(Int(image.size.width)) × \(Int(image.size.height))") } else { say("No image") }
    }
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { say("Cancelled") }
}

final class SystemSheetController: UIViewController {
    let model = SystemSheetModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        model.presenter = self
        let titles = [("Share", "share"), ("Open document", "document"), ("Choose photo", "photo")]
        for (index, (title, probe)) in titles.enumerated() {
            var configuration = UIButton.Configuration.gray()
            configuration.title = title
            let button = UIButton(configuration: configuration)
            button.frame = CGRect(x: 16, y: 16 + CGFloat(index) * 52, width: 180, height: 36)
            button.addAction(UIAction { [weak self] _ in
                switch index {
                case 0: self?.model.share()
                case 1: self?.model.pickDocument()
                default: self?.model.pickImage()
                }
            }, for: .primaryActionTriggered)
            view.addSubview(button.probe(probe))
        }
        model.status.font = .systemFont(ofSize: 15)
        model.status.frame = CGRect(x: 16, y: 180, width: 288, height: 20)
        model.say("Nothing yet")
        view.addSubview(model.status.probe("status"))
    }
}

public enum SystemSheetFixtures {
    public static let all = [pickers]

    public static let pickers = UIKitFixture("uikit/sheets/pickers", size: CGSize(width: 320, height: 220)) {
        SystemSheetController()
    }
}
#endif
