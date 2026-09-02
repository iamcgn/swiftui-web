import SwiftUIWebCore
#if os(WASI)
import JavaScriptKit
import JavaScriptEventLoop

/// Hosts a `Runtime` in a `<canvas>`: sizing at device pixel ratio, a requestAnimationFrame
/// loop that flushes state, lays out, paints through the injected JS decoder, forwards pointer
/// events in points, and maintains a DOM overlay of focusable buttons for accessibility.
@MainActor
public final class CanvasHost {
    public let runtime = Runtime()
    private let document: JSObject
    private let window: JSObject
    private let container: JSObject
    private let canvas: JSObject
    private let context: JSObject
    private let overlay: JSObject
    private let bridge: JSObject
    private var width: Double = 0
    private var height: Double = 0
    private var dpr: Double = 1
    private var frameScheduled = false
    private var needsLayout = true
    private var overlayButtons: [Int: JSObject] = [:]
    private var closures: [JSClosure] = []
    private var frameClosure: JSClosure?

    /// Installs the JavaScript event loop, creates a host in `#app` (or `<body>`) and mounts.
    public static func launch(_ root: @MainActor () -> AnyView) {
        JavaScriptEventLoop.installGlobalExecutor()
        let host = CanvasHost()
        host.mount(root())
        retained = host
    }

    nonisolated(unsafe) private static var retained: CanvasHost?

    public init() {
        window = JSObject.global
        document = window.document.object!
        if window.__swiftuiweb.isUndefined {
            let script = document.createElement!("script").object!
            script.textContent = .string(PainterScript.source)
            _ = document.head.object!.appendChild!(script)
        }
        bridge = window.__swiftuiweb.object!
        container = document.getElementById!("app").object ?? document.body.object!
        let containerStyle = container.style.object!
        if (containerStyle.position.string ?? "").isEmpty {
            containerStyle.position = .string("relative")
        }
        canvas = document.createElement!("canvas").object!
        canvas.style.object!.display = .string("block")
        canvas.style.object!.touchAction = .string("none")
        _ = container.appendChild!(canvas)
        context = canvas.getContext!("2d").object!
        overlay = document.createElement!("div").object!
        let overlayStyle = overlay.style.object!
        overlayStyle.position = .string("absolute")
        overlayStyle.left = .string("0")
        overlayStyle.top = .string("0")
        overlayStyle.width = .string("100%")
        overlayStyle.height = .string("100%")
        overlayStyle.pointerEvents = .string("none")
        _ = overlay.setAttribute!("aria-label", "SwiftUI content")
        _ = container.appendChild!(overlay)

        runtime.textEngine = Canvas2DTextEngine(context: context, bridge: bridge)
        runtime.scheduler.onNeedsFlush = { [weak self] in self?.scheduleFrame() }
        installEventHandlers()
        resize()
        installDebugBridge()
    }

    /// Mounts (or replaces) the root view and schedules a frame.
    public func mount(_ view: AnyView) {
        runtime.mount(view)
        needsLayout = true
        scheduleFrame()
    }

    private func on(_ target: JSObject, _ event: String, _ handler: @escaping @MainActor (JSObject) -> Void) {
        let closure = JSClosure { args in
            MainActor.assumeIsolated { if let e = args.first?.object { handler(e) } }
            return .undefined
        }
        closures.append(closure)
        _ = target.addEventListener!(event, closure)
    }

    private func installEventHandlers() {
        on(canvas, "pointerdown") { [weak self] e in
            guard let self else { return }
            _ = self.canvas.setPointerCapture?(e.pointerId)
            self.runtime.pointerDown(at: self.point(of: e))
            self.scheduleFrame()
        }
        on(canvas, "pointermove") { [weak self] e in
            guard let self else { return }
            self.runtime.pointerMoved(to: self.point(of: e))
        }
        on(canvas, "pointerup") { [weak self] e in
            guard let self else { return }
            self.runtime.pointerUp(at: self.point(of: e))
            self.scheduleFrame()
        }
        on(window, "resize") { [weak self] _ in self?.resize() }
        if let resizeObserver = window.ResizeObserver.function {
            let closure = JSClosure { [weak self] _ in
                MainActor.assumeIsolated { self?.resize() }
                return .undefined
            }
            closures.append(closure)
            let observer = resizeObserver.new(closure)
            _ = observer.observe!(container)
        }
    }

    private func point(of event: JSObject) -> CGPoint {
        CGPoint(x: event.offsetX.number ?? 0, y: event.offsetY.number ?? 0)
    }

