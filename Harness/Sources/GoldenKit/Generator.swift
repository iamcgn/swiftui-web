// GoldenKit: golden generation shared by the AppKit host (`GoldenGen`, macOS goldens) and the
// UIKit host on Mac Catalyst (`GoldenGenCatalyst`, iOS goldens). A host puts a view in a real
// window (decision 0010), reports probe frames and rasterises; everything else is here.
// Output per fixture: image@2x.png, frames.json (probe frames, plus frames after each behaviour
// step), step-N@2x.png, meta.json; per platform text-metrics.json.
import SwiftUI
import FixtureKit
import Fixtures
import Foundation

public struct GoldenOptions {
    public var output = URL(fileURLWithPath: "../Fixtures/Goldens")
    public var filter: String? = nil

    public init(arguments: [String]) {
        var it = arguments.dropFirst().makeIterator()
        while let a = it.next() {
            switch a {
            case "--output": output = URL(fileURLWithPath: it.next()!)
            case "--filter": filter = it.next()
            default: fatalError("unknown argument \(a)")
            }
        }
    }
}

@MainActor
public final class FrameCollector: ObservableObject {
    public var frames: [String: CGRect] = [:]
    public init() {}
}

/// A view hosted in a real window: lays out on demand, reports the probe frames once preference
/// callbacks have delivered, and rasterises its contents. Kept alive across behaviour steps so
/// view state survives as it would on screen.
@MainActor
public protocol GoldenHost: AnyObject {
    func frames() -> [String: CGRect]
    /// Transparent background, sRGB PNG at `scale`.
    func png(scale: Int) throws -> (data: Data, width: Int, height: Int)
}

extension GoldenHost {
    /// The view every host puts in its window: the fixture root space, probe collection and
    /// the environment all goldens share.
    public static func root(_ view: AnyView, collector: FrameCollector, colorScheme: ColorScheme) -> AnyView {
        AnyView(view
            .coordinateSpace(name: fixtureRootSpace)
            .onPreferenceChange(ProbeKey.self) { collector.frames = $0 }
            .environment(\.locale, Locale(identifier: "en_US"))
            .environment(\.colorScheme, colorScheme)
            .dynamicTypeSize(.large)
            .transaction { $0.animation = nil })
    }
}

/// The platform a run's goldens describe.
public struct GoldenPlatform {
    /// The runtime profile name written into every meta.json (`PlatformProfile.name`).
    public let profile: String
    /// What hosted the views ("AppKit", "macCatalyst").
    public let host: String
    /// Where the platform's text-metrics.json lives under the goldens root ("" or "ios").
    public let subdirectory: String
    public let fixturePlatform: FixturePlatform
    public let makeHost: @MainActor (AnyView, CGSize, ColorScheme) -> any GoldenHost
    /// Font metrics layout cannot reveal: capHeight, xHeight, underlinePosition, underlineThickness.
    public let fontMetrics: @MainActor (FixtureFont) -> [String: Double]

    public init(profile: String, host: String, subdirectory: String, fixturePlatform: FixturePlatform,
                makeHost: @escaping @MainActor (AnyView, CGSize, ColorScheme) -> any GoldenHost,
                fontMetrics: @escaping @MainActor (FixtureFont) -> [String: Double]) {
        self.profile = profile; self.host = host; self.subdirectory = subdirectory; self.fixturePlatform = fixturePlatform
        self.makeHost = makeHost; self.fontMetrics = fontMetrics
    }
}

@MainActor
public enum Generator {
    static var platform: GoldenPlatform!

    static func collectFrames<V: View>(_ view: V, size: CGSize) -> [String: CGRect] {
        platform.makeHost(AnyView(view), size, .light).frames()
    }

    /// The SwiftUI view of a text request: its runs concatenated, with the layout modifiers applied.
    static func requestText(_ request: TextMetricRequest) -> Text {
        request.runs.map { Text($0.string).font($0.font.font) }.dropFirst().reduce(Text(request.runs[0].string).font(request.runs[0].font.font), +)
    }

    @ViewBuilder
    static func requestView(_ request: TextMetricRequest, id: String) -> some View {
        let options = request.options
        let base = requestText(request).kerning(options.kerning).tracking(options.tracking).probe(id)
            .textScale(.secondary, isEnabled: options.secondaryScale)
            .lineSpacing(options.lineSpacing)
            .truncationMode(options.truncation == "head" ? .head : options.truncation == "middle" ? .middle : .tail)
        // The same mapping SwiftUIWeb's View.lineLimit overloads perform, inverted.
        let limited: AnyView = {
            switch (options.lineLimit, options.minimumLines) {
            case (nil, 0): return AnyView(base)
            case (let limit?, 0): return AnyView(base.lineLimit(limit))
            case (nil, let minimum): return AnyView(base.lineLimit(minimum...))
            case (let limit?, let minimum) where limit == minimum: return AnyView(base.lineLimit(limit, reservesSpace: true))
            case (let limit?, let minimum): return AnyView(base.lineLimit(minimum...limit))
            }
        }()
        if let width = request.width {
            limited.frame(width: width, alignment: .topLeading)
        } else {
            limited
        }
    }

