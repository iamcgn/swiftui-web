// The system sheets inside a representable (uk-system-sheets): a hosted UIKit controller's
// share sheet and pickers reach the runtime's host services.
#if !os(WASI)
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless
import UIKit
import WebGraphics
import Foundation

@Suite @MainActor struct HostedSystemSheetTests {
    final class Screen: UIViewController, UIDocumentPickerDelegate {
        let status = UILabel()
        var picked: [URL] = []
        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .white
            var configuration = UIButton.Configuration.gray()
            configuration.title = "Share"
            let share = UIButton(configuration: configuration)
            share.frame = CGRect(x: 16, y: 16, width: 180, height: 36)
            share.addAction(UIAction { [weak self] _ in self?.share() }, for: .primaryActionTriggered)
            view.addSubview(share)
            var open = UIButton.Configuration.gray()
            open.title = "Open"
            let openButton = UIButton(configuration: open)
            openButton.frame = CGRect(x: 16, y: 68, width: 180, height: 36)
            openButton.addAction(UIAction { [weak self] _ in self?.open() }, for: .primaryActionTriggered)
            view.addSubview(openButton)
            status.text = "Nothing yet"
            status.frame = CGRect(x: 16, y: 120, width: 200, height: 20)
            view.addSubview(status)
        }
        func share() {
            let sheet = UIActivityViewController(activityItems: ["Shared text"], applicationActivities: nil)
            sheet.completionWithItemsHandler = { [weak self] _, completed, _, _ in self?.status.text = completed ? "Shared" : "Share unavailable" }
            present(sheet, animated: true)
        }
        func open() {
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.plainText])
            picker.delegate = self
            present(picker, animated: true)
        }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            picked = urls
            status.text = "Picked " + urls.map(\.lastPathComponent).joined(separator: ", ")
        }
    }

    struct Host: UIViewControllerRepresentable {
        let screen: Screen
        func makeUIViewController(context: Context) -> UIViewController { screen }
        func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
    }

    @Test func hostedSheetsReachTheRuntimeHost() {
        var environment = EnvironmentValues()
        environment.platformProfile = .iOS
        let runtime = Runtime(environment: environment)
        runtime.textEngine = RecordedTextEngine(entries: [:])
        var shares: [HostShareRequest] = []
        runtime.shareHandler = { shares.append($0) }
        runtime.fileOpenHandler = { _, completion in completion([HostFile(data: Data("hi".utf8), name: "a.txt", mimeType: "text/plain")]) }
        let screen = Screen()
        runtime.mount(Host(screen: screen))
        runtime.layout(in: CGSize(width: 320, height: 300))
        runtime.pointerDown(at: CGPoint(x: 100, y: 34))
        runtime.pointerUp(at: CGPoint(x: 100, y: 34))
        _ = runtime.advanceAnimations(elapsed: 0.5)
        runtime.layout(in: CGSize(width: 320, height: 300))
        #expect(shares.count == 1 && shares[0].items == ["Shared text"], "\(shares)")
        #expect(screen.status.text == "Shared")
        runtime.pointerDown(at: CGPoint(x: 100, y: 86))
        runtime.pointerUp(at: CGPoint(x: 100, y: 86))
        _ = runtime.advanceAnimations(elapsed: 0.5)
        runtime.layout(in: CGSize(width: 320, height: 300))
        #expect(screen.status.text == "Picked UIKitWeb-a.txt")
    }
}
#endif