    private func resize() {
        let newWidth = container.clientWidth.number ?? 0
        let newHeight = container.clientHeight.number ?? 0
        let newDPR = window.devicePixelRatio.number ?? 1
        guard newWidth != width || newHeight != height || newDPR != dpr else { return }
        width = newWidth
        height = newHeight
        dpr = newDPR
        canvas.width = .number((width * dpr).rounded())
        canvas.height = .number((height * dpr).rounded())
        canvas.style.object!.width = .string("\(width)px")
        canvas.style.object!.height = .string("\(height)px")
        needsLayout = true
        scheduleFrame()
    }

    /// Requests one animation frame; several invalidations coalesce into it.
    public func scheduleFrame() {
        guard !frameScheduled else { return }
        frameScheduled = true
        if frameClosure == nil {
            frameClosure = JSClosure { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
                return .undefined
            }
        }
        _ = window.requestAnimationFrame!(frameClosure!)
    }

    private func tick() {
        frameScheduled = false
        guard needsLayout || runtime.scheduler.hasPendingWork else { return }
        needsLayout = false
        runtime.layout(in: CGSize(width: width, height: height))
        let list = runtime.render(scale: dpr)
        paint(list)
        updateOverlay()
        lastDisplayList = list
        frameCount += 1
        // A preference action or observation may have invalidated during layout.
        if runtime.scheduler.hasPendingWork { scheduleFrame() }
    }

    /// The most recently painted display list and the number of frames painted (debug bridge).
    public private(set) var lastDisplayList = DisplayList()
    public private(set) var frameCount = 0

    private func paint(_ list: DisplayList) {
        let encoded = DisplayListEncoder.encode(list, font: DisplayListEncoder.cssFont)
        let buffer = JSTypedArray<Double>(encoded.ops)
        let strings = JSObject.global.Array.function!.new()
        for s in encoded.strings { _ = strings.push!(s) }
        _ = bridge.paint!(context, buffer, strings, dpr, width, height)
    }

    private func updateOverlay() {
        var seen = Set<Int>()
        for node in runtime.semanticsTree() {
            seen.insert(node.identifier)
            let element: JSObject
            if let existing = overlayButtons[node.identifier] {
                element = existing
            } else {
                element = document.createElement!("button").object!
                let style = element.style.object!
                style.position = .string("absolute")
                style.opacity = .string("0")
                style.pointerEvents = .string("none")
                style.margin = .string("0")
                style.padding = .string("0")
                style.border = .string("0")
                let id = node.identifier
                on(element, "click") { [weak self] _ in
                    self?.runtime.activate(semanticsIdentifier: id)
                    self?.scheduleFrame()
                }
                _ = overlay.appendChild!(element)
                overlayButtons[node.identifier] = element
            }
            let style = element.style.object!
            style.left = .string("\(node.frame.minX)px")
            style.top = .string("\(node.frame.minY)px")
            style.width = .string("\(node.frame.width)px")
            style.height = .string("\(node.frame.height)px")
            element.textContent = .string(node.label)
            _ = element.setAttribute!("aria-label", node.label)
        }
        for (id, element) in overlayButtons where !seen.contains(id) {
            _ = element.remove!()
            overlayButtons[id] = nil
        }
    }

    /// `window.__swiftuiwebDebug`: probe frames, display list and frame count for Tier B tests.
    private func installDebugBridge() {
        let debug = JSObject.global.Object.function!.new()
        let frames = JSClosure { [weak self] _ in
            guard let self else { return .undefined }
            let object = JSObject.global.Object.function!.new()
            for (id, frame) in self.runtime.probeFrames {
                let rect = JSObject.global.Object.function!.new()
                rect.x = .number(frame.minX); rect.y = .number(frame.minY)
                rect.width = .number(frame.width); rect.height = .number(frame.height)
                object[dynamicMember: id] = .object(rect)
            }
            return .object(object)
        }
        let displayList = JSClosure { [weak self] _ in
            guard let self else { return .undefined }
            let array = JSObject.global.Array.function!.new()
            for command in self.lastDisplayList.commands { _ = array.push!(command.description) }
            return .object(array)
        }
        let frameCount = JSClosure { [weak self] _ in .number(Double(self?.frameCount ?? 0)) }
        closures += [frames, displayList, frameCount]
        debug.frames = .object(frames)
        debug.displayList = .object(displayList)
        debug.frameCount = .object(frameCount)
        JSObject.global.__swiftuiwebDebug = .object(debug)
    }
}
#else
/// The canvas host exists only on wasm; this keeps the module importable elsewhere.
public enum SwiftUIWebCanvas {}
#endif
