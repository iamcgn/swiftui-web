// GoldenGen: renders fixtures with Apple's SwiftUI and writes goldens.
//   swift run GoldenGen --output ../Fixtures/Goldens [--filter text/]
// Output per fixture: image@2x.png (ImageRenderer, scale 2), frames.json (probe frames), meta.json.
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

@MainActor
func fixtureRoot(_ fixture: Fixture, collector: FrameCollector) -> some View {
    fixture.content()
        .frame(width: fixture.size.width, height: fixture.size.height)
        .coordinateSpace(name: fixtureRootSpace)
        .onPreferenceChange(ProbeKey.self) { collector.frames = $0 }
        .environment(\.locale, Locale(identifier: "en_US"))
        .environment(\.colorScheme, .light)
        .dynamicTypeSize(.large)
        .transaction { $0.animation = nil }
}

@MainActor
func generate(_ fixture: Fixture, into root: URL) throws {
    let dir = root.appendingPathComponent(fixture.name, isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    // Frames: host in an offscreen window so layout and preferences run for real.
    let collector = FrameCollector()
    let hosting = NSHostingView(rootView: fixtureRoot(fixture, collector: collector))
    hosting.frame = CGRect(origin: .zero, size: fixture.size)
    let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = hosting
    hosting.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))   // let preference callbacks deliver

    // Pixels: ImageRenderer at scale 2, sRGB.
    let renderer = ImageRenderer(content: fixtureRoot(fixture, collector: collector))
    renderer.scale = 2
    renderer.proposedSize = ProposedViewSize(fixture.size)
    guard let cg = renderer.cgImage else { throw NSError(domain: "GoldenGen", code: 1, userInfo: [NSLocalizedDescriptionKey: "no image for \(fixture.name)"]) }
    let rep = NSBitmapImageRep(cgImage: cg)
    guard let png = rep.representation(using: .png, properties: [:]) else { throw NSError(domain: "GoldenGen", code: 2) }
    try png.write(to: dir.appendingPathComponent("image@2x.png"))

    // frames.json
    var frames: [String: [String: Double]] = [:]
    for (id, r) in collector.frames {
        frames[id] = ["x": r.minX, "y": r.minY, "width": r.width, "height": r.height]
    }
    let framesDoc: [String: Any] = [
        "fixture": fixture.name,
        "size": ["width": fixture.size.width, "height": fixture.size.height],
        "frames": frames,
    ]
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
    print("\(fixture.name): \(collector.frames.count) probe(s), \(cg.width)x\(cg.height)px")
}

let options = Options()
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
Task { @MainActor in
    var failures = 0
    for fixture in AllFixtures.all where options.filter.map({ fixture.name.hasPrefix($0) }) ?? true {
        do { try generate(fixture, into: options.output) }
        catch { failures += 1; FileHandle.standardError.write("FAILED \(fixture.name): \(error)\n".data(using: .utf8)!) }
    }
    exit(failures == 0 ? 0 : 1)
}
app.run()
