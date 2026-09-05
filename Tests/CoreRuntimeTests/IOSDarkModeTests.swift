// The iOS profile's dark appearance (Docs/elements/iOS.md): black windows, text fields and
// plain lists, (28, 28, 30) grouped cards on a black ground, and the dark looks of the switch,
// the segmented picker and placeholders. Frames against goldens are in GoldenFrameTests (ios/dark/*).
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless

#if !os(WASI)
@Suite @MainActor struct IOSDarkModeTests {
    private static let body = ResolvedFont(family: "system", size: 17, weight: .regular, italic: false, textStyle: .body, profile: "iOS")

    private func runtime<V: View>(_ view: V, scheme: ColorScheme = .dark, size: CGSize = CGSize(width: 320, height: 300)) -> Runtime {
        var environment = EnvironmentValues()
        environment.colorScheme = scheme
        environment.platformProfile = .iOS
        let runtime = Runtime(environment: environment)
        runtime.textEngine = RecordedTextEngine(entries: [
            RecordedTextEngine.key(font: Self.body, width: nil, string: "Hi"): .init(width: 16, height: 24.5, firstBaseline: 18, lastBaseline: 18),
        ])
        runtime.mount(view)
        runtime.layout(in: size)
        return runtime
    }

    private func commands<V: View>(_ view: V, scheme: ColorScheme = .dark) -> [String] {
        runtime(view, scheme: scheme).render(scale: 2).commands.map(\.description)
    }

    @Test func thePaletteIsMacOSsAndTheBackgroundsAreIOSs() {
        var light = EnvironmentValues(); light.platformProfile = .iOS
        var dark = light; dark.colorScheme = .dark
        #expect(Color.blue.resolve(in: light) == RGBA(r: 0, g: 136, b: 255))
        #expect(Color.blue.resolve(in: dark) == RGBA(r: 0, g: 145, b: 255))
        #expect(light._windowBackground == .white && dark._windowBackground == .black)
        #expect(dark._controlBackground == .black)
        #expect(light._groupedCard == .white && dark._groupedCard == RGBA(r: 28, g: 28, b: 30))
        #expect(PlatformProfile.iOS.resolve(.groupedBackground, scheme: .light) == RGBA(r: 235, g: 236, b: 236))
        #expect(PlatformProfile.iOS.resolve(.groupedBackground, scheme: .dark) == .black)
        // macOS keeps its own greys.
        #expect(EnvironmentValues().platformProfile.resolve(.windowBackground, scheme: .dark) == RGBA(r: 30, g: 30, b: 30))
    }

    @Test func groupedListsPaintBlackGroundsAndDarkCards() {
        let list = commands(List { Text("Hi") })
        #expect(list.contains { $0.hasPrefix("fillRect(0, 0, 320, 300) #000000") })
        #expect(list.contains { $0.hasPrefix("fillPath") && $0.hasSuffix("#1C1C1E") })
        let plain = commands(List { Text("Hi") }.listStyle(.plain))
        #expect(plain.contains { $0.hasPrefix("fillRect(0, 0, 320, 300) #000000") })
    }

    @Test func controlsTakeTheirDarkLooks() {
        // The switch off track is white at 22 %, on stays the dark green.
        #expect(commands(Toggle("Hi", isOn: .constant(false))).contains { $0.hasPrefix("fillRRect") && $0.hasSuffix("#FFFFFF@0.22") })
        #expect(commands(Toggle("Hi", isOn: .constant(true))).contains { $0.hasPrefix("fillRRect") && $0.hasSuffix("#34C759") })
        // The selected segment is the measured translucent grey, not white.
        let segmented = commands(Picker("Hi", selection: .constant(1)) { Text("Hi").tag(1); Text("Hi").tag(2) }.pickerStyle(.segmented))
        #expect(segmented.contains { $0.hasPrefix("fillRRect") && $0.contains("#BFBFCC@") })
        // A placeholder is the iOS placeholder text; the field's fill is black.
        let field = commands(TextField("Hi", text: .constant("")).textFieldStyle(.roundedBorder))
        #expect(field.contains { $0.hasPrefix("drawText(\"Hi\"") && $0.contains("#EBEBF5@0.3") })
        #expect(field.contains { $0.hasPrefix("fillRRect") && $0.hasSuffix("#000000") })
    }

    @Test func anEmptyPlainFieldIsHalfAPointShorter() {
        #expect(runtime(TextField("Hi", text: .constant(""))._probe("f")).probeFrames["f"]?.height == 25)
        #expect(runtime(TextField("Hi", text: .constant("Hi"))._probe("f")).probeFrames["f"]?.height == 26)
    }
}
#endif
