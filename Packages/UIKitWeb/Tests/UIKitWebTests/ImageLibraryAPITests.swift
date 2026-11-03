// The UIKit corners image libraries reach (Kingfisher): a button's background images, the
// pre-iOS 13 activity indicator styles, background tasks, and text attachments.
import Testing
import UIKit
@testable import UIKitWebCore
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif

@Suite @MainActor struct ImageLibraryAPITests {
    @Test func buttonBackgroundImagesPaintBehindTheTitle() throws {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        scene.textEngine = try Goldens.textEngine()
        scene.configureScreen(size: CGSize(width: 320, height: 400), scale: 2)
        let png = try #require(Data(base64Encoded: ImageTests.checkerPNG))
        let image = try #require(UIImage(data: png))
        let button = UIButton(type: .custom)
        button.frame = CGRect(x: 20, y: 30, width: 80, height: 40)
        button.setBackgroundImage(image, for: .normal)
        #expect(button.backgroundImage(for: .highlighted) === image && button.currentBackgroundImage === image)
        let root = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        window.rootViewController = root
        window.makeKeyAndVisible()
        root.view.addSubview(button)
        scene.layout(in: CGSize(width: 320, height: 400))
        let draws = scene.render(scale: 2, background: false).commands.compactMap { command -> ImageDraw? in
            if case .drawImage(let draw) = command { return draw }
            return nil
        }
        #expect(draws.count == 1 && draws.first?.rect == CGRect(x: 20, y: 30, width: 80, height: 40))
        button.setBackgroundImage(nil, for: .normal)
        #expect(button.currentBackgroundImage == nil)
    }

    @Test func olderIndicatorStylesAndBackgroundTasks() {
        #expect(UIActivityIndicatorView(style: .whiteLarge).frame.size == CGSize(width: 37, height: 37))
        #expect(UIActivityIndicatorView(style: .gray).frame.size == CGSize(width: 20, height: 20))
        #expect(UIActivityIndicatorView.Style.gray.rawValue == 2 && UIActivityIndicatorView.Style.white.rawValue == 1)

        let app = UIApplication.shared
        let first = app.beginBackgroundTask(withName: "cache") {}
        let second = app.beginBackgroundTask(expirationHandler: nil)
        #expect(first != .invalid && second != .invalid && first != second)
        app.endBackgroundTask(first)
        #expect(app.backgroundTimeRemaining > 60 * 60)
    }

    @Test func textAttachmentsHoldAnImage() throws {
        let png = try #require(Data(base64Encoded: ImageTests.checkerPNG))
        let attachment = NSTextAttachment(image: try #require(UIImage(data: png)))
        attachment.bounds = CGRect(x: 0, y: -2, width: 12, height: 12)
        let text = NSAttributedString(attachment: attachment)
        #expect(text.string == "\u{FFFC}" && text.length == 1)
        #expect((text.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment) === attachment)
        #expect(NSTextAttachment(data: Data([1]), ofType: "public.data").contents == Data([1]))
    }
}
