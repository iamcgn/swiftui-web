// UIKitGoldenGen: renders the UIKit fixtures (`uikit/…`, Fixtures/UIKit) with Apple's UIKit in
// a window on Mac Catalyst and writes their goldens under Fixtures/Goldens/uikit: image@2x.png,
// frames.json (the probe views' frames in the fixture root's coordinates, plus the frames after
// each behaviour step), step-N@2x.png, meta.json; and uikit/text-metrics.json, every fixture
// string measured by a real UILabel plus each font's UIKit metrics, which UIKitWeb's headless
// text engine replays (decision 0014). Like GoldenGenCatalyst it runs inside an app bundle
// through UIApplicationMain: scripts/gen-goldens-uikit.sh builds the bundle and runs it.
#if os(iOS)
import UIKit
import UIKitFixtureKit
import UIKitFixtures

struct Options {
    var output = URL(fileURLWithPath: "../Fixtures/Goldens")
    var filter: String? = nil
    /// Prints each fixture's laid-out view tree (class, frame, fonts) instead of writing goldens:
    /// the geometry UIKit's controls build inside, which the frames alone do not show.
    var dump = false

    init(arguments: [String]) {
        var it = arguments.dropFirst().makeIterator()
        while let a = it.next() {
            switch a {
            case "--output": output = URL(fileURLWithPath: it.next()!)
            case "--filter": filter = it.next()
            case "--dump": dump = true
            default: fatalError("unknown argument \(a)")
            }
        }
    }
}

/// A fixture in a UIKit window sized so the root view is exactly the fixture size (the window's
/// own title bar is outside it). Kept alive across behaviour steps so view state survives.
@MainActor
final class Host {
    let instance: UIKitFixtureInstance
    private let window: UIWindow
    private let size: CGSize

    init(_ fixture: UIKitFixture) {
        size = fixture.size
        UIKitProbes.reset()
        instance = fixture.instantiate()
        window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.overrideUserInterfaceStyle = fixture.style
        window.traitOverrides.verticalSizeClass = .regular   // portrait screens whatever the fixture height
        window.backgroundColor = .clear
        window.rootViewController = instance.controller
        window.makeKeyAndVisible()
        instance.controller.view.layoutIfNeeded()
        // The window's content may be smaller than its frame (title bar): grow it by the difference.
        let actual = instance.controller.view.bounds.size
        if actual != size {
            window.frame = CGRect(origin: .zero, size: CGSize(width: size.width + (size.width - actual.width), height: size.height + (size.height - actual.height)))
            instance.controller.view.layoutIfNeeded()
        }
    }

    var root: UIView { instance.controller.view }

    func frames() -> [String: CGRect] {
        root.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        return UIKitProbes.frames(in: root)
    }

    /// Lets the animations a step started finish (goldens hold end states).
    func settle() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
    }

    func png(scale: Int) throws -> (data: Data, width: Int, height: Int) {
        let bounds = root.bounds
        guard bounds.size == size else {
            throw NSError(domain: "UIKitGoldenGen", code: 1, userInfo: [NSLocalizedDescriptionKey: "root view is \(bounds.size), fixture is \(size)"])
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = CGFloat(scale)
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: bounds.size, format: format)
        var drawn = false
        let image = renderer.image { _ in drawn = root.drawHierarchy(in: bounds, afterScreenUpdates: true) }
        guard drawn, let png = image.pngData() else { throw NSError(domain: "UIKitGoldenGen", code: 2, userInfo: [NSLocalizedDescriptionKey: "drawHierarchy failed"]) }
        return (png, Int(bounds.width) * scale, Int(bounds.height) * scale)
    }
}

