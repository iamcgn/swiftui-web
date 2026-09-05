// GoldenGenCatalyst: renders the iOS fixtures (`ios/…`) with Apple's SwiftUI in a UIKit window
// on Mac Catalyst and writes their goldens under Fixtures/Goldens/ios. The Command Line Tools'
// SDK carries the Catalyst UIKit and SwiftUI (System/iOSSupport), so no Xcode or simulator is
// needed; the idiom is iPad (regular size class), which shares its controls and text styles with
// iPhone. UIKit only runs inside an app bundle with a bundle identifier, through
// UIApplicationMain: scripts/gen-goldens-ios.sh builds the bundle and runs it.
#if targetEnvironment(macCatalyst)
import UIKit
import SwiftUI
import FixtureKit
import Fixtures
import GoldenKit

/// Hosts a view in a UIKit window sized so the hosting view is exactly the fixture size (the
/// window's own title bar is outside it); the safe area is off so content fills the view.
@MainActor
final class UIKitHost: GoldenHost {
    private let collector = FrameCollector()
    private let controller: UIHostingController<AnyView>
    private let window: UIWindow
    private let size: CGSize

    init(_ view: AnyView, size: CGSize, colorScheme: ColorScheme) {
        self.size = size
        controller = UIHostingController(rootView: Self.root(view, collector: collector, colorScheme: colorScheme))
        controller.safeAreaRegions = []
        controller.view.backgroundColor = .clear
        window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        window.backgroundColor = .clear
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        // The window's content may be smaller than its frame (title bar): grow it by the difference.
        let actual = controller.view.bounds.size
        if actual != size {
            window.frame = CGRect(origin: .zero, size: CGSize(width: size.width + (size.width - actual.width), height: size.height + (size.height - actual.height)))
            controller.view.layoutIfNeeded()
        }
    }

    func frames() -> [String: CGRect] {
        controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        return collector.frames
    }

    func png(scale: Int) throws -> (data: Data, width: Int, height: Int) {
        let bounds = controller.view.bounds
        guard bounds.size == size else {
            throw NSError(domain: "GoldenGenCatalyst", code: 1, userInfo: [NSLocalizedDescriptionKey: "hosting view is \(bounds.size), fixture is \(size)"])
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = CGFloat(scale)
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: bounds.size, format: format)
        var drawn = false
        let image = renderer.image { _ in drawn = controller.view.drawHierarchy(in: bounds, afterScreenUpdates: true) }
        guard drawn, let png = image.pngData() else { throw NSError(domain: "GoldenGenCatalyst", code: 2, userInfo: [NSLocalizedDescriptionKey: "drawHierarchy failed"]) }
        return (png, Int(bounds.width) * scale, Int(bounds.height) * scale)
    }
}

/// The UIKit font behind a fixture font, for metrics layout cannot reveal.
func uiFont(_ font: FixtureFont) -> UIFont {
    let weights: [String: UIFont.Weight] = ["ultraLight": .ultraLight, "thin": .thin, "light": .light, "regular": .regular, "medium": .medium,
                                            "semibold": .semibold, "bold": .bold, "heavy": .heavy, "black": .black]
    let designs: [String: UIFontDescriptor.SystemDesign] = ["rounded": .rounded, "serif": .serif, "monospaced": .monospaced]
    let styles: [String: UIFont.TextStyle] = ["largeTitle": .largeTitle, "title": .title1, "title2": .title2, "title3": .title3, "headline": .headline,
                                              "subheadline": .subheadline, "body": .body, "callout": .callout, "footnote": .footnote,
                                              "caption": .caption1, "caption2": .caption2]
    var result: UIFont
    var design: String?
    switch font {
    case .system(let size, let weight, let d, _):
        result = UIFont.systemFont(ofSize: size, weight: weights[weight]!)
        design = d
    case .style(let name, let weight, let d, _):
        result = UIFont.preferredFont(forTextStyle: styles[name]!)
        if let weight { result = UIFont.systemFont(ofSize: result.pointSize, weight: weights[weight]!) }
        design = d
    }
    if let design, let systemDesign = designs[design], let descriptor = result.fontDescriptor.withDesign(systemDesign) {
        result = UIFont(descriptor: descriptor, size: result.pointSize)
    }
    return result
}

final class Delegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let platform = GoldenPlatform(profile: "iOS", host: "macCatalyst", subdirectory: "ios", fixturePlatform: .iOS,
                                      makeHost: { UIKitHost($0, size: $1, colorScheme: $2) },
                                      fontMetrics: { fixtureFont in
                                          let font = uiFont(fixtureFont)
                                          let ct = CTFontCreateWithFontDescriptor(font.fontDescriptor as CTFontDescriptor, font.pointSize, nil)
                                          return ["capHeight": Double(font.capHeight), "xHeight": Double(font.xHeight),
                                                  "underlinePosition": Double(CTFontGetUnderlinePosition(ct)), "underlineThickness": Double(CTFontGetUnderlineThickness(ct))]
                                      })
        let options = GoldenOptions(arguments: CommandLine.arguments)
        DispatchQueue.main.async {
            exit(Generator.run(options, platform: platform) == 0 ? 0 : 1)
        }
        return true
    }
}

_ = UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(Delegate.self))
#else
print("GoldenGenCatalyst renders the iOS goldens on Mac Catalyst: run scripts/gen-goldens-ios.sh")
#endif
