import SwiftUI
import SwiftUIWebCanvas
import SwiftUIWebFixtures
import FixtureKit
#if os(WASI)
import JavaScriptKit
import JavaScriptEventLoop

/// Minimal percent-decoding (no Foundation on wasm).
func percentDecoded(_ s: String) -> String {
    var bytes: [UInt8] = []
    var iterator = Array(s.utf8).makeIterator()
    while let b = iterator.next() {
        if b == UInt8(ascii: "%"), let h = iterator.next(), let l = iterator.next(),
           let value = UInt8(String(decoding: [h, l], as: UTF8.self), radix: 16) {
            bytes.append(value)
        } else if b == UInt8(ascii: "+") {
            bytes.append(UInt8(ascii: " "))
        } else {
            bytes.append(b)
        }
    }
    return String(decoding: bytes, as: UTF8.self)
}

/// The fixture named by `?fixture=` in a query string, if any.
func requestedFixture(in search: String) -> String? {
    let query = search.dropFirst().split(separator: "&").map { $0.split(separator: "=", maxSplits: 1).map(String.init) }
    return query.first { $0.first == "fixture" }?.last.map(percentDecoded)
}

/// Three panes: every fixture listed on the left (`#list`); the code that declares the selected
/// one in the middle (`#code`, from the generated `FixtureSources`, highlighted by highlight.js
/// when the CDN is reachable); and its preview on the right (`#app`, sized to the fixture) with
/// its behaviour steps as buttons. Selecting a fixture updates the URL (`?fixture=<name>`) without
/// reloading, so links stay shareable and the Tier B job (`Playwright/tier-b.mjs`) can still open
/// one fixture per navigation.
@MainActor
final class Gallery {
    private let document = JSObject.global.document.object!
    private let list: JSObject
    private let filter: JSObject
    private let title: JSObject
    private let steps: JSObject
    private let app: JSObject
    private let code: JSObject
    private let gutter: JSObject
    private let band: JSObject
    private let codePane: JSObject
    private let codeFile: JSObject
    private let modes: JSObject
    private var host: CanvasHost?
    private var instance: FixtureInstance?
    private var source: FixtureSource?
    private var wholeFile = false
    private var closures: [JSClosure] = []
    private let lineHeight = 18.0   // matches `--line` in index.html

    init() {
        list = document.getElementById!("list").object!
        filter = document.getElementById!("filter").object!
        title = document.getElementById!("title").object!
        steps = document.getElementById!("steps").object!
        app = document.getElementById!("app").object!
        code = document.getElementById!("code").object!
        gutter = document.getElementById!("gutter").object!
        band = document.getElementById!("band").object!
        codePane = document.getElementById!("codepane").object!
        codeFile = document.getElementById!("codefile").object!
        modes = document.getElementById!("modes").object!
        renderList()
        // Clicks on list links select in place; the browser's back/forward buttons follow along.
        on(list, "click") { [weak self] event in
            guard let anchor = event.target.object?.closest?("a[data-fixture]").object,
                  let name = anchor.dataset.object?.fixture.string else { return }
            _ = event.preventDefault!()
            let encoded = JSObject.global.encodeURIComponent!(name).string ?? name
            _ = JSObject.global.history.object!.pushState!(JSValue.null, "", "?fixture=\(encoded)")
            self?.select(name)
        }
        on(JSObject.global, "popstate") { [weak self] _ in
            self?.select(requestedFixture(in: JSObject.global.location.object!.search.string ?? ""))
        }
        on(filter, "input") { [weak self] _ in self?.applyFilter() }
        on(steps, "click") { [weak self] event in
            guard let button = event.target.object?.closest?("button[data-step]").object,
                  let index = button.dataset.object?.step.string.flatMap(Int.init) else { return }
            self?.runStep(index)
        }
        on(modes, "click") { [weak self] event in
            guard let self, let button = event.target.object?.closest?("button[data-mode]").object else { return }
            self.wholeFile = button.dataset.object?.mode.string == "file"
            self.renderCode()
        }
        // Behaviour steps: `window.__galleryStep(i)` mutates the model; the host repaints on its own.
        let step = JSClosure { [weak self] args in
            if let index = args.first?.number { MainActor.assumeIsolated { self?.runStep(Int(index)) } }
            return .undefined
        }
        closures.append(step)
        JSObject.global.__galleryStep = .object(step)
    }

