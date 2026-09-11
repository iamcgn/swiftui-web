// The UIKit pixel tier: every UIKit fixture laid out with the CoreText engine and painted by
// the substrate's CoreGraphics painter into a 2× bitmap that is compared with the golden PNG
// UIKit drew on the simulator (composited over white, a pixel differs when a channel is more
// than 32 off, at most `pixelTolerance` of the pixels may differ). `TIER_C_REPORT=1` prints the
// fraction per render; `TIER_C_DUMP=<dir>` writes every render there.
#if canImport(AppKit)
import AppKit
import Foundation
import Testing
import UIKit
import UIKitFixtureKit
import UIKitFixtures
import WebGraphicsNative

@Suite @MainActor struct UIKitPixelTests {
    static let pixelTolerance = 0.03
    /// Fixtures held to three times the tolerance: text-heavy ones, where CoreText's rendering of
    /// SF on macOS differs from the simulator's in antialiasing and line pitch (`label/wrapping`:
    /// 4.6 % with identical text and breaks).
    static let approximate: Set<String> = ["uikit/label/wrapping"]
    /// Fixtures compared by frames only (their look is not painted yet).
    /// The wheels date picker: a drum drawn approximately (Docs/elements/UIKit/DatePicker.md).
    static let framesOnly: Set<String> = ["uikit/datepicker/wheels"]

    nonisolated static var fixtureNames: [String] {
        let filter = ProcessInfo.processInfo.environment["TIER_C_FILTER"] ?? ""
        return AllUIKitFixtures.all.map(\.name).filter { $0.hasPrefix(filter) }
    }

    @Test(arguments: fixtureNames)
    func renderMatchesGolden(name: String) throws {
        let fixture = try #require(AllUIKitFixtures.all.first { $0.name == name })
        guard !Self.framesOnly.contains(name) else { return }
        let engine = CoreTextEngine()
        let painter = CoreGraphicsPainter(textEngine: engine, assetBase: Goldens.root.deletingLastPathComponent())
        let runner = UIKitFixtureRunner(fixture, textEngine: engine)
        try compare(runner, fixture: fixture, png: "image@2x.png", label: name, painter: painter)
        for (index, step) in fixture.stepNames.enumerated() {
            runner.apply(step: index)
            try compare(runner, fixture: fixture, png: "step-\(index + 1)@2x.png", label: "\(name)/\(step)", painter: painter)
        }
    }

    private func compare(_ runner: UIKitFixtureRunner, fixture: UIKitFixture, png: String, label: String, painter: CoreGraphicsPainter) throws {
        let file = Goldens.root.appendingPathComponent(fixture.name).appendingPathComponent(png)
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        let ground: UInt8 = fixture.style == .dark ? 0 : 255
        let golden = try #require(UIKitBitmap.golden(file, ground: ground), "\(label): unreadable golden \(png)")
        let ours = UIKitBitmap.render(runner.render(scale: 2), size: fixture.size, scale: 2, painter: painter, ground: ground)
        if let dump = ProcessInfo.processInfo.environment["TIER_C_DUMP"] {
            try ours.writePNG(to: URL(fileURLWithPath: dump).appendingPathComponent(label.replacingOccurrences(of: "/", with: "_") + ".png"))
        }
        let fraction = try #require(ours.differingFraction(from: golden), "\(label): size \(ours.width)x\(ours.height) vs \(golden.width)x\(golden.height)")
        let tolerance = Self.pixelTolerance * (Self.approximate.contains(fixture.name) ? 3 : 1)
        if ProcessInfo.processInfo.environment["TIER_C_REPORT"] != nil { print("UIKitTierC \(label) pixels=\(String(format: "%.2f", fraction * 100))%") }
        #expect(fraction <= tolerance, "\(label): \(String(format: "%.2f", fraction * 100)) % of pixels differ (limit \(String(format: "%.0f", tolerance * 100)) %)")
    }
}

/// An RGBA8 bitmap over a ground colour, for the render and for the golden.
struct UIKitBitmap {
    let width: Int, height: Int
    var data: [UInt8]

    private static func composite(_ data: inout [UInt8], over ground: UInt8) {
        var index = 0
        while index < data.count {
            let inverse = Int(255 - data[index + 3]) * Int(ground) / 255
            data[index] = UInt8(min(255, Int(data[index]) + inverse))
            data[index + 1] = UInt8(min(255, Int(data[index + 1]) + inverse))
            data[index + 2] = UInt8(min(255, Int(data[index + 2]) + inverse))
            data[index + 3] = 255
            index += 4
        }
    }

    @MainActor static func render(_ list: DisplayList, size: CGSize, scale: CGFloat, painter: CoreGraphicsPainter, ground: UInt8) -> UIKitBitmap {
        let width = Int((size.width * scale).rounded()), height = Int((size.height * scale).rounded())
        var data = [UInt8](repeating: 0, count: width * height * 4)
        data.withUnsafeMutableBytes { bytes in
            let ctx = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.translateBy(x: 0, y: CGFloat(height))
            ctx.scaleBy(x: scale, y: -scale)
            painter.paint(list, into: ctx)
        }
        composite(&data, over: ground)
        return UIKitBitmap(width: width, height: height, data: data)
    }

    static func golden(_ url: URL, ground: UInt8) -> UIKitBitmap? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        data.withUnsafeMutableBytes { bytes in
            let ctx = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        composite(&data, over: ground)
        return UIKitBitmap(width: width, height: height, data: data)
    }

    func writePNG(to url: URL) throws {
        var copy = data
        let image: CGImage? = copy.withUnsafeMutableBytes { bytes in
            CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        }
        guard let image, let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }

    func differingFraction(from other: UIKitBitmap) -> Double? {
        guard width == other.width, height == other.height else { return nil }
        var differing = 0
        var index = 0
        while index < data.count {
            let d = max(abs(Int(data[index]) - Int(other.data[index])), abs(Int(data[index + 1]) - Int(other.data[index + 1])),
                        abs(Int(data[index + 2]) - Int(other.data[index + 2])))
            if d > 32 { differing += 1 }
            index += 4
        }
        return Double(differing) / Double(width * height)
    }
}
#endif
