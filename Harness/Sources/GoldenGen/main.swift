// GoldenGen: renders fixtures with Apple's SwiftUI in an AppKit window and writes the macOS
// goldens (the shared generation lives in GoldenKit; GoldenGenCatalyst is the iOS twin).
//   swift run GoldenGen --output ../Fixtures/Goldens [--filter text/]
import AppKit
import SwiftUI
import FixtureKit
import Fixtures
import GoldenKit

/// Hosts a view in an offscreen window so layout, preferences and drawing run exactly as in a
/// real app window (decision 0010: ImageRenderer resolves the default font differently).
@MainActor
final class AppKitHost: GoldenHost {
    private let collector = FrameCollector()
    private let hosting: NSHostingView<AnyView>
    private let window: NSWindow

    /// `Fixture.capturesWindow` on macOS (sw-mac-presentation-looks): the window is put on
    /// screen so sheets, alerts, popovers and menus present as separate windows; their frames
    /// relative to the window's content join the probes (`window.sheet`, `window.alert`,
    /// `window.popover`, `window.menu`) and their content views are composited into the
    /// capture at those frames. The panels' own chrome (glass, shadow, corners) belongs to the
    /// window server and needs screen recording to capture, so it stays out.
    private let capturesWindows: Bool

    init(_ view: AnyView, size: CGSize, colorScheme: ColorScheme, capturesWindows: Bool = false) {
        // A CLI process never becomes active, so the offscreen window is never key; controls
        // would draw their inactive look (grey prominent buttons). This is the environment
        // value SwiftUI reads for that, so set it as a key window would.
        let root = AnyView(Self.root(view, collector: collector, colorScheme: colorScheme).environment(\.controlActiveState, .key))
        hosting = NSHostingView(rootView: root)
        hosting.frame = CGRect(origin: .zero, size: size)
        self.capturesWindows = capturesWindows
        window = NSWindow(contentRect: CGRect(origin: CGPoint(x: 200, y: 200), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        // AppKit-backed controls follow the window's appearance, not the environment.
        window.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        window.contentView = hosting
        if capturesWindows {
            NSApplication.shared.setActivationPolicy(.regular)
            window.makeKeyAndOrderFront(nil)
        }
    }

    deinit {
        if capturesWindows { MainActor.assumeIsolated { window.orderOut(nil) } }
    }

    /// The presented windows: their kind by class, and their frames in the content's top-left space.
    private func presentedWindows() -> [(kind: String, window: NSWindow)] {
        guard capturesWindows else { return [] }
        return NSApp.windows.compactMap { presented in
            guard presented !== window, presented.isVisible else { return nil }
            let name = String(describing: type(of: presented))
            let kind = presented.isSheet && name.contains("Alert") ? "alert" : presented.isSheet ? "sheet" : name.contains("Popover") ? "popover" : name.contains("Menu") ? "menu" : "window"
            return (kind, presented)
        }
    }

    private func relativeFrame(of presented: NSWindow) -> CGRect {
        CGRect(x: presented.frame.minX - window.frame.minX, y: window.frame.maxY - presented.frame.maxY, width: presented.frame.width, height: presented.frame.height)
    }

    func settle() {
        guard capturesWindows else { return }
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))
    }

    func frames() -> [String: CGRect] {
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        var frames = collector.frames
        var counts: [String: Int] = [:]
        for (kind, presented) in presentedWindows() {
            counts[kind, default: 0] += 1
            let name = counts[kind]! == 1 ? "window.\(kind)" : "window.\(kind)\(counts[kind]!)"
            frames[name] = relativeFrame(of: presented)
        }
        return frames
    }