    private func on(_ target: JSObject, _ event: String, _ handler: @escaping @MainActor (JSObject) -> Void) {
        let closure = JSClosure { args in
            MainActor.assumeIsolated { if let e = args.first?.object { handler(e) } }
            return .undefined
        }
        closures.append(closure)
        _ = target.addEventListener!(event, closure)
    }

    /// Fixtures grouped by their directory prefix (`layout/spacer` lands under "layout").
    private func renderList() {
        var html = ""
        var group = ""
        for fixture in AllFixtures.all {
            let parts = fixture.name.split(separator: "/", maxSplits: 1).map(String.init)
            let prefix = parts.count > 1 ? parts[0] : ""
            if prefix != group || html.isEmpty {
                if !html.isEmpty { html += "</ul>" }
                html += "<h2>\(prefix.isEmpty ? "other" : prefix)</h2><ul>"
                group = prefix
            }
            let label = parts.count > 1 ? parts[1] : fixture.name
            let badge = fixture.stepNames.isEmpty ? "" : "<span class=\"badge\">\(fixture.stepNames.count)</span>"
            html += "<li><a href=\"?fixture=\(fixture.name)\" data-fixture=\"\(fixture.name)\">\(label)\(badge)</a></li>"
        }
        html += "</ul>"
        list.innerHTML = .string(html)
    }

    private func applyFilter() {
        let needle = (filter.value.string ?? "").lowercased()
        let items = list.querySelectorAll!("li").object!
        let count = Int(items.length.number ?? 0)
        for i in 0..<count {
            guard let item = items[i].object, let anchor = item.querySelector!("a").object else { continue }
            let name = anchor.dataset.object?.fixture.string ?? ""
            item.hidden = .boolean(!needle.isEmpty && !name.lowercased().contains(needle))
        }
    }

    /// Mounts `name` in the right pane, or the placeholder when `nil`/unknown.
    func select(_ name: String?) {
        let fixture = name.flatMap { n in AllFixtures.all.first { $0.name == n } }
        highlight(fixture?.name)
        guard let fixture else {
            title.textContent = .string(name.map { "No fixture named \($0)" } ?? "Select a fixture")
            steps.innerHTML = .string("")
            app.style.object!.width = .string("0px")
            app.style.object!.height = .string("0px")
            document.title = .string("SwiftUIWeb gallery")
            instance = nil
            source = nil
            renderCode()
            host?.mount(AnyView(EmptyView()))
            return
        }
        let size = fixture.size
        title.textContent = .string("\(fixture.name)  ·  \(Int(size.width))×\(Int(size.height))")
        document.title = .string("\(fixture.name) · SwiftUIWeb gallery")
        app.style.object!.width = .string("\(size.width)px")
        app.style.object!.height = .string("\(size.height)px")
        JSObject.global.__galleryFrames = .undefined

        let instance = fixture.instantiate()
        self.instance = instance
        var buttons = ""
        for (i, step) in instance.steps.enumerated() {
            buttons += "<button type=\"button\" data-step=\"\(i)\">\(i + 1). \(step.name)</button>"
        }
        steps.innerHTML = .string(buttons)
        source = FixtureSources.source(for: fixture.name)
        renderCode()

        // The host is created once `#app` has its first fixture size; later fixtures resize it.
        if host == nil {
            host = CanvasHost()
            // Fixture pages compare against goldens whose toolbar lives in the window chrome,
            // outside the capture; `?chrome=1` shows the runtime's bar (Playwright/toolbar-probe.mjs).
            host!.runtime.paintsWindowChrome = JSObject.global.location.search.string?.contains("chrome=1") == true
        }
        host!.mount(AnyView(
            instance.view
                .frame(width: size.width, height: size.height)
                .environment(\.colorScheme, fixture.colorScheme)
                .environment(\.platformProfile, fixture.platform == .iOS ? .iOS : .macOS)
                .coordinateSpace(name: fixtureRootSpace)
                .onPreferenceChange(ProbeKey.self) { frames in
                    // Same probe path as the Apple harness; published for Playwright/tier-b.mjs.
                    let object = JSObject.global.Object.function!.new()
                    for (id, frame) in frames {
                        let rect = JSObject.global.Object.function!.new()
                        rect.x = .number(frame.minX); rect.y = .number(frame.minY)
                        rect.width = .number(frame.width); rect.height = .number(frame.height)
                        object[dynamicMember: id] = .object(rect)
                    }
                    JSObject.global.__galleryFrames = .object(object)
                }))
        JSObject.global.__galleryStepCount = .number(Double(instance.steps.count))
        _ = JSObject.global.console.object!.log!("[gallery] mounted \(fixture.name)")
    }

