// CGImage where it is WebGraphics's (Images/CGImage.swift, Images/ImageFiles.swift and
// UIKitWebCore's UIImageCG.swift and CGImageDrawing.swift): image file headers (PNG, JPEG with
// its EXIF orientation, animated GIF, WebP), the PNG encoder, CGImages from pixels, crops,
// UIImage's cgImage and orientations, drawing a CGImage into a context, an image context's
// makeImage, and a layer's CGImage contents. Apple's platforms keep CoreGraphics's CGImage.
#if !canImport(CoreGraphics) || os(WASI)
import Testing
import UIKit
@testable import UIKitWebCore
import WebGraphics
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif

@Suite @MainActor struct CGImageTests {
    /// A JPEG of 300 × 200 pixels whose EXIF orientation (6) turns it a quarter clockwise.
    static let turnedJPEG: [UInt8] = {
        var b: [UInt8] = [0xFF, 0xD8]
        // APP1 "Exif\0\0", then a big-endian TIFF block with one directory entry.
        let tiff: [UInt8] = [0x4D, 0x4D, 0x00, 0x2A, 0x00, 0x00, 0x00, 0x08,
                             0x00, 0x01, 0x01, 0x12, 0x00, 0x03, 0x00, 0x00, 0x00, 0x01, 0x00, 0x06, 0x00, 0x00,
                             0x00, 0x00, 0x00, 0x00]
        let app1 = Array("Exif".utf8) + [0, 0] + tiff
        b += [0xFF, 0xE1, UInt8((app1.count + 2) >> 8), UInt8((app1.count + 2) & 0xFF)] + app1
        b += [0xFF, 0xC0, 0x00, 0x11, 0x08, 0x00, 0xC8, 0x01, 0x2C, 0x03, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        return b
    }()

    /// A two-frame GIF89a of 3 × 2 pixels: 0.1 s then 0.05 s, looping forever.
    static let animatedGIF: [UInt8] = {
        var b = Array("GIF89a".utf8) + [3, 0, 2, 0, 0x00, 0, 0]
        b += [0x21, 0xFF, 0x0B] + Array("NETSCAPE2.0".utf8) + [0x03, 0x01, 0x00, 0x00, 0x00]
        for delay: UInt8 in [10, 5] {
            b += [0x21, 0xF9, 0x04, 0x00, delay, 0x00, 0x00, 0x00]
            b += [0x2C, 0, 0, 0, 0, 3, 0, 2, 0, 0x00, 0x02, 0x00]
        }
        return b + [0x3B]
    }()

    @Test func imageFileHeaders() throws {
        let png = _PNGEncoder.encode(width: 5, height: 3, rgba: [UInt8](repeating: 255, count: 60))
        let pngInfo = try #require(_ImageFileInfo(png))
        #expect(pngInfo.kind == .png && pngInfo.pixelWidth == 5 && pngInfo.pixelHeight == 3 && pngInfo.frameCount == 1)
        #expect(_ImageFileInfo.kind(of: png) == .png && _ImageFileInfo.kind(of: Self.turnedJPEG) == .jpeg)

        let jpeg = try #require(_ImageFileInfo(Self.turnedJPEG))
        #expect(jpeg.kind == .jpeg && jpeg.pixelWidth == 300 && jpeg.pixelHeight == 200 && jpeg.orientation == 6)
        #expect(jpeg.uprightPixelSize.width == 200 && jpeg.uprightPixelSize.height == 300)

        let gif = try #require(_ImageFileInfo(Self.animatedGIF))
        #expect(gif.kind == .gif && gif.pixelWidth == 3 && gif.pixelHeight == 2)
        #expect(gif.frameCount == 2 && gif.frameDelays == [0.1, 0.05] && gif.loopCount == 0)
        #expect(gif.kind.typeIdentifier == "com.compuserve.gif" && gif.kind.mimeType == "image/gif")

        // A lossless WebP: RIFF, then a VP8L chunk whose 14-bit fields hold width and height less one.
        let bits: UInt32 = UInt32(64 - 1) | UInt32(48 - 1) << 14
        var webp = Array("RIFF".utf8) + [0, 0, 0, 0] + Array("WEBP".utf8) + Array("VP8L".utf8) + [10, 0, 0, 0, 0x2F]
        webp += [UInt8(bits & 0xFF), UInt8((bits >> 8) & 0xFF), UInt8((bits >> 16) & 0xFF), UInt8(bits >> 24)]
        webp += [0, 0, 0, 0, 0, 0]
        let webpInfo = try #require(_ImageFileInfo(webp))
        #expect(webpInfo.kind == .webp && webpInfo.pixelWidth == 64 && webpInfo.pixelHeight == 48)
        #expect(_ImageFileInfo([1, 2, 3]) == nil)
    }

    @Test func pngEncoderStoresStraightAlphaRows() {
        // Opaque red, then blue at half alpha (premultiplied 128 → straight 255).
        let png = _PNGEncoder.encode(width: 2, height: 1, rgba: [255, 0, 0, 255, 0, 0, 128, 128])
        #expect(Array(png.prefix(8)) == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let row: [UInt8] = [0, 255, 0, 0, 255, 0, 0, 255, 128]
        #expect(png.indices.contains { start in start + row.count <= png.count && Array(png[start..<(start + row.count)]) == row })
        #expect(Array(png.suffix(12).prefix(8)) == [0, 0, 0, 0] + Array("IEND".utf8))
        #expect(Array(png.suffix(4)) == [0xAE, 0x42, 0x60, 0x82])   // IEND's CRC
    }

    @Test func imagesFromPixelsAndCrops() throws {
        // 2 × 2 BGRA (little-endian, alpha first): red, green / blue, clear.
        let bgra: [UInt8] = [0, 0, 255, 255, 0, 255, 0, 255, 255, 0, 0, 255, 0, 0, 0, 0]
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        let provider = try #require(CGDataProvider(data: Data(bgra)))
        let image = try #require(CGImage(width: 2, height: 2, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 8,
                                         space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info,
                                         provider: provider,
                                         decode: nil, shouldInterpolate: true, intent: .defaultIntent))
        #expect(image.width == 2 && image.height == 2 && image.bytesPerRow == 8 && image.alphaInfo == .premultipliedLast)
        #expect(image.dataProvider?.data == Data([255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 0, 0, 0, 0]))
        let right = try #require(image.cropping(to: CGRect(x: 1, y: 0, width: 5, height: 2)))
        #expect(right.width == 1 && right.height == 2 && right.dataProvider?.data == Data([0, 255, 0, 255, 0, 0, 0, 0]))
        #expect(image.cropping(to: CGRect(x: 4, y: 4, width: 2, height: 2)) == nil)
        let png = try #require(right._pngData)
        #expect(_ImageFileInfo(png)?.pixelWidth == 1 && _ImageFileInfo(png)?.pixelHeight == 2)
        // A cropped draw clips to the target and places the whole bitmap so the crop lands on it.
        let commands = right._commands(in: CGRect(x: 10, y: 10, width: 10, height: 20))
        #expect(commands.contains(.clipRect(CGRect(x: 10, y: 10, width: 10, height: 20))))
        #expect(commands.contains { if case .drawBitmap(_, let rect) = $0 { return rect == CGRect(x: 0, y: 10, width: 20, height: 20) } else { return false } })
    }

    @Test func uiImagesAndTheirCGImages() throws {
        let pixels = try #require(CGDataProvider(data: Data([255, 0, 0, 255, 0, 0, 255, 255])))
        let wide = try #require(CGImage(width: 2, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 8,
                                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(alphaInfo: .premultipliedLast),
                                        provider: pixels, decode: nil, shouldInterpolate: true, intent: .defaultIntent))
        let upright = UIImage(cgImage: wide)
        #expect(upright.size == CGSize(width: 2, height: 1) && upright.cgImage === wide)
        #expect(upright.pngData().flatMap { _ImageFileInfo($0) }?.pixelWidth == 2)
        let turned = UIImage(cgImage: wide, scale: 2, orientation: .right)
        #expect(turned.size == CGSize(width: 0.5, height: 1) && turned.imageOrientation == .right && turned.cgImage === wide)

        // An image from a turned JPEG shows upright, and its CGImage is the file's.
        let jpeg = try #require(UIImage(data: Data(Self.turnedJPEG)))
        #expect(jpeg.size == CGSize(width: 200, height: 300))
        let fromFile = try #require(jpeg.cgImage)
        #expect(fromFile.width == 200 && fromFile.height == 300 && fromFile.utType == "public.jpeg" && fromFile._fileData == Data(Self.turnedJPEG))

        // Orientations map the unturned pixels' corners onto the shown image's.
        let size = CGSize(width: 4, height: 2)
        #expect(CGPoint(x: 0, y: 0).applying(UIImage.Orientation.right.transform(for: size)) == CGPoint(x: 2, y: 0))
        #expect(CGPoint(x: 4, y: 0).applying(UIImage.Orientation.right.transform(for: size)) == CGPoint(x: 2, y: 4))
        #expect(CGPoint(x: 0, y: 0).applying(UIImage.Orientation.left.transform(for: size)) == CGPoint(x: 0, y: 4))
        #expect(CGPoint(x: 4, y: 2).applying(UIImage.Orientation.down.transform(for: size)) == CGPoint(x: 0, y: 0))
    }

    @Test func contextsDrawAndMakeImages() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 3), format: format)
        var made: CGImage?
        let pixels = try #require(CGDataProvider(data: Data([0, 0, 255, 255])))
        let dot = try #require(CGImage(width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 4,
                                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(alphaInfo: .premultipliedLast),
                                       provider: pixels, decode: nil, shouldInterpolate: true, intent: .defaultIntent))
        _ = renderer.image { context in
            let cg = context.cgContext
            #expect(cg.width == 8 && cg.height == 6 && cg.data == nil)
            cg.draw(dot, in: CGRect(x: 1, y: 1, width: 2, height: 1))
            made = cg.makeImage()
        }
        let image = try #require(made)
        #expect(image.width == 8 && image.height == 6)
        guard case .recording(let commands, let size, let scale) = image._content else { Issue.record("not a recording"); return }
        #expect(size == CGSize(width: 4, height: 3) && scale == 2)
        // CoreGraphics draws an image's first row at the rectangle's maximum y: the draw is flipped about it.
        #expect(commands.contains(.concat(CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: 3))))
        #expect(commands.contains { if case .drawBitmap(_, let rect) = $0 { return rect == CGRect(x: 1, y: 1, width: 2, height: 1) } else { return false } })
    }

    /// A bitmap context as CoreGraphics makes one (Nuke's decompression): pixels, y up from the
    /// bottom left, an image drawn into it comes out as `makeImage()`, and one asked to draw into
    /// caller memory, or with no pixels, is not made.
    @Test func bitmapContextsDrawUpwardAndMakeImages() throws {
        let ctx = try #require(CGContext(data: nil, width: 4, height: 3, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        #expect(ctx.width == 4 && ctx.height == 3 && ctx.data == nil)
        #expect(ctx.ctm == CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: 3))
        // The bottom row in CoreGraphics's space is the last row of the image.
        #expect(CGRect(x: 0, y: 0, width: 4, height: 1).applying(ctx.ctm) == CGRect(x: 0, y: 2, width: 4, height: 1))

        let pixels = try #require(CGDataProvider(data: Data([0, 0, 255, 255])))
        let dot = try #require(CGImage(width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 4,
                                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(alphaInfo: .premultipliedLast),
                                       provider: pixels, decode: nil, shouldInterpolate: true, intent: .defaultIntent))
        ctx.interpolationQuality = .high
        ctx.draw(dot, in: CGRect(x: 0, y: 0, width: 4, height: 3))
        let image = try #require(ctx.makeImage())
        #expect(image.width == 4 && image.height == 3)
        guard case .recording(let commands, let size, let scale) = image._content else { Issue.record("not a recording"); return }
        #expect(size == CGSize(width: 4, height: 3) && scale == 1)
        #expect(commands.contains { if case .drawBitmap = $0 { return true } else { return false } })

        var bytes = [UInt8](repeating: 0, count: 48)
        bytes.withUnsafeMutableBytes { buffer in
            #expect(CGContext(data: buffer.baseAddress, width: 4, height: 3, bitsPerComponent: 8, bytesPerRow: 16,
                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) == nil)
        }
        #expect(CGContext(data: nil, width: 0, height: 3, bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: 0) == nil)
    }

    @Test func layerContentsPaintByGravity() throws {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        scene.textEngine = try Goldens.textEngine()
        scene.configureScreen(size: CGSize(width: 320, height: 400), scale: 2)
        let png = _PNGEncoder.encode(width: 20, height: 10, rgba: [UInt8](repeating: 255, count: 800))
        let source = try #require(CGDataProvider(data: Data(png)))
        let file = try #require(CGImage(pngDataProviderSource: source, decode: nil,
                                        shouldInterpolate: true, intent: .defaultIntent))
        let view = UIView(frame: CGRect(x: 10, y: 20, width: 40, height: 40))
        view.layer.contents = file
        view.layer.contentsGravity = .resizeAspect
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
        #expect(draws.count == 1 && draws.first?.rect == CGRect(x: 10, y: 30, width: 40, height: 20))
        #expect(draws.first?.file.hasPrefix("data:image/png;base64,") == true)
        #expect(CALayer.contentsFrame(.center, natural: CGSize(width: 10, height: 10), in: CGRect(x: 0, y: 0, width: 40, height: 40))
                == CGRect(x: 15, y: 15, width: 10, height: 10))
    }
}
#endif
