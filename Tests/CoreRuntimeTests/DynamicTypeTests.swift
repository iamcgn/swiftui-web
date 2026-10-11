// Dynamic Type (sw-dynamic-type, Docs/elements/Text.md): the iOS profile's text styles take
// their category's point size and key the recorded metrics by it, `@ScaledMetric` scales by the
// style's line-height ratio rounded to the display scale, the range form clamps, macOS ignores
// it all, and a host's text size reaches the root environment. The goldens hold the layouts
// (`ios/text/dynamic-*`, `text/dynamic-type`).
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless
import WebGraphics

#if !os(WASI)
@Suite @MainActor struct DynamicTypeTests {
    struct Scaled: View {
        @ScaledMetric(relativeTo: .body) var side: CGFloat = 20
        @ScaledMetric var plain: CGFloat = 10
        var body: some View {
            HStack(spacing: 0) {
                Color.red.frame(width: side, height: side)._probe("side")
                Color.blue.frame(width: plain, height: plain)._probe("plain")
            }
        }
    }

    private func runtime<V: View>(_ view: V, profile: PlatformProfile = .iOS) -> Runtime {
        var environment = EnvironmentValues()
        environment.platformProfile = profile
        let runtime = Runtime(environment: environment)
        runtime.textEngine = RecordedTextEngine(entries: [:])
        runtime.mount(view)
        runtime.layout(in: CGSize(width: 300, height: 300))
        return runtime
    }

    @Test func textStylesTakeTheCategorysPointSize() {
        let iOS = PlatformProfile.iOS
        #expect(Font.body.resolve(profile: iOS).size == 17 && Font.body.resolve(profile: iOS).sizeCategory == nil)
        let xxxLarge = Font.body.resolve(profile: iOS, dynamicTypeSize: .xxxLarge)
        #expect(xxxLarge.size == 23 && xxxLarge.sizeCategory == "XXXL" && xxxLarge.key == "style:body:XXXL")
        #expect(Font.largeTitle.resolve(profile: iOS, dynamicTypeSize: .accessibility5).size == 60)
        #expect(Font.caption2.resolve(profile: iOS, dynamicTypeSize: .xSmall).size == 11)   // the small styles stop at 11
        #expect(Font.title.bold().resolve(profile: iOS, dynamicTypeSize: .xLarge).key == "style:title:XL:w700")
        // Point-size fonts and macOS styles do not scale.
        #expect(Font.system(size: 20).resolve(profile: iOS, dynamicTypeSize: .accessibility5).size == 20)
        #expect(Font.body.resolve(profile: .macOS, dynamicTypeSize: .accessibility5).size == 13 && Font.body.resolve(profile: .macOS, dynamicTypeSize: .accessibility5).sizeCategory == nil)
        // The environment form reads the size from the environment.
        var environment = EnvironmentValues()
        environment.platformProfile = iOS
        environment.dynamicTypeSize = .accessibility1
        #expect(Font.headline.resolve(in: environment).size == 28)
    }

    @Test func scaledMetricFollowsTheLineHeightRatio() {
        // Measured on `ios/text/dynamic-*`: 20 relative to body is 17.5 at xSmall, 22 at xLarge,
        // 26.5 at xxxLarge and 51 at accessibility4 (the line-height ratio, to the half point).
        for (size, expected) in [(DynamicTypeSize.xSmall, CGFloat(17.5)), (.large, 20), (.xLarge, 22), (.xxxLarge, 26.5), (.accessibility4, 51)] {
            let r = runtime(Scaled().dynamicTypeSize(size))
            #expect(r.probeFrames["side"]?.width == expected, "\(size)")
        }
        #expect(runtime(Scaled().dynamicTypeSize(.accessibility4)).probeFrames["plain"]?.width == 25.5)
        // macOS has no Dynamic Type: the value stays (`text/dynamic-type`).
        #expect(runtime(Scaled().dynamicTypeSize(.accessibility5), profile: .macOS).probeFrames["side"]?.width == 20)
        // A coarser display scale rounds to its pixels.
        var environment = EnvironmentValues()
        environment.platformProfile = .iOS
        environment.displayScale = 1
        let coarse = Runtime(environment: environment)
        coarse.textEngine = RecordedTextEngine(entries: [:])
        coarse.mount(Scaled().dynamicTypeSize(.xSmall))
        coarse.layout(in: CGSize(width: 300, height: 300))
        #expect(coarse.probeFrames["side"]?.width == 17)
    }

    @Test func rangesClampAndNestedSizesWin() {
        var environment = EnvironmentValues()
        environment.dynamicTypeSize = .accessibility4
        let clamped = runtime(Scaled().dynamicTypeSize(...DynamicTypeSize.xLarge).dynamicTypeSize(.accessibility4))
        #expect(clamped.probeFrames["side"]?.width == 22)
        let below = runtime(Scaled().dynamicTypeSize(DynamicTypeSize.large...).dynamicTypeSize(.xSmall))
        #expect(below.probeFrames["side"]?.width == 20)
        let nested = runtime(Scaled().dynamicTypeSize(.xSmall).dynamicTypeSize(...DynamicTypeSize.xLarge).dynamicTypeSize(.accessibility4))
        #expect(nested.probeFrames["side"]?.width == 17.5)
        #expect(DynamicTypeSize.accessibility1.isAccessibilitySize && !DynamicTypeSize.xxxLarge.isAccessibilitySize && DynamicTypeSize.xSmall < .large)
    }

    @Test func theHostsTextSizeReachesTheEnvironment() {
        let r = runtime(Scaled())
        #expect(r.probeFrames["side"]?.width == 20)
        r.hostDynamicTypeSize = "XXXL"
        r.layout(in: CGSize(width: 300, height: 300))
        #expect(r.probeFrames["side"]?.width == 26.5)
        r.hostDynamicTypeSize = "nonsense"
        r.layout(in: CGSize(width: 300, height: 300))
        #expect(r.probeFrames["side"]?.width == 20)
        r.hostDisplayScale = 3
        r.hostDynamicTypeSize = "XS"
        r.layout(in: CGSize(width: 300, height: 300))
        #expect(abs((r.probeFrames["side"]?.width ?? 0) - 17.333333333333332) < 1e-9)
        #expect(DynamicTypeSize(_categoryName: "AXXXXL") == .accessibility5 && DynamicTypeSize(_categoryName: "x") == nil)
    }
}
#endif