    /// Fills the code pane: the fixture's declaration, or its whole file with the declaration
    /// marked and scrolled into view. Line numbers are the file's.
    private func renderCode() {
        guard let source else {
            code.innerHTML = .string("")
            gutter.innerHTML = .string("")
            codeFile.textContent = .string("")
            band.hidden = .boolean(true)
            return
        }
        let text = wholeFile ? source.fileContents : source.declaration
        let firstLine = wholeFile ? 1 : source.firstLine
        let lineCount = text.split(separator: "\n", omittingEmptySubsequences: false).count
        code.innerHTML = .string(highlighted(text))
        var numbers = ""
        for line in firstLine..<(firstLine + lineCount) {
            let marked = wholeFile && line >= source.firstLine && line <= source.lastLine
            numbers += "<span class=\"\(marked ? "mark" : "")\">\(line)</span>"
        }
        gutter.innerHTML = .string(numbers)
        codeFile.textContent = .string("\(source.file):\(source.firstLine)")
        let buttons = modes.querySelectorAll!("button[data-mode]").object!
        for i in 0..<Int(buttons.length.number ?? 0) {
            guard let button = buttons[i].object else { continue }
            let mode = button.dataset.object?.mode.string
            button.className = .string((mode == "file") == wholeFile ? "selected" : "")
        }
        if wholeFile {
            band.hidden = .boolean(false)
            band.style.object!.top = .string("\(Double(source.firstLine - 1) * lineHeight)px")
            band.style.object!.height = .string("\(Double(source.lastLine - source.firstLine + 1) * lineHeight)px")
            codePane.scrollTop = .number(max(0, Double(source.firstLine - 1) * lineHeight - 2 * lineHeight))
        } else {
            band.hidden = .boolean(true)
            codePane.scrollTop = .number(0)
        }
    }

    /// highlight.js output when the library loaded (see index.html), escaped plain text otherwise.
    private func highlighted(_ text: String) -> String {
        if let hljs = JSObject.global.hljs.object, !hljs.getLanguage!("swift").isUndefined {
            let options = JSObject.global.Object.function!.new()
            options.language = .string("swift")
            if let value = hljs.highlight!(text, options).object?.value.string { return value }
        }
        var escaped = ""
        for character in text {
            switch character {
            case "&": escaped += "&amp;"
            case "<": escaped += "&lt;"
            case ">": escaped += "&gt;"
            default: escaped.append(character)
            }
        }
        return escaped
    }

    private func runStep(_ index: Int) {
        guard let instance, index >= 0, index < instance.steps.count else { return }
        instance.steps[index].run()
    }

    private func highlight(_ name: String?) {
        let anchors = list.querySelectorAll!("a[data-fixture]").object!
        let count = Int(anchors.length.number ?? 0)
        for i in 0..<count {
            guard let anchor = anchors[i].object else { continue }
            let selected = anchor.dataset.object?.fixture.string == name
            anchor.className = .string(selected ? "selected" : "")
            if selected {
                let options = JSObject.global.Object.function!.new()
                options.block = .string("nearest")
                _ = anchor.scrollIntoView?(options)
            }
        }
    }
}

JavaScriptEventLoop.installGlobalExecutor()
let gallery = Gallery()
gallery.select(requestedFixture(in: JSObject.global.location.object!.search.string ?? ""))
#endif
