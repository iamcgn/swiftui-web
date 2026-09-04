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
        runtime.assetCatalog = Self.assetCatalog(from: window.__swiftuiwebAssets)
        runtime.scheduler.onNeedsFlush = { [weak self] in self?.scheduleFrame() }
        // An image the painter had to fetch has arrived: paint the frame again.
        let imageLoaded = JSClosure { [weak self] _ in
            MainActor.assumeIsolated {
                self?.runtime.setNeedsDisplay()
                self?.scheduleFrame()
            }
            return .undefined
        }
        closures.append(imageLoaded)
        _ = bridge.setImageLoadHandler!(imageLoaded)
        installEventHandlers()
        resize()
        installDebugBridge()
    }

    /// The catalog `scripts/assets.py --js` published as `window.__swiftuiwebAssets`, or an empty
    /// one when the page has no manifest script.
    static func assetCatalog(from manifest: JSValue) -> AssetCatalog {
        guard let manifest = manifest.object else { return .empty }
        var images: [String: ImageResource] = [:]
        if let sets = manifest.images.object, let names = JSObject.global.Object.function!.keys!(sets).object {
            for index in 0..<Int(names.length.number ?? 0) {
                guard let name = names[index].string, let set = sets[dynamicMember: name].object,
                      let variants = set.variants.object else { continue }
                var resource = ImageResource(name: name, isTemplate: set.template.boolean ?? false, variants: [])
                for v in 0..<Int(variants.length.number ?? 0) {
                    guard let variant = variants[v].object, let file = variant.file.string else { continue }
                    resource.variants.append(ImageVariant(
                        file: file, scale: CGFloat(variant.scale.number ?? 1),
                        pixelWidth: Int(variant.width.number ?? 0), pixelHeight: Int(variant.height.number ?? 0),
                        idiom: variant.idiom.string ?? "universal", appearance: variant.appearance.string ?? "any"))
                }
                images[name] = resource
            }
        }
        var colors: [String: [ColorVariant]] = [:]
        if let sets = manifest.colors.object, let names = JSObject.global.Object.function!.keys!(sets).object {
            for index in 0..<Int(names.length.number ?? 0) {
                guard let name = names[index].string, let set = sets[dynamicMember: name].object,
                      let variants = set.variants.object else { continue }
                var entries: [ColorVariant] = []
                for v in 0..<Int(variants.length.number ?? 0) {
                    guard let variant = variants[v].object else { continue }
                    entries.append(ColorVariant(
                        idiom: variant.idiom.string ?? "universal", appearance: variant.appearance.string ?? "any",
                        colorSpace: variant.colorSpace.string ?? "srgb",
                        red: variant.red.number ?? 0, green: variant.green.number ?? 0, blue: variant.blue.number ?? 0,
                        alpha: variant.alpha.number ?? 1))
                }
                colors[name] = entries
            }
        }
        return AssetCatalog(images: images, colors: colors)
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
            if (e.button.number ?? 0) == 2 {
                self.runtime.secondaryPointerDown(at: self.point(of: e))
                self.scheduleFrame()
                return
            }
            _ = self.canvas.setPointerCapture?(e.pointerId)
            self.runtime.pointerDown(at: self.point(of: e), type: self.pointerType(of: e), time: self.seconds(of: e))
            self.scheduleFrame()
        }
        // Context menus are the runtime's (`contextMenu`); the browser's stays closed.
        on(canvas, "contextmenu") { e in _ = e.preventDefault!() }
        on(canvas, "pointermove") { [weak self] e in
            guard let self else { return }
            self.runtime.pointerMoved(to: self.point(of: e), time: self.seconds(of: e))
            if self.runtime.needsFrame { self.scheduleFrame() }
        }
        on(canvas, "pointerup") { [weak self] e in
            guard let self, (e.button.number ?? 0) != 2 else { return }
            self.runtime.pointerUp(at: self.point(of: e), time: self.seconds(of: e))
            self.scheduleFrame()
        }
        on(canvas, "pointercancel") { [weak self] e in
            guard let self else { return }
            self.runtime.pointerUp(at: CGPoint(x: -1, y: -1), time: self.seconds(of: e))
            self.scheduleFrame()
        }
        // Wheel deltas are consumed here (non-passive, so the page does not scroll too): pixel
        // deltas map to points, lines to 16 pt, pages to the viewport.
        let wheel = JSClosure { [weak self] args in
            MainActor.assumeIsolated {
                guard let self, let e = args.first?.object else { return }
                _ = e.preventDefault!()
                let mode = e.deltaMode.number ?? 0
                let factor = mode == 1 ? 16.0 : mode == 2 ? self.height : 1.0
                let delta = CGSize(width: (e.deltaX.number ?? 0) * factor, height: (e.deltaY.number ?? 0) * factor)
                self.runtime.scrollWheel(by: delta, at: self.point(of: e))
                if self.runtime.needsFrame { self.scheduleFrame() }
            }
            return .undefined
        }
        closures.append(wheel)
        let wheelOptions = JSObject.global.Object.function!.new()
        wheelOptions.passive = .boolean(false)
        _ = canvas.addEventListener!("wheel", wheel, wheelOptions)
        on(window, "resize") { [weak self] _ in self?.resize() }
        // Keys go to the runtime (Runtime/KeyboardNodes.swift): the focused element's handlers,
        // the open menu, keyboard shortcuts, Escape. A text field's input keeps its own keys
        // except Escape.
        on(window, "keydown") { [weak self] e in
            guard let self, let domKey = e.key.string, let key = KeyEquivalent(domKey: domKey) else { return }
            if let target = e.target.object, target.tagName.string == "INPUT", target.type.string != "range", key != .escape { return }
            var modifiers: EventModifiers = []
            if e.shiftKey.boolean == true { modifiers.insert(.shift) }
            if e.ctrlKey.boolean == true { modifiers.insert(.control) }
            if e.altKey.boolean == true { modifiers.insert(.option) }
            if e.metaKey.boolean == true { modifiers.insert(.command) }
            let event = KeyEvent(key: key, characters: domKey.count == 1 ? domKey : "", modifiers: modifiers, isRepeat: e["repeat"].boolean == true)
            if self.runtime.keyDown(event) {
                _ = e.preventDefault?()
                self.scheduleFrame()
            }
        }
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

    private func pointerType(of event: JSObject) -> PointerType {
        switch event.pointerType.string {
        case "touch": return .touch
        case "pen": return .pen
        default: return .mouse
        }
    }

    /// The event's timestamp in seconds (same clock as `performance.now()`).
    private func seconds(of event: JSObject) -> Double {
        (event.timeStamp.number ?? 0) / 1000
    }

    private var now: Double { (window.performance.object?.now?().number ?? 0) / 1000 }

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
        // A hidden document gets no animation frames (a WKWebView window the window server has
        // not shown yet, a background tab): the first frames come from a timer instead so the
        // page has content when it appears; after that only visible documents paint.
        if frameCount == 0, document.hidden.boolean == true {
            _ = window.setTimeout!(frameClosure!, 16)
        } else {
            _ = window.requestAnimationFrame!(frameClosure!)
        }
    }

    private func tick() {
        frameScheduled = false
        let time = now
        let elapsed = lastFrameTime.map { min(0.1, time - $0) } ?? 0
        var animating = runtime.advanceScrollAnimations(elapsed: elapsed)
        if runtime.advanceAnimations(elapsed: elapsed) { animating = true }
        lastFrameTime = time
        guard needsLayout || runtime.needsFrame else {
            // An animation in a phase that changes nothing on screen (the indicator hold) still
            // needs the clock to advance.
            if animating { scheduleFrame() } else { lastFrameTime = nil }
            return
        }
        needsLayout = false
        runtime.layout(in: CGSize(width: width, height: height))
        let list = runtime.render(scale: dpr)
        paint(list)
        updateOverlay()
        lastDisplayList = list
        frameCount += 1
        frameMillis = (now - time) * 1000
        // A preference action, observation, scroll animation or an animation the layout just
        // started may need another frame.
        if animating || runtime.isAnimating || runtime.needsFrame { scheduleFrame() } else { lastFrameTime = nil }
    }

    /// Time of the previous frame while frames run back to back (scroll animations).
    private var lastFrameTime: Double?

    /// Layout + paint time of the most recent frame in milliseconds (debug bridge).
    public private(set) var frameMillis: Double = 0

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
            if let input = node.textInput {
                updateInputElement(node, input)
                continue
            }
            let element: JSObject
            if let existing = overlayButtons[node.identifier] {
                element = existing
            } else {
                element = document.createElement!(Self.overlayTag(for: node)).object!
                let style = element.style.object!
                style.position = .string("absolute")
                style.opacity = .string("0")
                style.pointerEvents = .string("none")
                style.margin = .string("0")
                style.padding = .string("0")
                style.border = .string("0")
                let id = node.identifier
                switch node.role {
                case .slider:
                    on(element, "input") { [weak self] e in
                        guard let self, let target = e.target.object, let value = Double(target.value.string ?? "") else { return }
                        self.runtime.setValue(semanticsIdentifier: id, value: value)
                        self.scheduleFrame()
                    }
                case .text, .heading, .image, .group, .list:
                    break
                default:
                    on(element, "click") { [weak self] _ in
                        self?.runtime.activate(semanticsIdentifier: id)
                        self?.scheduleFrame()
                    }
                }
                // Keyboard focus is mirrored into the runtime: the ring shows for keyboard focus
                // (`:focus-visible`), not for a click.
                if node.isFocusable || ![.text, .heading, .image, .group].contains(node.role) {
                    on(element, "focus") { [weak self] e in
                        guard let self else { return }
                        let visible = e.target.object?.matches?(":focus-visible").boolean ?? true
                        self.runtime.focus(semanticsIdentifier: id, keyboard: visible)
                        self.scheduleFrame()
                    }
                    on(element, "blur") { [weak self] _ in
                        self?.runtime.blur(semanticsIdentifier: id)
                        self?.scheduleFrame()
                    }
                }
                _ = overlay.appendChild!(element)
                overlayButtons[node.identifier] = element
            }
            let style = element.style.object!
            style.left = .string("\(node.frame.minX)px")
            style.top = .string("\(node.frame.minY)px")
            style.width = .string("\(node.frame.width)px")
            style.height = .string("\(node.frame.height)px")
            Self.applyAttributes(of: node, to: element)
            // Programmatic focus (`FocusState`, a click on a focusable view) moves the host's focus.
            if runtime.focusedIdentifier == node.identifier, !(document.activeElement.object === element) {
                _ = element.focus?()
            }
        }
        for (id, element) in overlayButtons where !seen.contains(id) {
            _ = element.remove!()
            overlayButtons[id] = nil
        }
    }

    /// The overlay element for a semantics role: real controls where the browser has them
    /// (buttons, range inputs), headings and plain elements for static content.
    private static func overlayTag(for node: SemanticsNode) -> String {
        switch node.role {
        case .slider: return "input"
        case .heading: return "h2"
        case .text, .image, .group, .list: return "div"
        default: return "button"
        }
    }

    /// ARIA attributes and text for an element from its semantics.
    private static func applyAttributes(of node: SemanticsNode, to element: JSObject) {
        element.textContent = .string(node.label)
        _ = element.setAttribute!("aria-label", node.label)
        switch node.role {
        case .checkbox:
            _ = element.setAttribute!("role", "checkbox")
            _ = element.setAttribute!("aria-checked", node.isOn == true ? "true" : "false")
        case .switch:
            _ = element.setAttribute!("role", "switch")
            _ = element.setAttribute!("aria-checked", node.isOn == true ? "true" : "false")
        case .slider:
            element.type = .string("range")
            if let range = node.range {
                _ = element.setAttribute!("min", "\(range.minimum)")
                _ = element.setAttribute!("max", "\(range.maximum)")
                _ = element.setAttribute!("step", range.step.map { "\($0)" } ?? "any")
                if element.value.string != "\(range.value)" { element.value = .string("\(range.value)") }
            }
        case .stepper:
            _ = element.setAttribute!("role", "spinbutton")
        case .popUpButton:
            _ = element.setAttribute!("aria-haspopup", "listbox")
        case .segmented, .radioGroup:
            _ = element.setAttribute!("role", "radiogroup")
        case .image:
            _ = element.setAttribute!("role", "img")
        case .group:
            _ = element.setAttribute!("role", "group")
        case .list:
            _ = element.setAttribute!("role", "listbox")
        case .link:
            _ = element.setAttribute!("role", "link")
        case .text, .heading, .button, .textField:
            break
        }
        if node.isFocusable { _ = element.setAttribute!("tabindex", "0") }
        if let value = node.value { _ = element.setAttribute!("aria-valuetext", value) }
        if let hint = node.hint { _ = element.setAttribute!("aria-description", hint) }
        if let identifier = node.accessibilityIdentifier { _ = element.setAttribute!("data-testid", identifier) }
    }

    /// A text field's editor: a real `<input>` over the text line with transparent text (the
    /// canvas paints it), so typing, IME composition, caret, selection and copy/paste are the
    /// browser's. Its value flows into the binding on every `input` event.
    private func updateInputElement(_ node: SemanticsNode, _ info: TextInputInfo) {
        let element: JSObject
        if let existing = overlayButtons[node.identifier] {
            element = existing
        } else {
            element = document.createElement!("input").object!
            let style = element.style.object!
            style.position = .string("absolute")
            style.margin = .string("0")
            style.padding = .string("0")
            style.border = .string("0")
            style.outline = .string("none")
            style.background = .string("transparent")
            style.color = .string("transparent")
            style.caretColor = .string("black")
            style.pointerEvents = .string("auto")
            style.boxSizing = .string("border-box")
            _ = element.setAttribute!("autocomplete", "off")
            _ = element.setAttribute!("autocapitalize", "off")
            _ = element.setAttribute!("spellcheck", "false")
            let id = node.identifier
            on(element, "input") { [weak self] e in
                guard let self, let target = e.target.object else { return }
                self.runtime.textField(id, didChange: target.value.string ?? "")
                self.scheduleFrame()
            }
            on(element, "keydown") { [weak self] e in
                guard let self, e.key.string == "Enter" else { return }
                self.runtime.textFieldDidSubmit(id)
                self.scheduleFrame()
            }
            on(element, "focus") { [weak self] _ in
                self?.runtime.textField(id, focused: true)
                self?.scheduleFrame()
            }
            on(element, "blur") { [weak self] _ in
                self?.runtime.textField(id, focused: false)
                self?.scheduleFrame()
            }
            _ = overlay.appendChild!(element)
            overlayButtons[node.identifier] = element
        }
        let style = element.style.object!
        style.left = .string("\(info.textRect.minX)px")
        style.top = .string("\(info.textRect.minY)px")
        style.width = .string("\(info.textRect.width)px")
        style.height = .string("\(info.textRect.height)px")
        style.font = .string(DisplayListEncoder.cssFont(info.font))
        style.lineHeight = .string("\(info.textRect.height)px")
        element.type = .string(info.isSecure ? "password" : "text")
        element.disabled = .boolean(!info.isEnabled)
        _ = element.setAttribute!("aria-label", node.label)
        if element.value.string != info.text { element.value = .string(info.text) }
        // A field the runtime focused (a canvas press) takes the browser focus too.
        if runtime.focusedTextFieldIdentifier == node.identifier, document.activeElement.object != element {
            _ = element.focus?()
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
        let frameMillis = JSClosure { [weak self] _ in .number(self?.frameMillis ?? 0) }
        let pendingImages = JSClosure { [weak self] _ in self?.bridge.pendingImages!() ?? .number(0) }
        let animating = JSClosure { [weak self] _ in .boolean(self?.runtime.isAnimating ?? false) }
        let semantics = JSClosure { [weak self] _ in
            guard let self else { return .undefined }
            let array = JSObject.global.Array.function!.new()
            for node in self.runtime.semanticsTree() {
                let object = JSObject.global.Object.function!.new()
                object.role = .string(node.role.rawValue)
                object.label = .string(node.label)
                if let value = node.value { object.value = .string(value) }
                if let identifier = node.accessibilityIdentifier { object.identifier = .string(identifier) }
                _ = array.push!(object)
            }
            return .object(array)
        }
        closures += [frames, displayList, frameCount, frameMillis, pendingImages, animating, semantics]
        debug.animating = .object(animating)
        debug.semantics = .object(semantics)
        debug.pendingImages = .object(pendingImages)
        debug.frames = .object(frames)
        debug.displayList = .object(displayList)
        debug.frameCount = .object(frameCount)
        debug.frameMillis = .object(frameMillis)
        JSObject.global.__swiftuiwebDebug = .object(debug)
    }
}
#else
/// The canvas host exists only on wasm; this keeps the module importable elsewhere.
public enum SwiftUIWebCanvas {}
#endif