@MainActor
enum Generator {
    static var osVersion: String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
    }

    /// A request measured as UIKitWeb's UILabel asks its text engine: the label's size to fit,
    /// its lines counted from the height, the baselines at the font's ascender per line.
    static func measure(_ request: UIKitTextRequest) -> [String: Double] {
        let label = UILabel()
        label.text = request.string
        label.font = request.font.uiFont
        label.numberOfLines = request.lines
        let size = label.sizeThatFits(CGSize(width: request.width ?? CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        let font = label.font!
        let lines = max(1, (size.height / font.lineHeight).rounded())
        return ["width": size.width, "height": size.height,
                "firstBaseline": font.ascender, "lastBaseline": font.ascender + font.lineHeight * (lines - 1)]
    }

    /// The font's UIKit metrics. `spacingBelow`, `spacingAbove` and `textToText` are SwiftUI
    /// stack distances that UIKit has no use for; they are written as 0 so the shared recorded
    /// engine can decode the file.
    static func fontMetrics(_ font: UIKitFixtureFont) -> [String: Double] {
        let f = font.uiFont
        return ["pointSize": f.pointSize, "ascender": f.ascender, "descender": f.descender, "lineHeight": f.lineHeight,
                "capHeight": f.capHeight, "xHeight": f.xHeight, "leading": f.leading,
                "spacingBelow": 0, "spacingAbove": 0, "textToText": 0]
    }

    static var hostName: String {
        #if targetEnvironment(macCatalyst)
        return "macCatalyst-UIKit"
        #else
        return "iPhoneSimulator \(UIDevice.current.systemVersion) \(UIDevice.current.name)"
        #endif
    }

    static func generateTextMetrics(into root: URL) throws {
        var entries: [String: [String: Double]] = [:]
        var fonts: [String: [String: Double]] = [:]
        for request in UIKitTextMetricsRequests.all { entries[request.key] = measure(request) }
        for font in UIKitTextMetricsRequests.fonts { fonts[font.key] = fontMetrics(font) }
        let doc: [String: Any] = [
            "platformProfile": "iOS",
            "host": hostName,
            "macOS": osVersion,
            "scale": Double(UIScreen.main.scale),
            "entries": entries,
            "fonts": fonts,
        ]
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: doc, options: [.prettyPrinted, .sortedKeys])
            .write(to: root.appendingPathComponent("text-metrics.json"))
        print("uikit/text-metrics.json: \(entries.count) entries, \(fonts.count) fonts")
    }

    static func framesDictionary(_ frames: [String: CGRect]) -> [String: [String: Double]] {
        var result: [String: [String: Double]] = [:]
        for (id, r) in frames {
            result[id] = ["x": r.minX, "y": r.minY, "width": r.width, "height": r.height]
        }
        return result
    }

    static func describe(_ view: UIView, depth: Int = 0) {
        var line = String(repeating: "  ", count: depth) + "\(type(of: view)) \(view.frame)"
        if let label = view as? UILabel {
            line += " font=\(label.font.fontName) \(label.font.pointSize) lines=\(label.numberOfLines) text=\"\(label.text ?? "")\""
        }
        if let button = view as? UIButton {
            line += " insets=\(button.contentEdgeInsets)"
            if let configuration = button.configuration { line += " configuration.contentInsets=\(configuration.contentInsets) cornerStyle=\(configuration.cornerStyle)" }
        }
        if let field = view as? UITextField { line += " font=\(field.font.map { "\($0.fontName) \($0.pointSize)" } ?? "nil") border=\(field.borderStyle.rawValue)" }
        if view.layer.cornerRadius != 0 { line += " cornerRadius=\(view.layer.cornerRadius)" }
        if let background = view.backgroundColor, background != .clear { line += " background=\(background)" }
        print(line)
        for subview in view.subviews { describe(subview, depth: depth + 1) }
    }

    static func dump(_ fixture: UIKitFixture) {
        let host = Host(fixture)
        _ = host.frames()
        print("== \(fixture.name)")
        describe(host.root)
    }

    /// The faces the recorder's fonts and the convenience constructors resolve to.
    static func dumpFonts() {
        print("== fonts")
        for font in UIKitTextMetricsRequests.fonts {
            let f = font.uiFont
            print("  \(font.key): \(f.fontName) \(f.pointSize) traits=\(f.fontDescriptor.symbolicTraits.rawValue) \(f.fontDescriptor.fontAttributes[.face] ?? "")")
        }
        for (name, f) in [("boldSystemFont(13)", UIFont.boldSystemFont(ofSize: 13)), ("systemFont(13, .bold)", UIFont.systemFont(ofSize: 13, weight: .bold)),
                          ("boldSystemFont(17)", UIFont.boldSystemFont(ofSize: 17)), ("systemFont(17, .bold)", UIFont.systemFont(ofSize: 17, weight: .bold)),
                          ("systemFont(13, .semibold)", UIFont.systemFont(ofSize: 13, weight: .semibold))] {
            let label = UILabel()
            label.font = f
            label.text = "Bold 13"
            let width = label.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)).width
            print("  \(name): \(f.fontName) traits=\(f.fontDescriptor.symbolicTraits.rawValue) \(f.fontDescriptor.fontAttributes[.face] ?? "") width(Bold 13)=\(width)")
        }
    }

    /// UIKit's metrics for the system font at every weight and size, and for every text style,
    /// with the height a one-line and a two-line UILabel takes in each (uikit/font-metrics.json;
    /// scripts/uikit-font-metrics-table.py turns it into UIFontMetricsTable.swift).
    static func generateFontMetrics(into root: URL) throws {
        func entry(_ font: UIFont) -> [String: Double] {
            let one = UILabel()
            one.font = font
            one.text = "Hg"
            let two = UILabel()
            two.font = font
            two.text = "Hg\nHg"
            two.numberOfLines = 0
            let huge = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            return ["pointSize": font.pointSize, "ascender": font.ascender, "descender": font.descender, "leading": font.leading,
                    "lineHeight": font.lineHeight, "capHeight": font.capHeight, "xHeight": font.xHeight,
                    "labelHeight": one.sizeThatFits(huge).height, "twoLineHeight": two.sizeThatFits(huge).height]
        }
        var systemFonts: [String: [String: [String: Double]]] = [:]
        for (name, weight) in UIKitFixtureFont.weights {
            var sizes: [String: [String: Double]] = [:]
            for size in 6...72 { sizes["\(size)"] = entry(UIFont.systemFont(ofSize: CGFloat(size), weight: weight.0)) }
            systemFonts[name] = sizes
        }
        var textStyles: [String: [String: Double]] = [:]
        for (name, style) in UIKitFixtureFont.styles { textStyles[name] = entry(UIFont.preferredFont(forTextStyle: style)) }
        let doc: [String: Any] = [
            "host": hostName,
            "macOS": osVersion,
            "scale": Double(UIScreen.main.scale),
            "systemFonts": systemFonts,
            "textStyles": textStyles,
        ]
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: doc, options: [.prettyPrinted, .sortedKeys])
            .write(to: root.appendingPathComponent("font-metrics.json"))
        print("uikit/font-metrics.json: \(systemFonts.count) weights × 67 sizes, \(textStyles.count) text styles")
    }

    static func generate(_ fixture: UIKitFixture, into root: URL) throws {
        let dir = root.appendingPathComponent(fixture.name, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let host = Host(fixture)
        let initialFrames = host.frames()
        let image = try host.png(scale: 2)
        try image.data.write(to: dir.appendingPathComponent("image@2x.png"))

        var steps: [[String: Any]] = []
        for (index, step) in host.instance.steps.enumerated() {
            step.run()
            host.settle()
            let frames = host.frames()
            try host.png(scale: 2).data.write(to: dir.appendingPathComponent("step-\(index + 1)@2x.png"))
            steps.append(["name": step.name, "frames": framesDictionary(frames)])
        }

        var framesDoc: [String: Any] = [
            "fixture": fixture.name,
            "size": ["width": fixture.size.width, "height": fixture.size.height],
            "frames": framesDictionary(initialFrames),
        ]
        if !steps.isEmpty { framesDoc["steps"] = steps }
        try JSONSerialization.data(withJSONObject: framesDoc, options: [.prettyPrinted, .sortedKeys])
            .write(to: dir.appendingPathComponent("frames.json"))

        let uiKitVersion = Bundle(identifier: "com.apple.UIKit")?.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let meta: [String: Any] = [
            "macOS": osVersion,
            "uiKit": uiKitVersion,
            "scale": 2,
            "generated": ISO8601DateFormatter().string(from: Date()),
            "platformProfile": "iOS",
            "host": hostName,
        ]
        try JSONSerialization.data(withJSONObject: meta, options: [.prettyPrinted, .sortedKeys])
            .write(to: dir.appendingPathComponent("meta.json"))
        let stepNote = steps.isEmpty ? "" : ", \(steps.count) step(s)"
        print("\(fixture.name): \(initialFrames.count) probe(s), \(image.width)x\(image.height)px\(stepNote)")
    }

    /// Generates everything `options` selects; returns the number of failures.
    static func run(_ options: Options) -> Int {
        var failures = 0
        if options.dump {
            dumpFonts()
            for fixture in AllUIKitFixtures.all where options.filter.map({ fixture.name.hasPrefix($0) }) ?? true { dump(fixture) }
            return 0
        }
        let uikitRoot = options.output.appendingPathComponent("uikit", isDirectory: true)
        if options.filter == nil || options.filter == "uikit/text/" || options.filter == "text-metrics" {
            do { try generateTextMetrics(into: uikitRoot) }
            catch { failures += 1; FileHandle.standardError.write("FAILED text-metrics: \(error)\n".data(using: .utf8)!) }
        }
        if options.filter == nil || options.filter == "font-metrics" {
            do { try generateFontMetrics(into: uikitRoot) }
            catch { failures += 1; FileHandle.standardError.write("FAILED font-metrics: \(error)\n".data(using: .utf8)!) }
        }
        for fixture in AllUIKitFixtures.all where options.filter.map({ fixture.name.hasPrefix($0) }) ?? true {
            do { try generate(fixture, into: options.output) }
            catch { failures += 1; FileHandle.standardError.write("FAILED \(fixture.name): \(error)\n".data(using: .utf8)!) }
        }
        return failures
    }
}

final class Delegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let options = Options(arguments: CommandLine.arguments)
        DispatchQueue.main.async {
            exit(Generator.run(options) == 0 ? 0 : 1)
        }
        return true
    }
}

_ = UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(Delegate.self))
#else
print("UIKitGoldenGen renders the UIKit goldens on Mac Catalyst: run scripts/gen-goldens-uikit.sh")
#endif
