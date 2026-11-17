// The system environment values an iOS app reads (VoiceOver, button shapes, Always On, pixel
// length, the Bold Text weight) and the styling values their modifiers set.
import Testing
import SwiftUI
import SwiftUIWebHeadless

#if !os(WASI)
@MainActor private final class Seen { var values: [String] = [] }

private struct Reader: View {
    @Environment(\.badgeProminence) private var badge
    @Environment(\.buttonRepeatBehavior) private var repeating
    @Environment(\.springLoadingBehavior) private var springLoading
    @Environment(\.allowedDynamicRange) private var range
    @Environment(\.menuOrder) private var order
    @Environment(\.menuIndicatorVisibility) private var indicator
    @Environment(\.headerProminence) private var header
    @Environment(\.labelsVisibility) private var labels
    let seen: Seen
    var body: some View {
        let _ = seen.values = [
            badge == .increased ? "badge increased" : "badge standard",
            repeating == .enabled ? "repeat enabled" : "repeat automatic",
            springLoading == .disabled ? "spring disabled" : "spring automatic",
            range == .high ? "range high" : "range nil",
            order == .priority ? "order priority" : "order automatic",
            indicator == .hidden ? "indicator hidden" : "indicator automatic",
            header == .increased ? "header increased" : "header standard",
            labels == .hidden ? "labels hidden" : "labels automatic",
        ]
        return Text("Hi")
    }
}

@Suite @MainActor struct SystemEnvironmentTests {
    private static let body = ResolvedFont(family: "system", size: 13, weight: .regular, italic: false, textStyle: nil)

    private func mount<V: View>(_ view: V) {
        let runtime = Runtime()
        runtime.textEngine = RecordedTextEngine(entries: [RecordedTextEngine.key(font: Self.body, width: nil, string: "Hi"): .init(width: 16, height: 16, firstBaseline: 13, lastBaseline: 13)])
        runtime.mount(view)
        runtime.layout(in: CGSize(width: 200, height: 100))
    }

    @Test func systemSettingsReadAsAnIPhoneWithThemOff() {
        var values = EnvironmentValues()
        #expect(!values.accessibilityVoiceOverEnabled && !values.accessibilitySwitchControlEnabled)
        #expect(!values.accessibilityShowButtonShapes && !values.accessibilityDimFlashingLights)
        #expect(values.accessibilityPlayAnimatedImages)
        #expect(!values.accessibilityLargeContentViewerEnabled && !values.accessibilityAssistiveAccessEnabled)
        #expect(!values.isLuminanceReduced && !values.isSceneCaptured && values.appearsActive)
        #expect(values.legibilityWeight == .regular)
        #expect(values.backgroundProminence == .standard && values.backgroundMaterial == nil)
        #expect(values.defaultMinListHeaderHeight == nil && !values.contentTransitionAddsDrawingGroup)
        // One pixel at the display's scale.
        values.displayScale = 3
        #expect(values.pixelLength == 1.0 / 3)
        values.accessibilityVoiceOverEnabled = true
        values.legibilityWeight = .bold
        #expect(values.accessibilityVoiceOverEnabled && values.legibilityWeight == .bold)
    }

    @Test func modifiersSetTheirValues() {
        let plain = Seen()
        mount(Reader(seen: plain))
        #expect(plain.values == ["badge standard", "repeat automatic", "spring automatic", "range nil",
                                 "order automatic", "indicator automatic", "header standard", "labels automatic"])
        let set = Seen()
        mount(Reader(seen: set)
            .badgeProminence(.increased)
            .buttonRepeatBehavior(.enabled)
            .springLoadingBehavior(.disabled)
            .allowedDynamicRange(.high)
            .menuOrder(.priority)
            .menuIndicator(.hidden)
            .headerProminence(.increased)
            .labelsVisibility(.hidden))
        #expect(set.values == ["badge increased", "repeat enabled", "spring disabled", "range high",
                               "order priority", "indicator hidden", "header increased", "labels hidden"])
        // An image keeps itself under its own dynamic range modifier.
        #expect(Image("photo").allowedDynamicRange(.constrainedHigh) == Image("photo"))
    }
}
#endif
