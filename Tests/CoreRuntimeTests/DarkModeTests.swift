// Phase 6: the dark appearance — system colours and control inks per colorScheme, the host's
// scheme, preferredColorScheme, and the window background hosts paint.
import Testing
import SwiftUI
import SwiftUIWebHeadless

#if !os(WASI)
@Suite @MainActor struct DarkModeTests {
    private static let body = ResolvedFont(family: "system", size: 13, weight: .regular, italic: false, textStyle: nil)

    private func makeRuntime(scheme: ColorScheme = .light) -> Runtime {
        var environment = EnvironmentValues()
        environment.colorScheme = scheme
        let runtime = Runtime(environment: environment)
        runtime.textEngine = RecordedTextEngine(entries: [
            RecordedTextEngine.key(font: Self.body, width: nil, string: "Hi"): .init(width: 12, height: 16, firstBaseline: 13, lastBaseline: 13),
        ])
        return runtime
    }

    private func render<V: View>(_ view: V, scheme: ColorScheme = .light, size: CGSize = CGSize(width: 200, height: 100)) -> [String] {
        let runtime = makeRuntime(scheme: scheme)
        runtime.mount(view)
        runtime.layout(in: size)
        return runtime.render(scale: 2).commands.map(\.description)
    }

    @Test func systemColoursFollowTheScheme() {
        var dark = EnvironmentValues()
        dark.colorScheme = .dark
        #expect(Color.blue.resolve(in: EnvironmentValues()) == RGBA(r: 0, g: 136, b: 255))
        #expect(Color.blue.resolve(in: dark) == RGBA(r: 0, g: 145, b: 255))
        #expect(Color.primary.resolve(in: dark) == RGBA(r: 255, g: 255, b: 255, a: 216.0 / 255))
        #expect(Color.secondary.resolve(in: dark) == RGBA(r: 255, g: 255, b: 255, a: 140.0 / 255))
        #expect(Color.accentColor.resolve(in: dark) == RGBA(r: 0, g: 122, b: 255))
        // Explicit components do not change.
        #expect(Color(red: 0.2, green: 0.4, blue: 0.6).resolve(in: dark) == RGBA(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
    }

    @Test func controlsUseTheDarkInk() {
        let light = render(Toggle("", isOn: .constant(false)).labelsHidden())
        let dark = render(Toggle("", isOn: .constant(false)).labelsHidden(), scheme: .dark)
        #expect(light.contains { $0.hasPrefix("fillPath") && $0.contains("#000000@") })
        #expect(dark.contains { $0.hasPrefix("fillPath") && $0.contains("#FFFFFF@") })
        // Text fields fill with the control background.
        #expect(render(TextField("", text: .constant("")), scheme: .dark).contains { $0.hasPrefix("fillRRect") && $0.hasSuffix("#1E1E1E") })
        // Text draws in the dark label colour.
        #expect(render(Text("Hi"), scheme: .dark).contains { $0.hasPrefix("drawText") && $0.contains("#FFFFFF@") })
    }

    @Test func preferredColorSchemeOverridesTheHost() {
        let runtime = makeRuntime()
        runtime.mount(Text("Hi").preferredColorScheme(.dark))
        runtime.layout(in: CGSize(width: 100, height: 50))
        #expect(runtime.effectiveColorScheme == .dark)
        #expect(runtime.render(scale: 2).commands.map(\.description).contains { $0.contains("#FFFFFF@") })
        // Back to the host's scheme when the preference goes away.
        runtime.mount(Text("Hi").preferredColorScheme(nil))
        runtime.layout(in: CGSize(width: 100, height: 50))
        #expect(runtime.effectiveColorScheme == .light)
        #expect(runtime.render(scale: 2).commands.map(\.description).contains { $0.contains("#000000@") })
    }

    @Test func hostSchemeChangesReResolveTheTree() {
        let runtime = makeRuntime()
        runtime.mount(VStack(spacing: 0) { Text("Hi"); Color.blue.frame(width: 10, height: 10) })
        runtime.layout(in: CGSize(width: 100, height: 100))
        #expect(runtime.render(scale: 2).commands.map(\.description).contains("fillRect(45, 53, 10, 10) #0088FF"))
        runtime.hostColorScheme = .dark
        #expect(runtime.needsFrame)
        runtime.layout(in: CGSize(width: 100, height: 100))
        let commands = runtime.render(scale: 2).commands.map(\.description)
        #expect(commands.contains("fillRect(45, 53, 10, 10) #0091FF"))
        #expect(commands.contains { $0.hasPrefix("drawText") && $0.contains("#FFFFFF@") })
    }

    @Test func hostsPaintTheWindowBackground() {
        let runtime = Runtime()
        runtime.paintsWindowBackground = true
        runtime.mount(Color.red.frame(width: 10, height: 10))
        runtime.layout(in: CGSize(width: 100, height: 50))
        #expect(runtime.render(scale: 2).commands.first?.description == "fillRect(0, 0, 100, 50) #FFFFFF")
        runtime.hostColorScheme = .dark
        runtime.layout(in: CGSize(width: 100, height: 50))
        #expect(runtime.render(scale: 2).commands.first?.description == "fillRect(0, 0, 100, 50) #1E1E1E")
    }
}
#endif
