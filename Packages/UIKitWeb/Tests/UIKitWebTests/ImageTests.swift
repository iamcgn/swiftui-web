// uk-images (Controls/UIImageView.swift): images from PNG and JPEG data (their size from the
// header, their bytes back from pngData / jpegData, a data URL for the painters), rendering
// modes and tints on image views, and animated images stepping on the scene's clock.
import Testing
import UIKit
@testable import UIKitWebCore
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif

@Suite @MainActor struct ImageTests {
    /// A 4 × 4 red and blue checker.
    static let checkerPNG = "iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAYAAACp8Z5+AAAAJ0lEQVR4nGO8o6Hxn4GBgcFHYwuIYmACk0iAUSPgDljFlhs+2FUAAEYLB4VoDJZLAAAAAElFTkSuQmCC"

    private func scene() -> UIKitScene {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        scene.textEngine = try! Goldens.textEngine()
        scene.configureScreen(size: CGSize(width: 320, height: 400), scale: 2)
        return scene
    }

    @Test func imagesFromData() throws {
        let png = try #require(Data(base64Encoded: Self.checkerPNG))
        let image = try #require(UIImage(data: png))
        #expect(image.size == CGSize(width: 4, height: 4) && image.scale == 1)
        #expect(UIImage(data: png, scale: 2)?.size == CGSize(width: 2, height: 2))
        #expect(image.pngData() == png && image.jpegData(compressionQuality: 0.8) == png)
        #expect(image.name.hasPrefix("data:image/png;base64,"))
        // A JPEG header: SOI, an APP0 segment, then a baseline frame of 300 × 200.
        var jpeg: [UInt8] = [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x04, 0x00, 0x00]
        jpeg += [0xFF, 0xC0, 0x00, 0x11, 0x08, 0x00, 0xC8, 0x01, 0x2C, 0x03]
        let fromJPEG = try #require(UIImage(data: Data(jpeg)))
        #expect(fromJPEG.size == CGSize(width: 300, height: 200) && fromJPEG.name.hasPrefix("data:image/jpeg"))
        #expect(fromJPEG.jpegData(compressionQuality: 1) == Data(jpeg) && fromJPEG.pngData() == nil)
        #expect(UIImage(data: Data([1, 2, 3])) == nil)
        let scene = scene()
        let view = UIImageView(image: image)
        #expect(view.frame.size == CGSize(width: 4, height: 4))
        view.frame = CGRect(x: 10, y: 10, width: 40, height: 40)
        let root = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        window.rootViewController = root
        window.makeKeyAndVisible()
        root.view.addSubview(view)
        scene.layout(in: CGSize(width: 320, height: 400))
        let draws = scene.render(scale: 2, background: false).commands.compactMap { command -> ImageDraw? in
            if case .drawImage(let draw) = command { return draw }
            return nil
        }
        #expect(draws.count == 1 && draws.first?.rect == CGRect(x: 10, y: 10, width: 40, height: 40) && draws.first?.file == image.name)
        #expect(draws.first?.pixelSize == CGSize(width: 4, height: 4))
        // A tint fills the image's alpha through the painter.
        view.image = image.withTintColor(.systemRed)
        let tinted = scene.render(scale: 2, background: false).commands.compactMap { command -> ImageDraw? in
            if case .drawImage(let draw) = command { return draw }
            return nil
        }
        #expect(tinted.first?.tint == UIColor.systemRed.rgba(for: .light))
    }

    @Test func animatedImagesStepOnTheClock() throws {
        let scene = scene()
        let png = try #require(Data(base64Encoded: Self.checkerPNG))
        let a = try #require(UIImage(data: png))
        let b = a.withTintColor(.systemBlue)
        let c = a.withTintColor(.systemGreen)
        let animated = try #require(UIImage.animatedImage(with: [a, b, c], duration: 0.3))
        #expect(animated.images?.count == 3 && animated.duration == 0.3 && animated.size == a.size)
        let view = UIImageView(image: animated)
        #expect(view.isAnimating)   // an animated image plays as soon as it is set
        #expect(view.currentFrame == a)
        _ = scene.advanceFrame(elapsed: 0.1)
        #expect(view.currentFrame == b)
        _ = scene.advanceFrame(elapsed: 0.1)
        #expect(view.currentFrame == c)
        _ = scene.advanceFrame(elapsed: 0.1)
        #expect(view.currentFrame == a)
        view.stopAnimating()
        #expect(!view.isAnimating && view.currentFrame == a)

        let frames = UIImageView(image: nil)
        frames.animationImages = [a, b]
        frames.animationDuration = 1
        frames.animationRepeatCount = 1
        #expect(!frames.isAnimating)
        frames.startAnimating()
        #expect(frames.isAnimating && scene.isAnimating)
        _ = scene.advanceFrame(elapsed: 0.5)
        #expect(frames.currentFrame == b)
        _ = scene.advanceFrame(elapsed: 0.6)
        #expect(!frames.isAnimating && frames.currentFrame == nil)   // one repeat done: back to `image`, which is nil
        frames.animationImages = nil
        #expect(frames.currentFrame == nil)
    }
}