    func png(scale: Int) throws -> (data: Data, width: Int, height: Int) {
        let bounds = hosting.bounds
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(bounds.width) * scale, pixelsHigh: Int(bounds.height) * scale,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { throw NSError(domain: "GoldenGen", code: 1, userInfo: [NSLocalizedDescriptionKey: "no bitmap"]) }
        rep.size = bounds.size
        hosting.cacheDisplay(in: bounds, to: rep)
        let presented = presentedWindows()
        if !presented.isEmpty, let context = NSGraphicsContext(bitmapImageRep: rep) {
            // The presented windows' content over the main capture (flipped: y from the top).
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            for (_, presentedWindow) in presented {
                guard let content = presentedWindow.contentView, let panel = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { continue }
                content.cacheDisplay(in: content.bounds, to: panel)
                let frame = relativeFrame(of: presentedWindow)
                let image = NSImage(size: frame.size)
                image.addRepresentation(panel)
                // The bitmap context is unflipped: convert the top-left frame to bottom-left.
                let destination = CGRect(x: frame.minX, y: bounds.height - frame.maxY, width: frame.width, height: frame.height)
                image.draw(in: destination, from: .zero, operation: .sourceOver, fraction: 1)
            }
            NSGraphicsContext.restoreGraphicsState()
        }
        guard let png = rep.representation(using: .png, properties: [:]) else { throw NSError(domain: "GoldenGen", code: 2) }
        return (png, rep.pixelsWide, rep.pixelsHigh)
    }
}

/// The AppKit font behind a fixture font, for metrics layout cannot reveal (cap height).
func nsFont(_ font: FixtureFont) -> NSFont {
    let weights: [String: NSFont.Weight] = ["ultraLight": .ultraLight, "thin": .thin, "light": .light, "regular": .regular, "medium": .medium,
                                            "semibold": .semibold, "bold": .bold, "heavy": .heavy, "black": .black]
    let designs: [String: NSFontDescriptor.SystemDesign] = ["rounded": .rounded, "serif": .serif, "monospaced": .monospaced]
    let styles: [String: NSFont.TextStyle] = ["largeTitle": .largeTitle, "title": .title1, "title2": .title2, "title3": .title3, "headline": .headline,
                                              "subheadline": .subheadline, "body": .body, "callout": .callout, "footnote": .footnote,
                                              "caption": .caption1, "caption2": .caption2]
    var result: NSFont
    var design: String?
    switch font {
    case .system(let size, let weight, let d, _):
        result = NSFont.systemFont(ofSize: size, weight: weights[weight]!)
        design = d
    case .style(let name, let weight, let d, _, _):
        result = NSFont.preferredFont(forTextStyle: styles[name]!)
        if let weight { result = NSFont.systemFont(ofSize: result.pointSize, weight: weights[weight]!) }
        design = d
    case .custom(let name, let size, _, _):
        FixtureAssets.registerFonts()
        result = NSFont(name: name, size: size) ?? NSFont.systemFont(ofSize: size)
    }
    if let design, let systemDesign = designs[design], let descriptor = result.fontDescriptor.withDesign(systemDesign),
       let designed = NSFont(descriptor: descriptor, size: result.pointSize) {
        result = designed
    }
    return result
}

// The fixtures' bundled fonts (`Font.custom`) must be registered before anything renders.
FixtureAssets.registerFonts()

let platform = GoldenPlatform(profile: "macOS", host: "AppKit", subdirectory: "", fixturePlatform: .macOS,
                              makeHost: { view, size, scheme, capturesWindow in AppKitHost(view, size: size, colorScheme: scheme, capturesWindows: capturesWindow) },
                              fontMetrics: { fixtureFont in
                                  let font = nsFont(fixtureFont)
                                  return ["capHeight": Double(font.capHeight), "xHeight": Double(font.xHeight),
                                          "underlinePosition": Double(font.underlinePosition), "underlineThickness": Double(font.underlineThickness)]
                              })
let options = GoldenOptions(arguments: CommandLine.arguments)
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
Task { @MainActor in
    exit(Generator.run(options, platform: platform) == 0 ? 0 : 1)
}
app.run()
