// GoldenGen: renders fixtures with Apple's SwiftUI and writes goldens.
//   swift run GoldenGen --output ../Fixtures/Goldens [--filter text/]
// Output per fixture: image@2x.png (hosted window at scale 2), frames.json (probe frames, plus
// frames after each behaviour step), step-N@2x.png, meta.json.
import AppKit
import SwiftUI
import FixtureKit
import Fixtures

struct Options {
    var output = URL(fileURLWithPath: "../Fixtures/Goldens")
    var filter: String? = nil
    init() {
        var it = CommandLine.arguments.dropFirst().makeIterator()
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
final class FrameCollector: ObservableObject {
    var frames: [String: CGRect] = [:]
}

/// Hosts a view in an offscreen window so layout, preferences and drawing run exactly as in a
/// real app window (decision 0010: ImageRenderer resolves the default font differently). Kept
/// alive across behaviour steps so view state survives as it would on screen.
@MainActor
final class FrameHost {
    private let collector = FrameCollector()
    private let hosting: NSHostingView<AnyView>
    private let window: NSWindow

    init<V: View>(_ view: V, size: CGSize) {
        let collector = collector
        let root = view
            .coordinateSpace(name: fixtureRootSpace)
            .onPreferenceChange(ProbeKey.self) { collector.frames = $0 }
            .environment(\.locale, Locale(identifier: "en_US"))
            .environment(\.colorScheme, .light)
            .dynamicTypeSize(.large)
            .transaction { $0.animation = nil }
            // A CLI process never becomes active, so the offscreen window is never key; controls
            // would draw their inactive look (grey prominent buttons). This is the environment
            // value SwiftUI reads for that, so set it as a key window would.
            .environment(\.controlActiveState, .key)
        hosting = NSHostingView(rootView: AnyView(root))
        hosting.frame = CGRect(origin: .zero, size: size)
        window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
    }

    /// Lays out (again) and returns the probe frames once preference callbacks have delivered.
    func frames() -> [String: CGRect] {
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        return collector.frames
    }

    /// Rasterises the window contents at `scale`, transparent background, sRGB PNG.
    func png(scale: Int) throws -> (data: Data, width: Int, height: Int) {
        let bounds = hosting.bounds
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(bounds.width) * scale, pixelsHigh: Int(bounds.height) * scale,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { throw NSError(domain: "GoldenGen", code: 1, userInfo: [NSLocalizedDescriptionKey: "no bitmap"]) }
        rep.size = bounds.size
        hosting.cacheDisplay(in: bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { throw NSError(domain: "GoldenGen", code: 2) }
        return (png, rep.pixelsWide, rep.pixelsHigh)
    }
}

@MainActor
func collectFrames<V: View>(_ view: V, size: CGSize) -> [String: CGRect] {
    FrameHost(view, size: size).frames()
}

/// The SwiftUI view of a text request: its runs concatenated, with the layout modifiers applied.
func requestText(_ request: TextMetricRequest) -> Text {
    request.runs.map { Text($0.string).font($0.font.font) }.dropFirst().reduce(Text(request.runs[0].string).font(request.runs[0].font.font), +)
}

@ViewBuilder
func requestView(_ request: TextMetricRequest, id: String) -> some View {
    let options = request.options
    let base = requestText(request).probe(id)
        .lineSpacing(options.lineSpacing)
        .truncationMode(options.truncation == "head" ? .head : options.truncation == "middle" ? .middle : .tail)
    let limited: AnyView = {
        if let limit = options.lineLimit {
            return AnyView(options.reservesSpace ? AnyView(base.lineLimit(limit, reservesSpace: true)) : AnyView(base.lineLimit(limit)))
        }
        return AnyView(base)
    }()
    if let width = request.width {
        limited.frame(width: width, alignment: .topLeading)
    } else {
        limited
    }
}

/// Measures one text request: size plus first/last baseline. A 10×10 marker aligned on the
/// baseline has its bottom on that baseline (non-text views' baseline guides are their bottom).
@MainActor
func measure(_ request: TextMetricRequest) -> [String: Double] {
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
/// below and above, and to another text run of the same font below.
@MainActor
func measureFontSpacing(_ font: FixtureFont) -> [String: Double] {
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
    }
    .frame(width: canvas.width, height: canvas.height, alignment: .topLeading)
    let f = collectFrames(view, size: canvas)
    return [
        "spacingBelow": f["b1"]!.minY - f["t1"]!.maxY,
        "spacingAbove": f["t2"]!.minY - f["b2"]!.maxY,
        "textToText": f["t4"]!.minY - f["t3"]!.maxY,
        "horizontalTextToText": f["t6"]!.minX - f["t5"]!.maxX,
        "horizontalTrailing": f["b3"]!.minX - f["t6"]!.maxX,
        "lineHeight": f["t1"]!.height,
    ]
}

@MainActor
func generateTextMetrics(into root: URL) throws {
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
    let os = ProcessInfo.processInfo.operatingSystemVersion
    let doc: [String: Any] = [
        "platformProfile": "macOS",
        "macOS": "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
        "entries": entries,
        "fonts": fonts,
    ]
    try JSONSerialization.data(withJSONObject: doc, options: [.prettyPrinted, .sortedKeys])
        .write(to: root.appendingPathComponent("text-metrics.json"))
    print("text-metrics.json: \(entries.count) entries, \(fonts.count) fonts")
}

func framesDictionary(_ frames: [String: CGRect]) -> [String: [String: Double]] {
    var result: [String: [String: Double]] = [:]
    for (id, r) in frames {
        result[id] = ["x": r.minX, "y": r.minY, "width": r.width, "height": r.height]
    }
    return result
}

@MainActor
func generate(_ fixture: Fixture, into root: URL) throws {
    let dir = root.appendingPathComponent(fixture.name, isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    // One hosted instance gives frames and pixels, before and after every behaviour step.
    let instance = fixture.instantiate()
    let host = FrameHost(instance.view.frame(width: fixture.size.width, height: fixture.size.height), size: fixture.size)
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
    let os = ProcessInfo.processInfo.operatingSystemVersion
    let swiftUIVersion = Bundle(identifier: "com.apple.SwiftUI")?.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    let meta: [String: Any] = [
        "macOS": "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
        "swiftUI": swiftUIVersion,
        "scale": 2,
        "generated": ISO8601DateFormatter().string(from: Date()),
        "platformProfile": "macOS",
    ]
    try JSONSerialization.data(withJSONObject: meta, options: [.prettyPrinted, .sortedKeys])
        .write(to: dir.appendingPathComponent("meta.json"))
    let stepNote = steps.isEmpty ? "" : ", \(steps.count) step(s)"
    print("\(fixture.name): \(initialFrames.count) probe(s), \(image.width)x\(image.height)px\(stepNote)")
}

let options = Options()
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
Task { @MainActor in
    var failures = 0
    if options.filter == nil || options.filter == "text/" || options.filter == "text-metrics" {
        do { try generateTextMetrics(into: options.output) }
        catch { failures += 1; FileHandle.standardError.write("FAILED text-metrics: \(error)\n".data(using: .utf8)!) }
    }
    for fixture in AllFixtures.all where options.filter.map({ fixture.name.hasPrefix($0) }) ?? true {
        do { try generate(fixture, into: options.output) }
        catch { failures += 1; FileHandle.standardError.write("FAILED \(fixture.name): \(error)\n".data(using: .utf8)!) }
    }
    exit(failures == 0 ? 0 : 1)
}
app.run()
