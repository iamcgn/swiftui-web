// SwiftUI and Foundation gaps Harbour's sweep found: a submit scope that blocks the enclosing
// submit action, `toolbar(removing:)` taking the sidebar toggle out of the bar, role-only
// buttons (iOS 26's close button), the glass styles as primitive styles, `SettingsLink`, a
// search with suggested tokens and a presentation binding, file representations of dropped
// items, `URL.formatted()` and the session flags apps set.
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless
import WebFoundation

#if !os(WASI)
@MainActor private final class Box { var count = 0; var text = ""; var tokens: [Token] = []; var presented = false }

private struct Token: Identifiable, Hashable { let id: String }

@Suite @MainActor struct HarbourSwiftUIGapsTests {
    private func runtime<V: View>(_ view: V, size: CGSize = CGSize(width: 480, height: 300)) -> Runtime {
        let runtime = Runtime()
        runtime.textEngine = MonospaceTextEngine()
        runtime.mount(view)
        runtime.layout(in: size)
        _ = runtime.render(scale: 2)
        return runtime
    }

    @Test func aBlockingSubmitScopeKeepsTheSubmitFromTheEnclosingAction() throws {
        let box = Box()
        let r = runtime(VStack {
            TextField("Blocked", text: .constant("")).submitScope()
            TextField("Open", text: .constant("")).submitScope(false)
        }.onSubmit { box.count += 1 })
        let fields = r.semanticsTree().filter { $0.role == .textField }
        let blocked = try #require(fields.first { $0.label == "Blocked" })
        let open = try #require(fields.first { $0.label == "Open" })
        r.textFieldDidSubmit(blocked.identifier)
        #expect(box.count == 0)
        r.textFieldDidSubmit(open.identifier)
        #expect(box.count == 1)
    }

    @Test func removingTheSidebarToggleTakesItOutOfTheBar() {
        func toggles(removing: Bool) -> Bool {
            let r = Runtime()
            r.textEngine = MonospaceTextEngine()
            r.paintsWindowChrome = true
            r.mount(NavigationSplitView {
                Text("Sidebar").toolbar(removing: removing ? .sidebarToggle : nil)
            } detail: {
                Text("Detail")
            })
            r.layout(in: CGSize(width: 640, height: 300))
            return r.semanticsTree().contains { $0.label == "Toggle Sidebar" }
        }
        #expect(toggles(removing: false))
        #expect(!toggles(removing: true))
    }

    @Test func aRoleOnlyButtonShowsTheRolesMarkAndRuns() throws {
        let box = Box()
        let r = runtime(VStack {
            Button(role: .close) { box.count += 1 }
            Button(role: .confirm) { box.count += 10 }
        })
        let close = try #require(r.semanticsTree().first { $0.label == "Close" })
        r.activate(semanticsIdentifier: close.identifier)
        #expect(box.count == 1)
        let confirm = try #require(r.semanticsTree().first { $0.label == "Done" })
        r.activate(semanticsIdentifier: confirm.identifier)
        #expect(box.count == 11)
    }

    @Test func glassStylesArePrimitiveAndRunTheirButtons() throws {
        let box = Box()
        // An app returns them as primitive styles, as Harbour's iOS 26 shim does.
        func glass() -> some PrimitiveButtonStyle { GlassButtonStyle() }
        let r = runtime(VStack {
            Button("Glass") { box.count += 1 }.buttonStyle(glass())
            Button("Prominent", role: .destructive) { box.count += 10 }.buttonStyle(.glassProminent)
        })
        let tree = r.semanticsTree()
        r.activate(semanticsIdentifier: try #require(tree.first { $0.label == "Glass" }).identifier)
        r.activate(semanticsIdentifier: try #require(tree.first { $0.label == "Prominent" }).identifier)
        #expect(box.count == 11)
        #expect(r.render(scale: 2).commands.map(\.description).contains { $0.hasPrefix("drawText(\"Glass\"") })
    }

    @Test func aSettingsLinkOpensTheSettings() throws {
        let box = Box()
        let r = runtime(VStack {
            SettingsLink()
            SettingsLink { Text("Preferences") }
        }.environment(\.openSettings, OpenSettingsAction { box.count += 1 }))
        let tree = r.semanticsTree()
        r.activate(semanticsIdentifier: try #require(tree.first { $0.label == "Preferences" }).identifier)
        #expect(box.count == 1)
        #expect(tree.contains { $0.label.hasPrefix("Settings") })
    }

    @Test func aSearchTakesSuggestedTokensAndAPresentationBinding() {
        let box = Box()
        let text = Binding(get: { box.text }, set: { box.text = $0 })
        let tokens = Binding(get: { box.tokens }, set: { box.tokens = $0 })
        let presented = Binding(get: { box.presented }, set: { box.presented = $0 })
        let r = runtime(NavigationStack {
            Text("List")
                .searchable(text: text, tokens: tokens, suggestedTokens: .constant([Token(id: "a")]), isPresented: presented,
                            placement: .automatic) { token in Text(token.id) }
                .searchable(text: text, tokens: tokens, suggestedTokens: .constant([]), prompt: "Find") { token in Text(token.id) }
                .contentTransition(.numericText(value: 3))
                .background(Material.regular)
        })
        #expect(r.semanticsTree().contains { $0.label == "List" })
    }

    #if !canImport(Darwin)
    @Test func aDroppedItemLoadsAsAFile() throws {
        let provider = NSItemProvider(item: Data("services: {}".utf8), typeIdentifier: UTType.yaml.identifier)
        var loaded: (URL?, Bool)?
        provider.loadInPlaceFileRepresentation(forTypeIdentifier: UTType.yaml.identifier) { url, inPlace, error in
            #expect(error == nil)
            loaded = (url, inPlace)
        }
        let url = try #require(loaded?.0)
        #expect(loaded?.1 == false)
        #expect(try Data(contentsOf: url) == Data("services: {}".utf8))
        var missing: (any Error)?
        provider.loadFileRepresentation(forTypeIdentifier: UTType.png.identifier) { _, error in missing = error }
        #expect(missing != nil)
    }
    #endif
}
#endif

// WebFoundation's URL and session configuration are wasm's; Apple's format and keep the flags
// the same way, and Linux's Foundation may have neither.
#if os(WASI) || canImport(Darwin)
@Suite struct URLFormattingTests {
    @Test func sessionsTakeTheirNetworkFlags() {
        let configuration = URLSessionConfiguration.default
        configuration.allowsConstrainedNetworkAccess = false
        configuration.allowsExpensiveNetworkAccess = false
        configuration.shouldUseExtendedBackgroundIdleMode = true
        #expect(!configuration.allowsConstrainedNetworkAccess && !configuration.allowsExpensiveNetworkAccess)
        #expect(configuration.shouldUseExtendedBackgroundIdleMode)
    }

    @Test func aURLFormatsWithoutItsQueryOrHTTPPort() throws {
        #expect(try #require(URL(string: "https://github.com/rrroyal/Harbour.git?ref=main#top")).formatted() == "https://github.com/rrroyal/Harbour.git")
        #expect(try #require(URL(string: "ssh://git.example.com:2222/repo")).formatted() == "ssh://git.example.com:2222/repo")
        #expect(try #require(URL(string: "https://example.com:443/a")).formatted() == "https://example.com/a")
    }
}
#endif