    /// Measures one text request: size plus first/last baseline. A 10×10 marker aligned on the
    /// baseline has its bottom on that baseline (non-text views' baseline guides are their bottom).
    static func measure(_ request: TextMetricRequest) -> [String: Double] {
        let canvas = CGSize(width: 2000, height: 2000)
        let view = VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                requestView(request, id: "text1")
                Color.clear.frame(width: 10, height: 10).probe("first")
            }
            HStack(alignment: .lastTextBaseline, spacing: 0) {
                requestView(request, id: "text2")
                Color.clear.frame(width: 10, height: 10).probe("last")
            }
        }
        .frame(width: canvas.width, height: canvas.height, alignment: .topLeading)
        let frames = collectFrames(view, size: canvas)
        guard let text1 = frames["text1"], let text2 = frames["text2"], let first = frames["first"], let last = frames["last"] else {
            fatalError("could not measure \(request.key)")
        }
        return ["width": text1.width, "height": text1.height,
                "firstBaseline": first.maxY - text1.minY, "lastBaseline": last.maxY - text2.minY]
    }

    /// Per-font values a text run contributes to stack spacing: distance to a non-text neighbour
    /// below and above, and to another text run of the same font below; line pitch and the
    /// unrounded line height; the platform's font metrics (cap height, decorations).
    static func measureFontSpacing(_ font: FixtureFont) -> [String: Double] {
        let canvas = CGSize(width: 2000, height: 2000)
        let view = HStack(alignment: .top, spacing: 50) {
            VStack(spacing: nil) {
                Text("Hg").font(font.font).probe("t1")
                Color.clear.frame(width: 10, height: 10).probe("b1")
            }
            VStack(spacing: nil) {
                Color.clear.frame(width: 10, height: 10).probe("b2")
                Text("Hg").font(font.font).probe("t2")
            }
            VStack(spacing: nil) {
                Text("Hg").font(font.font).probe("t3")
                Text("Hg").font(font.font).probe("t4")
            }
            HStack(spacing: nil) {
                Text("Hg").font(font.font).probe("t5")
                Text("Hg").font(font.font).probe("t6")
                Color.clear.frame(width: 10, height: 10).probe("b3")
            }
            // Thirteen lines: the pitch without line spacing, and with a large spacing, whose excess
            // over the spacing is the font's unrounded line height (pitch = max(pitch, unrounded +
            // spacing)). Twelve gaps keep the pixel rounding of the frame below 0.05 pt.
            Text(Array(repeating: "Hg", count: 13).joined(separator: "\n")).font(font.font).probe("many")
            Text(Array(repeating: "Hg", count: 13).joined(separator: "\n")).font(font.font).lineSpacing(50).probe("manySpaced")
        }
        .frame(width: canvas.width, height: canvas.height, alignment: .topLeading)
        let f = collectFrames(view, size: canvas)
        let lineHeight: Double = f["t1"]!.height
        let manyHeight: Double = f["many"]!.height, manySpacedHeight: Double = f["manySpaced"]!.height
        let linePitch: Double = (manyHeight - lineHeight) / 12
        let unroundedLineHeight: Double = (manySpacedHeight - lineHeight) / 12 - 50
        var result: [String: Double] = [
            "spacingBelow": f["b1"]!.minY - f["t1"]!.maxY,
            "spacingAbove": f["t2"]!.minY - f["b2"]!.maxY,
            "textToText": f["t4"]!.minY - f["t3"]!.maxY,
            "horizontalTextToText": f["t6"]!.minX - f["t5"]!.maxX,
            "horizontalTrailing": f["b3"]!.minX - f["t6"]!.maxX,
            "lineHeight": lineHeight,
            "linePitch": linePitch,
            "unroundedLineHeight": unroundedLineHeight,
        ]
        // Cap height, x-height and decoration metrics (underline below the baseline is negative,
        // as CoreText reports it).
        for (key, value) in platform.fontMetrics(font) { result[key] = value }
        return result
    }

    static var osVersion: String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
    }

    static func generateTextMetrics(into root: URL) throws {
        var entries: [String: [String: Double]] = [:]
        var fonts: [String: [String: Double]] = [:]
        var pending = TextMetricsRequests.all
        // A mixed-font request also records each of its parts alone: the headless engine places the
        // parts of a concatenation with those widths.
        for request in TextMetricsRequests.all where request.runs.count > 1 {
            pending += request.runs.map { TextMetricRequest($0.string, $0.font) }
        }
        for request in pending {
            entries[request.key] = measure(request)
            if request.width == nil {
                // Stacks probe minimum sizes with a zero-width proposal; record that layout too.
                let minimum = TextMetricRequest(runs: request.runs, width: 0, options: request.options)
                entries[minimum.key] = measure(minimum)
            }
            for font in request.fonts where fonts[font.key] == nil { fonts[font.key] = measureFontSpacing(font) }
        }
        let doc: [String: Any] = [
            "platformProfile": platform.profile,
            "host": platform.host,
            "macOS": osVersion,
            "entries": entries,
            "fonts": fonts,
        ]
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: doc, options: [.prettyPrinted, .sortedKeys])
            .write(to: root.appendingPathComponent("text-metrics.json"))
        print("\(platform.subdirectory.isEmpty ? "" : platform.subdirectory + "/")text-metrics.json: \(entries.count) entries, \(fonts.count) fonts")
    }

    /// Apple's `Path.description` for every shared path request (PathGoldenTests compares ours).
    static func generatePathGoldens(into root: URL) throws {
        var paths: [String: String] = [:]
        for request in PathRequests.all { paths[request.name] = request.make().description }
        let doc: [String: Any] = ["macOS": osVersion, "paths": paths]
        let dir = root.appendingPathComponent("shape", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: doc, options: [.prettyPrinted, .sortedKeys])
            .write(to: dir.appendingPathComponent("paths.json"))
        print("shape/paths.json: \(paths.count) paths")
    }

    static func framesDictionary(_ frames: [String: CGRect]) -> [String: [String: Double]] {
        var result: [String: [String: Double]] = [:]
        for (id, r) in frames {
            result[id] = ["x": r.minX, "y": r.minY, "width": r.width, "height": r.height]
        }
        return result
    }

    static func generate(_ fixture: Fixture, into root: URL) throws {
        let dir = root.appendingPathComponent(fixture.name, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // One hosted instance gives frames and pixels, before and after every behaviour step.
        FixtureAssets.appearance = fixture.colorScheme == .dark ? "dark" : "light"
        let instance = fixture.instantiate()
        let sized = instance.view.frame(width: fixture.size.width, height: fixture.size.height)
        let host = platform.makeHost(fixture.rasterized ? AnyView(sized.drawingGroup()) : AnyView(sized), fixture.size, fixture.colorScheme)
        let initialFrames = host.frames()
        let image = try host.png(scale: 2)
        try image.data.write(to: dir.appendingPathComponent("image@2x.png"))

        var steps: [[String: Any]] = []
        for (index, step) in instance.steps.enumerated() {
            step.run()
            let frames = host.frames()
            try host.png(scale: 2).data.write(to: dir.appendingPathComponent("step-\(index + 1)@2x.png"))
            steps.append(["name": step.name, "frames": framesDictionary(frames)])
        }

        // frames.json
        var framesDoc: [String: Any] = [
            "fixture": fixture.name,
            "size": ["width": fixture.size.width, "height": fixture.size.height],
            "frames": framesDictionary(initialFrames),
        ]
        if !steps.isEmpty { framesDoc["steps"] = steps }
        try JSONSerialization.data(withJSONObject: framesDoc, options: [.prettyPrinted, .sortedKeys])
            .write(to: dir.appendingPathComponent("frames.json"))

        // meta.json
        let swiftUIVersion = Bundle(identifier: "com.apple.SwiftUI")?.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let meta: [String: Any] = [
            "macOS": osVersion,
            "swiftUI": swiftUIVersion,
            "scale": 2,
            "generated": ISO8601DateFormatter().string(from: Date()),
            "platformProfile": platform.profile,
            "host": platform.host,
        ]
        try JSONSerialization.data(withJSONObject: meta, options: [.prettyPrinted, .sortedKeys])
            .write(to: dir.appendingPathComponent("meta.json"))
        let stepNote = steps.isEmpty ? "" : ", \(steps.count) step(s)"
        print("\(fixture.name): \(initialFrames.count) probe(s), \(image.width)x\(image.height)px\(stepNote)")
    }

    /// Generates everything `options` selects for `platform`; returns the number of failures.
    /// Text metrics go next to the platform's fixtures; path goldens are platform-independent
    /// and come from the macOS run.
    public static func run(_ options: GoldenOptions, platform: GoldenPlatform) -> Int {
        self.platform = platform
        var failures = 0
        let textRoot = platform.subdirectory.isEmpty ? options.output : options.output.appendingPathComponent(platform.subdirectory, isDirectory: true)
        let textPrefix = platform.subdirectory.isEmpty ? "text/" : platform.subdirectory + "/text/"
        if options.filter == nil || options.filter == textPrefix || options.filter == "text-metrics" {
            do { try generateTextMetrics(into: textRoot) }
            catch { failures += 1; FileHandle.standardError.write("FAILED text-metrics: \(error)\n".data(using: .utf8)!) }
        }
        if platform.fixturePlatform == .macOS, options.filter == nil || options.filter == "shape/" || options.filter == "shape-paths" {
            do { try generatePathGoldens(into: options.output) }
            catch { failures += 1; FileHandle.standardError.write("FAILED shape-paths: \(error)\n".data(using: .utf8)!) }
        }
        for fixture in AllFixtures.all where fixture.platform == platform.fixturePlatform && (options.filter.map({ fixture.name.hasPrefix($0) }) ?? true) {
            do { try generate(fixture, into: options.output) }
            catch { failures += 1; FileHandle.standardError.write("FAILED \(fixture.name): \(error)\n".data(using: .utf8)!) }
        }
        return failures
    }
}
