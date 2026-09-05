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

    init(_ view: AnyView, size: CGSize, colorScheme: ColorScheme) {
        // A CLI process never becomes active, so the offscreen window is never key; controls
        // would draw their inactive look (grey prominent buttons). This is the environment
        // value SwiftUI reads for that, so set it as a key window would.
        let root = AnyView(Self.root(view, collector: collector, colorScheme: colorScheme).environment(\.controlActiveState, .key))
        hosting = NSHostingView(rootView: root)
        hosting.frame = CGRect(origin: .zero, size: size)
        window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        // AppKit-backed controls follow the window's appearance, not the environment.
        window.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        window.contentView = hosting
    }

    func frames() -> [String: CGRect] {
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        return collector.frames
    }

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
    case .style(let name, let weight, let d, _):
        result = NSFont.preferredFont(forTextStyle: styles[name]!)
        if let weight { result = NSFont.systemFont(ofSize: result.pointSize, weight: weights[weight]!) }
        design = d
    }
    if let design, let systemDesign = designs[design], let descriptor = result.fontDescriptor.withDesign(systemDesign),
       let designed = NSFont(descriptor: descriptor, size: result.pointSize) {
        result = designed
    }
    return result
}

let platform = GoldenPlatform(profile: "macOS", host: "AppKit", subdirectory: "", fixturePlatform: .macOS,
                              makeHost: { AppKitHost($0, size: $1, colorScheme: $2) },
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
