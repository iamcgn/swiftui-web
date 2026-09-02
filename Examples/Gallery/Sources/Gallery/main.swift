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

// `?fixture=<name>` mounts one fixture at its size inside `#app`; without it, an index of links.
JavaScriptEventLoop.installGlobalExecutor()
let document = JSObject.global.document.object!
let search = JSObject.global.location.object!.search.string ?? ""
let query = search.dropFirst().split(separator: "&").map { $0.split(separator: "=", maxSplits: 1).map(String.init) }
let requested = query.first { $0.first == "fixture" }?.last.map(percentDecoded)

@MainActor
func mountIndex() {
    let app = document.getElementById!("app").object!
    var html = "<h1>SwiftUIWeb fixtures</h1><ul>"
    for fixture in AllFixtures.all {
        html += "<li><a href=\"?fixture=\(fixture.name)\">\(fixture.name)</a></li>"
    }
    html += "</ul>"
    app.innerHTML = .string(html)
}

if let name = requested, let fixture = AllFixtures.all.first(where: { $0.name == name }) {
    let app = document.getElementById!("app").object!
    app.style.object!.width = .string("\(fixture.size.width)px")
    app.style.object!.height = .string("\(fixture.size.height)px")
    let host = CanvasHost()
    let instance = fixture.instantiate()
    host.mount(AnyView(
        instance.view
            .frame(width: fixture.size.width, height: fixture.size.height)
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
    // Behaviour steps: `window.__galleryStep(i)` mutates the model; the host repaints on its own.
    let step = JSClosure { args in
        guard let index = args.first?.number, Int(index) < instance.steps.count else { return .undefined }
        instance.steps[Int(index)].run()
        return .undefined
    }
    JSObject.global.__galleryStep = .object(step)
    JSObject.global.__galleryStepCount = .number(Double(instance.steps.count))
    _ = JSObject.global.console.object!.log!("[gallery] mounted \(name)")
    galleryHost = host
    galleryStep = step
} else {
    mountIndex()
}
nonisolated(unsafe) var galleryHost: CanvasHost?
nonisolated(unsafe) var galleryStep: JSClosure?
#endif
