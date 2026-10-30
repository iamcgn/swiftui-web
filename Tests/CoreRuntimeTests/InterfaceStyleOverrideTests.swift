// Decision 0021 (Ember): the window's interface style override drives the colour scheme — an
// `onChange(of:initial:)` on the root sets it from an app-wide store while a full-screen cover
// (the onboarding) holds the control that changes the store; the cover follows at once.
import Testing
import SwiftUI
import SwiftUIWebHeadless
import SwiftUIWebUIKit
import UIKitWebCore

#if !os(WASI)
@Suite @MainActor struct InterfaceStyleOverrideTests {
    static let system13 = ResolvedFont(family: "system", size: 13, weight: .regular, italic: false, textStyle: nil)

    enum Appearance: Equatable { case system, light, dark
        var style: UIUserInterfaceStyle { switch self { case .system: .unspecified; case .light: .light; case .dark: .dark } }
    }
    @Observable final class Store {
        var appearance: Appearance = .system
        var onboarding = true
    }

    struct Cover: View {
        @Environment(Store.self) private var store
        var body: some View {
            VStack {
                Button("Dark") { store.appearance = .dark }._probe("dark")
                Button("Light") { store.appearance = .light }._probe("light")
                Button("System") { store.appearance = .system }._probe("system")
                Text("Cover").foregroundStyle(.primary)._probe("cover")
                // The cover reads the store too (Ember's picker shows the selection).
                Text(store.appearance == .dark ? "Dark" : "Light")
            }
        }
    }

    struct Root: View {
        @Environment(Store.self) private var store
        let runtime: Runtime
        var body: some View {
            Text("Feed").foregroundStyle(.primary)._probe("feed")
                .onChange(of: store.appearance, initial: true) { _, appearance in
                    // As Ember applies it: every window of every window scene.
                    for scene in UIApplication.shared.connectedScenes {
                        guard let windowScene = scene as? UIWindowScene else { continue }
                        for window in windowScene.windows { window.overrideUserInterfaceStyle = appearance.style }
                    }
                }
                .fullScreenCover(isPresented: Binding(get: { store.onboarding }, set: { store.onboarding = $0 })) {
                    Cover().environment(store)
                }
        }
    }

    private func press(_ r: Runtime, _ name: String) {
        let frame = r.probeFrames[name]!
        r.pointerDown(at: CGPoint(x: frame.midX, y: frame.midY)); r.pointerUp(at: CGPoint(x: frame.midX, y: frame.midY))
        r.layout(in: CGSize(width: 400, height: 300))
    }
    private func textInk(_ r: Runtime, _ word: String) -> String? {
        r.render(scale: 2).commands.map(\.description).first { $0.hasPrefix("drawText(\"\(word)\"") }.flatMap { c in c.range(of: "#").map { String(c[$0.lowerBound...].prefix(7)) } }
    }

    @Test func theFirstChangeThroughACoverReachesTheWindow() {
        let store = Store()
        let runtime = Runtime()
        var entries: [String: RecordedTextEngine.Entry] = [:]
        for word in ["Dark", "Light", "System", "Cover", "Feed"] { entries[RecordedTextEngine.key(font: Self.system13, width: nil, string: word)] = .init(width: 30, height: 16, firstBaseline: 13, lastBaseline: 13) }
        runtime.textEngine = RecordedTextEngine(entries: entries)
        UIKitScene.shared.removeAllWindows()
        runtime.mount(Root(runtime: runtime).environment(store))
        _SwiftUISceneWindow.install(for: runtime)
        #expect(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).count == 1)
        runtime.layout(in: CGSize(width: 400, height: 300))
        runtime.layout(in: CGSize(width: 400, height: 300))   // the initial onChange ran on the scheduler
        #expect(runtime.effectiveColorScheme == .light && runtime.hasPresentations)
        press(runtime, "dark")
        #expect(store.appearance == .dark)
        #expect(runtime.interfaceStyleOverride == .dark, "the root's onChange fired for the first change")
        #expect(runtime.effectiveColorScheme == .dark)
        #expect(textInk(runtime, "Cover") == "#FFFFFF", "the cover follows the scheme while open")
        #expect(textInk(runtime, "Feed") == "#FFFFFF")
        press(runtime, "system")
        #expect(runtime.interfaceStyleOverride == nil && runtime.effectiveColorScheme == .light)
        #expect(textInk(runtime, "Cover") == "#000000")
    }
}
#endif
