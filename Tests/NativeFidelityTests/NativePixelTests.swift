// Tier C: the native painter must reproduce Apple's goldens. Every enabled fixture is laid out
// with the CoreText engine (frames exact, like Tier A) and painted with `CoreGraphicsPainter`
// into a 2x bitmap that is compared pixel by pixel with the golden PNG the way Tier B compares
// browser renders (composited over white, a pixel differs when a channel is more than 32 off,
// at most 3 % of the pixels may differ). Symbol fixtures draw stand-in glyphs: frames only.
#if canImport(AppKit)
import AppKit
import Foundation
import Testing
import SwiftUI
import SwiftUIWebNative
import SwiftUIWebHeadless
import FixtureKit
import SwiftUIWebFixtures

struct NativeGoldenFrames: Decodable {
    struct Rect: Decodable { let x, y, width, height: Double }
    struct Step: Decodable { let name: String; let frames: [String: Rect] }
    let frames: [String: Rect]
    let steps: [Step]?
}

enum NativeGoldens {
    static let root: URL = {
        var url = URL(fileURLWithPath: #filePath)
        while url.lastPathComponent != "Tests" { url.deleteLastPathComponent() }
        url.deleteLastPathComponent()
        return url.appendingPathComponent("Fixtures/Goldens")
    }()

    static let enabledPrefixes = ["layout/", "paint/", "text/", "button/", "foreach/", "section/", "scroll/", "image/", "color/", "shape/", "toggle/", "label/", "textfield/", "list/", "nav/", "picker/", "slider/", "stepper/", "form/", "lifecycle/", "animation/", "presentation/", "customlayout/", "grid/", "canvas/", "observable/", "timeline/", "focus/", "accessibility/", "transform/", "gradient/", "menu/", "symbol/", "keyboard/", "progress/", "groupbox/", "labeledcontent/", "link/", "disclosure/", "lazy/", "tabview/", "unavailable/", "sharelink/", "splitview/", "gauge/", "datepicker/", "texteditor/", "table/", "colorpicker/", "effects/", "textstyle/", "dark/", "position/", "hover/", "toolbar/", "gesture/", "redacted/", "asyncimage/", "pressure/", "textscale/", "animator/", "matched/", "dragdrop/", "symboleffect/"]

    /// Fixtures whose browser render is held to a looser bound (font fallbacks); natively the
    /// fonts are real, but the bound is kept for parity with Tier B.
    /// `splitview/*`: Apple's capture drops the sidebar's rows and selection and fills the 8 pt
    /// bands beside the sidebar panel with a black-to-clear gradient (about 3.4 % of the window).
    static let approximate: Set<String> = ["text/system-fonts", "button/styles", "progress/indeterminate", "splitview/basic", "splitview/widths",
                                           "splitview/three", "splitview/columns", "splitview/sized", "splitview/selection", "splitview/visibility",
                                           "texteditor/basic"]   // NSTextView's tighter letters and wider spaces wrap one more word onto the first line
    /// Probes allowed two points (symbol sizes the metrics table scales to), as in Tier A.
    static let approximateProbes: [String: Set<String>] = [
        "symbol/basic": ["size24", "size40", "baselineText40", "largeSize24", "light", "black", "blue30", "chevronSemibold", "approximateRow", "stack"],
    ]
    static let pixelTolerance = 0.03
    /// Probes Apple reports but nothing reproduces (a hidden tab's stale frame), as in Tier A.
    static let ignoredProbes: [String: Set<String>] = [
        "tabview/basic/second": ["first"],
        "splitview/visibility": ["sidebar", "row1", "detail"],
        "splitview/visibility/detailOnly": ["sidebar", "row1", "detail"],
        "table/sorting/byCount": ["name2", "name3", "count2", "count3"],
    ]

    static func frames(for name: String) throws -> NativeGoldenFrames? {
        let file = root.appendingPathComponent(name).appendingPathComponent("frames.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try JSONDecoder().decode(NativeGoldenFrames.self, from: Data(contentsOf: file))
    }

    static func assets() throws -> AssetCatalog {
        try AssetCatalog(contentsOf: root.deletingLastPathComponent().appendingPathComponent("Assets.manifest.json"))
    }

    static var assetBase: URL { root.deletingLastPathComponent() }
}

/// An RGBA8 bitmap over white, for rendering and for the golden.
struct Bitmap {
    let width: Int, height: Int
    var data: [UInt8]

    /// Paints the list onto a transparent bitmap (as the harness captures a transparent window)
    /// and composites the result over white afterwards, like `golden`: blend modes that read
    /// the backdrop (`destinationOut`) then see the same transparency Apple's did.
    @MainActor static func render(_ list: DisplayList, size: CGSize, scale: CGFloat, painter: CoreGraphicsPainter) -> Bitmap {
        let width = Int((size.width * scale).rounded()), height = Int((size.height * scale).rounded())
        var data = [UInt8](repeating: 0, count: width * height * 4)
        data.withUnsafeMutableBytes { bytes in
            let ctx = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            // The bitmap's origin is at the bottom left: flip to the display list's y-down points.
            ctx.translateBy(x: 0, y: CGFloat(height))
            ctx.scaleBy(x: scale, y: -scale)
            painter.paint(list, into: ctx)
        }
        var index = 0
        while index < data.count {
            let inverse = 255 - Int(data[index + 3])
            data[index] = UInt8(min(255, Int(data[index]) + inverse))
            data[index + 1] = UInt8(min(255, Int(data[index + 1]) + inverse))
            data[index + 2] = UInt8(min(255, Int(data[index + 2]) + inverse))
            data[index + 3] = 255
            index += 4
        }
        return Bitmap(width: width, height: height, data: data)
    }

    /// The golden PNG composited over white.
    static func golden(_ url: URL) -> Bitmap? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 255, count: width * height * 4)
        data.withUnsafeMutableBytes { bytes in
            let ctx = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return Bitmap(width: width, height: height, data: data)
    }

    /// Writes the bitmap as a PNG (debugging: `TIER_C_DUMP`).
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

    /// The fraction of pixels differing by more than 32 in a channel, or nil for a size mismatch.
    func differingFraction(from other: Bitmap) -> Double? {
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

@Suite @MainActor struct NativePixelTests {
    /// `TIER_C_FILTER=<prefix>` restricts the run; `TIER_C_DUMP=<dir>` writes every render there.
    nonisolated static var fixtureNames: [String] {
        let filter = ProcessInfo.processInfo.environment["TIER_C_FILTER"] ?? ""
        return AllFixtures.all.filter { fixture in NativeGoldens.enabledPrefixes.contains { fixture.name.hasPrefix($0) } && fixture.name.hasPrefix(filter) }.map(\.name)
    }

    @Test(arguments: fixtureNames)
    func nativeRenderMatchesGolden(name: String) throws {
        let fixture = try #require(AllFixtures.all.first { $0.name == name })
        let golden = try #require(try NativeGoldens.frames(for: name), "missing golden for \(name)")
        let engine = CoreTextEngine()
        let painter = CoreGraphicsPainter(textEngine: engine, assetBase: NativeGoldens.assetBase)
        let runner = FixtureRunner(fixture, textEngine: engine, assets: try NativeGoldens.assets())
        let framesOnly = name.hasPrefix("symbol/") || name == "effects/shadow-offset"
        compare(runner.layoutFrames(), to: golden.frames, label: name)
        try comparePixels(runner, fixture: fixture, png: "image@2x.png", label: name, framesOnly: framesOnly, painter: painter)
        for (index, step) in (golden.steps ?? []).enumerated() where index < fixture.stepNames.count {
            runner.apply(step: index)
            // Like Tier B, compare once the step's animations have settled: the layout after the
            // step starts them, advancing runs them out.
            _ = runner.layoutFrames()
            var remaining = 20
            while remaining > 0, runner.runtime.advanceAnimations(elapsed: 1) || runner.runtime.advanceScrollAnimations(elapsed: 1) {
                remaining -= 1
                _ = runner.layoutFrames()
            }
            compare(runner.layoutFrames(), to: step.frames, label: "\(name)/\(step.name)")
            try comparePixels(runner, fixture: fixture, png: "step-\(index + 1)@2x.png", label: "\(name)/\(step.name)", framesOnly: framesOnly, painter: painter)
        }
    }

    private func compare(_ ours: [String: CGRect], to golden: [String: NativeGoldenFrames.Rect], label: String) {
        let approximate = NativeGoldens.approximateProbes[label] ?? []
        let ignored = NativeGoldens.ignoredProbes[label] ?? []
        for (id, expected) in golden.sorted(by: { $0.key < $1.key }) where !ignored.contains(id) {
            guard let actual = ours[id] else { Issue.record("\(label): probe \(id) not recorded"); continue }
            let tolerance = approximate.contains(id) ? 2 + 1e-9 : 1e-9
            // Text fixtures: CoreText's truncated widths land within the half point (Tier B's rule).
            let widthTolerance = label.hasPrefix("text/") ? max(tolerance, 0.5 + 1e-9, abs(expected.width) * 0.03) : tolerance
            let close = abs(actual.minX - expected.x) < widthTolerance && abs(actual.minY - expected.y) < tolerance
                && abs(actual.width - expected.width) < widthTolerance && abs(actual.height - expected.height) < tolerance
            #expect(close, "\(label)/\(id): \(actual) != (\(expected.x), \(expected.y), \(expected.width), \(expected.height))")
        }
    }

    private func comparePixels(_ runner: FixtureRunner, fixture: Fixture, png: String, label: String, framesOnly: Bool, painter: CoreGraphicsPainter) throws {
        guard !framesOnly else { return }
        let file = NativeGoldens.root.appendingPathComponent(fixture.name).appendingPathComponent(png)
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        let golden = try #require(Bitmap.golden(file), "\(label): unreadable golden \(png)")
        let ours = Bitmap.render(runner.runtime.render(scale: 2), size: fixture.size, scale: 2, painter: painter)
        if let dump = ProcessInfo.processInfo.environment["TIER_C_DUMP"] {
            try ours.writePNG(to: URL(fileURLWithPath: dump).appendingPathComponent(label.replacingOccurrences(of: "/", with: "_") + ".png"))
        }
        let fraction = try #require(ours.differingFraction(from: golden), "\(label): size \(ours.width)x\(ours.height) vs \(golden.width)x\(golden.height)")
        let tolerance = NativeGoldens.pixelTolerance * (NativeGoldens.approximate.contains(fixture.name) ? 3 : 1)
        if ProcessInfo.processInfo.environment["TIER_C_REPORT"] != nil { print("TierC \(label) pixels=\(String(format: "%.2f", fraction * 100))%") }
        #expect(fraction <= tolerance, "\(label): \(String(format: "%.2f", fraction * 100)) % of pixels differ (limit \(String(format: "%.0f", tolerance * 100)) %)")
    }
}
#endif
