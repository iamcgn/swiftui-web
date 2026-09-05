// More of the iOS profile (Docs/elements/iOS.md): the bold trait per text style, progress
// views, and controls spacing like plain views. Frames against goldens are in GoldenFrameTests.
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless

#if !os(WASI)
@Suite @MainActor struct IOSControlsTests {
    private static let body = ResolvedFont(family: "system", size: 17, weight: .regular, italic: false, textStyle: .body, profile: "iOS")

    private func commands<V: View>(_ view: V) -> [String] {
        var environment = EnvironmentValues()
        environment.platformProfile = .iOS
        let runtime = Runtime(environment: environment)
        runtime.textEngine = RecordedTextEngine(entries: [
            RecordedTextEngine.key(font: Self.body, width: nil, string: "Hi"): .init(width: 16, height: 24.5, firstBaseline: 18, lastBaseline: 18),
        ])
        runtime.mount(view)
        runtime.layout(in: CGSize(width: 320, height: 300))
        return runtime.render(scale: 2).commands.map(\.description)
    }

    @Test func boldTraitWeightsPerStyle() {
        let profile = PlatformProfile.iOS
        #expect(profile.boldTraitWeight(for: .largeTitle) == .bold && profile.boldTraitWeight(for: .title) == .bold && profile.boldTraitWeight(for: .title2) == .bold)
        for style in [Font.TextStyle.title3, .headline, .subheadline, .body, .callout, .footnote, .caption, .caption2] {
            #expect(profile.boldTraitWeight(for: style) == .semibold, "\(style)")
        }
        #expect(PlatformProfile.macOS.boldTraitWeight(for: .headline) == .heavy)
    }

    @Test func progressViewsTakeTheIOSLook() {
        // A 4 pt accent pill on the grey track; no segment while indeterminate.
        let bar = commands(ProgressView(value: 0.5))
        #expect(bar.contains { $0.hasPrefix("fillRRect(0, 148, 320, 4) r=2 #78787D@0.2") })
        #expect(bar.contains { $0.hasPrefix("fillRRect(0, 148, 160, 4) r=2 #0088FF") })
        let indeterminate = commands(ProgressView().progressViewStyle(.linear))
        #expect(indeterminate.filter { $0.hasPrefix("fillRRect") }.count == 1)
        // The circular style is the 20 pt spinner even with a value.
        let ring = commands(ProgressView(value: 0.5).progressViewStyle(.circular)._probe("ring"))
        #expect(ring.filter { $0.hasPrefix("strokePath") }.count == 8)
        #expect(!ring.contains { $0.hasPrefix("strokePath(") && $0.contains("w=5") })
    }

    @Test func controlsSpaceLikePlainViewsUnderText() {
        var environment = EnvironmentValues()
        environment.platformProfile = .iOS
        let runtime = Runtime(environment: environment)
        runtime.textEngine = RecordedTextEngine(entries: [
            RecordedTextEngine.key(font: Self.body, width: nil, string: "Hi"): .init(width: 16, height: 24.5, firstBaseline: 18, lastBaseline: 18),
        ], fonts: [Self.body.key: .init(lineHeight: 24.5, spacingBelow: 14.54345703125, spacingAbove: 8.041515904562814, textToText: 2)])
        runtime.mount(VStack { Text("Hi")._probe("text"); Toggle("Hi", isOn: .constant(true))._probe("toggle"); Text("Hi")._probe("below") })
        runtime.layout(in: CGSize(width: 320, height: 300))
        let text = runtime.probeFrames["text"]!, toggle = runtime.probeFrames["toggle"]!, below = runtime.probeFrames["below"]!
        // ios/layout/controls: 14.54 (the body text's distance below) down to the toggle row,
        // 8.04 (its distance above) from the row to the next text.
        #expect(abs((toggle.minY - text.maxY) - 14.54345703125) < 1e-6)
        #expect(abs((below.minY - toggle.maxY) - 8.041515904562814) < 1e-6)
    }
}
#endif
