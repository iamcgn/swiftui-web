#if os(WASI)
import WebFoundation   // never full Foundation on wasm: it links ICU (decisions 0006, 0017)
#else
import Foundation
#endif
import WebGraphics
#if os(WASI)
import JavaScriptKit

/// Hosts a `HostedScene` in a `<canvas>`: sizing at device pixel ratio, a requestAnimationFrame
/// loop that advances the scene, lays out, paints through the injected JS decoder, forwards
/// pointer events in points, and maintains a DOM overlay of focusable elements and real inputs
/// for accessibility and text entry (decisions 0007 and 0014).
@MainActor
public final class CanvasSceneHost {
    public let scene: any HostedScene
    private let document: JSObject
    private let window: JSObject
    private let container: JSObject
    private let canvas: JSObject
    private let context: JSObject
    private let overlay: JSObject
    /// The live region announcements are spoken from.
    private let announcer: JSObject
    private let bridge: JSObject
    private var width: Double = 0
    private var height: Double = 0
    private var dpr: Double = 1
    private var frameScheduled = false
    private var needsLayout = true
    private var overlayButtons: [Int: JSObject] = [:]
    /// The semantics each overlay element was last written from (writes cross the JS bridge).
    private var overlayState: [Int: SemanticsNode] = [:]
    private var closures: [JSClosure] = []
    private var frameClosure: JSClosure?

    /// The platform look the page asks for (`data-platform="ios"` / `"macos"` on the container
    /// or `?platform=` in the URL, lowercased), if any.
    public let requestedPlatform: String?
    /// Whether the primary pointer is coarse (a finger: phones and tablets, an iPad with a
    /// trackpad included), the cue for a touch-first look.
    public let hasCoarsePointer: Bool
    /// The container's size in points and the device pixel ratio, as of the last resize.
    public var viewportSize: CGSize { CGSize(width: width, height: height) }
    public var pixelScale: CGFloat { dpr }

    /// Creates a host for `scene` in `#app` (or `<body>`): installs the text engine, assets,
    /// image loader, clipboard and appearance, and schedules the first frame.
    public init(scene: any HostedScene) {
        self.scene = scene
        window = JSObject.global
        // The browser's zone is the app's `TimeZone.current` (WebFoundation has no tz database;
        // `Intl` answers for named zones and the browser's language is `Locale.current`).
        if let minutes = JSObject.global.Date.function?.new().getTimezoneOffset?().number {
            TimeZone._hostSecondsFromGMT = -Int(minutes) * 60
        }
        IntlBridge.install()
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
        // Overlay elements sit wherever their views are, including outside the window on a
        // scrolled page: clipped, or mobile browsers widen the layout viewport to fit them.
        containerStyle.overflow = .string("hidden")
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
        overlayStyle.overflow = .string("hidden")
        _ = overlay.setAttribute!("aria-label", "SwiftUI content")
        _ = container.appendChild!(overlay)
        // Announcements (`UIAccessibility.post(.announcement)`) are spoken from a live region.
        announcer = document.createElement!("div").object!
        _ = announcer.setAttribute!("aria-live", "polite")
        _ = announcer.setAttribute!("role", "status")
        let announcerStyle = announcer.style.object!
        announcerStyle.position = .string("absolute")
        announcerStyle.width = .string("1px")
        announcerStyle.height = .string("1px")
        announcerStyle.overflow = .string("hidden")
        announcerStyle.clip = .string("rect(0 0 0 0)")
        _ = container.appendChild!(announcer)

        requestedPlatform = Self.requestedPlatform(window: window, container: container)
        hasCoarsePointer = window.matchMedia?("(pointer: coarse)").object?.matches.boolean ?? false
        scene.textEngine = Canvas2DTextEngine(context: context, bridge: bridge)
        scene.assetCatalog = Self.assetCatalog(from: window.__swiftuiwebAssets)
        loadFonts(scene.assetCatalog, base: window.__swiftuiwebAssets.object?.base.string ?? "")
        scene.onNeedsFrame = { [weak self] in self?.scheduleFrame() }
        // An image the painter had to fetch has arrived: paint the frame again (and let the
        // scene's image views move to their loaded or failed phase).
        let imageLoaded = JSClosure { [weak self] _ in
            MainActor.assumeIsolated {
                self?.scene.imageLoadDidFinish()
                self?.scheduleFrame()
            }
            return .undefined
        }
        scene.imageLoader = CanvasImageLoader(bridge: bridge)
        // A recorded drawing becomes PNG data through a canvas of its own (`UIImage.pngData()`).
        let painterBridge = bridge
        scene.imageRasterizer = { list, size, scale in
            let encoded = DisplayListEncoder.encode(list, font: DisplayListEncoder.cssFont)
            let buffer = JSTypedArray<Double>(encoded.ops)
            let strings = JSObject.global.Array.function!.new()
            for s in encoded.strings { _ = strings.push!(s) }
            guard let url = painterBridge.rasterize!(buffer, strings, scale, size.width, size.height).string,
                  let comma = url.firstIndex(of: ",") else { return nil }
            return Data(base64Encoded: String(url[url.index(after: comma)...]))
        }
        closures.append(imageLoaded)
        _ = bridge.setImageLoadHandler!(imageLoaded)
        // Copies reach the system clipboard when the page may write it.
        if let navigator = JSObject.global.navigator.object, let clipboard = navigator.clipboard.object, clipboard.writeText.function != nil {
            scene.clipboardWriter = { text in _ = clipboard.writeText!(text) }
        }
        // The system appearance, now and when it changes.
        if let media = window.matchMedia?("(prefers-color-scheme: dark)").object {
            scene.hostColorScheme = (media.matches.boolean ?? false) ? .dark : .light
            let listener = JSClosure { [weak self] arguments in
                MainActor.assumeIsolated {
                    self?.scene.hostColorScheme = (arguments.first?.matches.boolean ?? false) ? .dark : .light
                    self?.scheduleFrame()
                }
                return .undefined
            }
            _ = media.addEventListener?("change", listener)
            closures.append(listener)
        }
        // The scene phase: the page's visibility and the window's focus; the URL's fragment at
        // launch and later changes reach `onOpenURL`.
        scene.hostIsVisible = document.visibilityState.string != "hidden"
        scene.hostIsFocused = document.hasFocus.function.map { _ in document.hasFocus!().boolean ?? true } ?? true
        on(document, "visibilitychange") { [weak self] _ in
            guard let self else { return }
            self.scene.hostIsVisible = self.document.visibilityState.string != "hidden"
            self.scheduleFrame()
        }
        on(window, "focus") { [weak self] _ in self?.scene.hostIsFocused = true; self?.scheduleFrame() }
        on(window, "blur") { [weak self] _ in self?.scene.hostIsFocused = false; self?.scheduleFrame() }
        if let location = window.location.object, let href = location.href.string, let hash = location["hash"].string, !hash.isEmpty {
            scene.handleOpenURL(href)
        }
        for event in ["hashchange", "popstate"] {
            on(window, event) { [weak self] _ in
                guard let self, let href = self.window.location.object?.href.string else { return }
                self.scene.handleOpenURL(href)
                self.scheduleFrame()
            }
        }
        // Reduce motion, now and when it changes.
        if let media = window.matchMedia?("(prefers-reduced-motion: reduce)").object {
            scene.hostReducesMotion = media.matches.boolean ?? false
            let listener = JSClosure { [weak self] arguments in
                MainActor.assumeIsolated {
                    self?.scene.hostReducesMotion = arguments.first?.matches.boolean ?? false
                    self?.scheduleFrame()
                }
                return .undefined
            }
            _ = media.addEventListener?("change", listener)
            closures.append(listener)
        }
        installEventHandlers()
        resize()
        installDebugBridge()
    }

    /// Opens `url` in a new tab.
    public func openURL(_ url: String) {
        _ = window.window.object?.open?(url, "_blank", "noopener")
    }

    /// Shares `items` through Web Share where the browser offers it (a user gesture must be in
    /// flight): a single URL as a link, anything else as text.
    public func share(items: [String], subject: String?) {
        guard let navigator = JSObject.global.navigator.object, navigator.share.function != nil else { return }
        let data = JSObject.global.Object.function!.new()
        if let first = items.first, first.hasPrefix("http") { data.url = .string(first) } else { data.text = .string(items.joined(separator: "\n")) }
        if let subject { data.title = .string(subject) }
        _ = navigator.share!(data)
    }

    /// The platform a page forces with `data-platform` on the container or `?platform=` in its URL.
    static func requestedPlatform(window: JSObject, container: JSObject) -> String? {
        var forced = container.dataset.object?.platform.string
        if forced == nil, let search = window.location.object?.search.string {
            for pair in search.dropFirst().split(separator: "&") {
                let parts = pair.split(separator: "=", maxSplits: 1)
                if parts.count == 2, parts[0] == "platform" { forced = String(parts[1]) }
            }
        }
        return forced?.lowercased()
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
        var fonts: [String: FontResource] = [:]
        if let sets = manifest.fonts.object, let names = JSObject.global.Object.function!.keys!(sets).object {
            for index in 0..<Int(names.length.number ?? 0) {
                guard let name = names[index].string, let entry = sets[dynamicMember: name].object, let file = entry.file.string else { continue }
                fonts[name] = FontResource(postScriptName: entry.postScriptName.string ?? name, family: entry.family.string ?? name, file: file,
                                           unitsPerEm: entry.unitsPerEm.number ?? 1000, ascender: entry.ascender.number ?? 0,
                                           descender: entry.descender.number ?? 0, lineGap: entry.lineGap.number ?? 0,
                                           capHeight: entry.capHeight.number ?? 0, xHeight: entry.xHeight.number ?? 0,
                                           underlinePosition: entry.underlinePosition.number ?? 0, underlineThickness: entry.underlineThickness.number ?? 0)
            }
        }
        return AssetCatalog(images: images, colors: colors, fonts: fonts)
    }

    /// Loads the catalog's font files as `FontFace`s under their PostScript and family names,
    /// so Canvas2D measures and draws them; text measured before a face arrived is laid out again.
    private func loadFonts(_ catalog: AssetCatalog, base: String) {
        guard let fontSet = document.fonts.object, let fontFace = JSObject.global.FontFace.function else { return }
        for font in catalog.fonts.values {
            let source = "url(\(base)\(font.file))"
            for name in Set([font.postScriptName, font.family]) {
                let face = fontFace.new(name, source)
                _ = fontSet.add?(face)
                let loaded = JSClosure { [weak self] _ in
                    MainActor.assumeIsolated { self?.textLayoutsNeedMeasuring() }
                    return .undefined
                }
                let failed = JSClosure { _ in
                    _ = JSObject.global.console.object?.error?("SwiftUIWeb: could not load font \(name) from \(font.file)")
                    return .undefined
                }
                _ = face.load?().object?.then?(loaded, failed)
                pendingFontLoads += 2  // the closures stay alive until the promise settles
                fontLoadClosures += [loaded, failed]
            }
        }
    }

    private var pendingFontLoads = 0
    private var fontLoadClosures: [JSClosure] = []

    private func textLayoutsNeedMeasuring() {
        (scene.textEngine as? Canvas2DTextEngine)?.forgetMeasurements()
        scene.fontsDidLoad()
        scheduleFrame()
    }

    /// The scene's content changed outside its own invalidation (a new root was mounted):
    /// lays out again on the next frame.
    public func invalidate() {
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
                self.scene.secondaryPointerDown(at: self.point(of: e))
                self.scheduleFrame()
                return
            }
            _ = self.canvas.setPointerCapture?(e.pointerId)
            if self.pointerType(of: e) == .touch, self.touchDown(e) { return }
            self.scene.pointerModifiersChanged(self.modifiers(of: e))
            self.scene.pointerDown(at: self.point(of: e), type: self.pointerType(of: e), time: self.seconds(of: e))
            self.scheduleFrame()
        }
        // Context menus are the scene's; the browser's stays closed.
        on(canvas, "contextmenu") { e in _ = e.preventDefault!() }
        on(canvas, "pointermove") { [weak self] e in
            guard let self else { return }
            if self.pointerType(of: e) == .touch, self.touchMoved(e) { return }
            self.scene.pointerMoved(to: self.point(of: e), time: self.seconds(of: e))
            self.applyPointerStyle()
            if self.scene.needsFrame { self.scheduleFrame() }
        }
        on(canvas, "pointerleave") { [weak self] e in
            guard let self else { return }
            self.scene.pointerLeft()
            self.applyPointerStyle()
            if self.scene.needsFrame { self.scheduleFrame() }
        }
        on(canvas, "pointerup") { [weak self] e in
            guard let self, (e.button.number ?? 0) != 2 else { return }
            if self.pointerType(of: e) == .touch, self.touchUp(e) { return }
            self.scene.pointerUp(at: self.point(of: e), time: self.seconds(of: e))
            self.scheduleFrame()
        }
        on(canvas, "pointercancel") { [weak self] e in
            guard let self else { return }
            if self.pointerType(of: e) == .touch, self.touchUp(e) { return }
            self.scene.pointerUp(at: CGPoint(x: -1, y: -1), time: self.seconds(of: e))
            self.scheduleFrame()
        }
        // Safari delivers trackpad pinches as gesture events (scale and rotation in degrees).
        on(canvas, "gesturestart") { [weak self] e in
            guard let self else { return }
            _ = e.preventDefault?()
            self.endWheelPinch()
            self.gesturePinch = true
            self.scene.pinch(.began, scale: 1, rotation: 0, at: self.clientPoint(of: e), time: self.seconds(of: e))
            self.scheduleFrame()
        }
        on(canvas, "gesturechange") { [weak self] e in
            guard let self, self.gesturePinch else { return }
            _ = e.preventDefault?()
            self.scene.pinch(.changed, scale: e.scale.number ?? 1, rotation: (e.rotation.number ?? 0) * .pi / 180, at: self.clientPoint(of: e), time: self.seconds(of: e))
            self.scheduleFrame()
        }
        on(canvas, "gestureend") { [weak self] e in
            guard let self, self.gesturePinch else { return }
            _ = e.preventDefault?()
            self.gesturePinch = false
            self.scene.pinch(.ended, scale: e.scale.number ?? 1, rotation: (e.rotation.number ?? 0) * .pi / 180, at: self.clientPoint(of: e), time: self.seconds(of: e))
            self.scheduleFrame()
        }
        // Wheel deltas are consumed here (non-passive, so the page does not scroll too): pixel
        // deltas map to points, lines to 16 pt, pages to the viewport. A wheel with the control
        // key is a trackpad pinch (Chromium and Firefox): the scale compounds by e^(-deltaY/100)
        // and the pinch ends a fifth of a second after its last event.
        let wheel = JSClosure { [weak self] args in
            MainActor.assumeIsolated {
                guard let self, let e = args.first?.object else { return }
                _ = e.preventDefault!()
                if e.ctrlKey.boolean == true, !self.gesturePinch {
                    self.wheelPinch(e)
                    return
                }
                let mode = e.deltaMode.number ?? 0
                let factor = mode == 1 ? 16.0 : mode == 2 ? self.height : 1.0
                let delta = CGSize(width: (e.deltaX.number ?? 0) * factor, height: (e.deltaY.number ?? 0) * factor)
                self.scene.scrollWheel(by: delta, at: self.point(of: e))
                if self.scene.needsFrame { self.scheduleFrame() }
            }
            return .undefined
        }
        closures.append(wheel)
        let wheelOptions = JSObject.global.Object.function!.new()
        wheelOptions.passive = .boolean(false)
        _ = canvas.addEventListener!("wheel", wheel, wheelOptions)
        on(window, "resize") { [weak self] _ in self?.resize() }
        // Keys go to the scene: the focused element's handlers,
        // the open menu, keyboard shortcuts, Escape. A text field's input keeps its own keys
        // except Escape.
        on(window, "keydown") { [weak self] e in
            guard let self, let event = self.keyEvent(of: e) else { return }
            if self.scene.keyDown(event) {
                _ = e.preventDefault?()
                self.scheduleFrame()
            }
        }
        on(window, "keyup") { [weak self] e in
            guard let self, let event = self.keyEvent(of: e) else { return }
            if self.scene.keyUp(event) {
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

    private func modifiers(of event: JSObject) -> EventModifiers {
        var modifiers: EventModifiers = []
        if event.shiftKey.boolean == true { modifiers.insert(.shift) }
        if event.ctrlKey.boolean == true { modifiers.insert(.control) }
        if event.altKey.boolean == true { modifiers.insert(.option) }
        if event.metaKey.boolean == true { modifiers.insert(.command) }
        return modifiers
    }

    /// The scene's key event for a DOM keyboard event; nil for keys the scene has no equivalent
    /// for and for keys a text field's input keeps (all but Escape).
    private func keyEvent(of e: JSObject) -> KeyEvent? {
        guard let domKey = e.key.string, let key = KeyEquivalent(domKey: domKey) else { return nil }
        if let target = e.target.object, target.tagName.string == "INPUT", target.type.string != "range", key != .escape { return nil }
        return KeyEvent(key: key, characters: domKey.count == 1 ? domKey : "", modifiers: modifiers(of: e), isRepeat: e["repeat"].boolean == true, time: seconds(of: e))
    }

    /// The event's point from its client coordinates (gesture events carry no offset).
    private func clientPoint(of event: JSObject) -> CGPoint {
        let rect = canvas.getBoundingClientRect!().object!
        return CGPoint(x: (event.clientX.number ?? 0) - (rect.left.number ?? 0), y: (event.clientY.number ?? 0) - (rect.top.number ?? 0))
    }

    // MARK: Pinches

    /// A Safari gesture-event pinch in flight (control-wheel events are ignored meanwhile).
    private var gesturePinch = false
    /// The cumulative scale of a control-wheel pinch, nil when none is in flight.
    private var wheelPinchScale: Double?
    private var wheelPinchPoint = CGPoint.zero
    private var wheelPinchGeneration = 0
    private var wheelPinchClosure: JSClosure?

    private func wheelPinch(_ e: JSObject) {
        let point = point(of: e)
        let time = seconds(of: e)
        if wheelPinchScale == nil {
            wheelPinchScale = 1
            wheelPinchPoint = point
            scene.pinch(.began, scale: 1, rotation: 0, at: point, time: time)
        }
        let scale = (wheelPinchScale ?? 1) * _exp(-(e.deltaY.number ?? 0) / 100)
        wheelPinchScale = scale
        scene.pinch(.changed, scale: scale, rotation: 0, at: wheelPinchPoint, time: time)
        scheduleFrame()
        wheelPinchGeneration += 1
        let generation = wheelPinchGeneration
        let closure = JSClosure { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.wheelPinchGeneration == generation else { return }
                self.endWheelPinch()
            }
            return .undefined
        }
        wheelPinchClosure = closure
        _ = window.setTimeout!(closure, 200)
    }

    private func endWheelPinch() {
        guard let scale = wheelPinchScale else { return }
        wheelPinchScale = nil
        wheelPinchGeneration += 1
        scene.pinch(.ended, scale: scale, rotation: 0, at: wheelPinchPoint, time: now)
        scheduleFrame()
    }

    /// Touches by pointer id; two of them pinch (the press under the first is cancelled, and
    /// the touch that remains after the pinch is ignored until it lifts).
    private var touches: [Int: CGPoint] = [:]
    private var touchOrder: [Int] = []
    private var touchPinch: (distance: Double, angle: Double)?
    private var touchPinchLast: (scale: CGFloat, rotation: Double) = (1, 0)
    private var touchesAfterPinch = false

    private func touchGeometry() -> (centre: CGPoint, distance: Double, angle: Double)? {
        guard touchOrder.count >= 2, let a = touches[touchOrder[0]], let b = touches[touchOrder[1]] else { return nil }
        let dx = b.x - a.x, dy = b.y - a.y
        return (CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2), (dx * dx + dy * dy).squareRoot(), _atan2(dy, dx))
    }

    /// Returns whether the touch was taken by a pinch (or ignored after one).
    private func touchDown(_ e: JSObject) -> Bool {
        let id = Int(e.pointerId.number ?? 0)
        touches[id] = point(of: e)
        touchOrder.append(id)
        if touchesAfterPinch || touchPinch != nil { return true }
        guard touchOrder.count == 2, let geometry = touchGeometry() else { return false }
        scene.pointerUp(at: CGPoint(x: -1, y: -1), time: seconds(of: e))
        touchPinch = (max(geometry.distance, 1), geometry.angle)
        touchPinchLast = (1, 0)
        scene.pinch(.began, scale: 1, rotation: 0, at: geometry.centre, time: seconds(of: e))
        scheduleFrame()
        return true
    }

    private func touchMoved(_ e: JSObject) -> Bool {
        let id = Int(e.pointerId.number ?? 0)
        guard touches[id] != nil else { return false }
        touches[id] = point(of: e)
        if touchesAfterPinch { return true }
        guard let start = touchPinch, let geometry = touchGeometry() else { return false }
        var rotation = geometry.angle - start.angle
        while rotation > .pi { rotation -= 2 * .pi }
        while rotation < -.pi { rotation += 2 * .pi }
        touchPinchLast = (geometry.distance / start.distance, rotation)
        scene.pinch(.changed, scale: touchPinchLast.scale, rotation: touchPinchLast.rotation, at: geometry.centre, time: seconds(of: e))
        scheduleFrame()
        return true
    }

    private func touchUp(_ e: JSObject) -> Bool {
        let id = Int(e.pointerId.number ?? 0)
        guard touches[id] != nil else { return false }
        let centre = touchGeometry()?.centre ?? point(of: e)
        touches[id] = nil
        touchOrder.removeAll { $0 == id }
        if touchPinch != nil {
            touchPinch = nil
            touchesAfterPinch = !touches.isEmpty
            scene.pinch(.ended, scale: touchPinchLast.scale, rotation: touchPinchLast.rotation, at: centre, time: seconds(of: e))
            scheduleFrame()
            return true
        }
        if touchesAfterPinch {
            if touches.isEmpty { touchesAfterPinch = false }
            return true
        }
        return false
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
    /// The cursor over the canvas follows the hovered `pointerStyle`.
    private var appliedCursor = ""
    private func applyPointerStyle() {
        let cursor = scene.pointerCursor ?? ""
        guard cursor != appliedCursor else { return }
        appliedCursor = cursor
        canvas.style.cursor = .string(cursor)
    }

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
        let animating = scene.advanceFrame(elapsed: elapsed)
        lastFrameTime = time
        guard needsLayout || scene.needsFrame else {
            // An animation in a phase that changes nothing on screen (the indicator hold) still
            // needs the clock to advance.
            if animating { scheduleFrame() } else { lastFrameTime = nil }
            return
        }
        needsLayout = false
        scene.layout(in: CGSize(width: width, height: height))
        let laidOut = now
        let list = scene.render(scale: dpr)
        let rendered = now
        paint(list)
        let painted = now
        overlayStart = painted
        updateOverlay()
        lastDisplayList = list
        frameCount += 1
        frameMillis = (now - time) * 1000
        framePhases = [(laidOut - time) * 1000, (rendered - laidOut) * 1000, (painted - rendered) * 1000, semanticsMillis, (now - painted) * 1000 - semanticsMillis]
        // The first frame is on screen: a loading screen in the page can go (`index.html`
        // listens for `swiftuiwebready` on the container; it bubbles to the document).
        if frameCount == 1, let event = window.CustomEvent.function {
            let options = JSObject.global.Object.function!.new()
            options.bubbles = .boolean(true)
            _ = container.dispatchEvent?(event.new("swiftuiwebready", options))
        }
        // A preference action, observation, scroll animation or an animation the layout just
        // started may need another frame.
        if animating || scene.isAnimating || scene.needsFrame { scheduleFrame() } else { lastFrameTime = nil }
    }

    /// Time of the previous frame while frames run back to back (scroll animations).
    private var lastFrameTime: Double?

    /// Layout + paint time of the most recent frame in milliseconds (debug bridge), and its
    /// split into layout, display list, paint, semantics walk and overlay DOM milliseconds.
    public private(set) var frameMillis: Double = 0
    public private(set) var framePhases: [Double] = [0, 0, 0, 0, 0]
    private var overlayStart: Double = 0
    private var semanticsMillis: Double = 0

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
        let tree = scene.semanticsTree()
        semanticsMillis = (now - overlayStart) * 1000
        // Elements that moved or resized, positioned with one bridge call at the end:
        // identifier, x, y, then width and height or -1 when the size is unchanged.
        var moved: [Double] = []
        for node in tree {
            seen.insert(node.identifier)
            if let input = node.textInput {
                updateInputElement(node, input, moved: &moved)
                continue
            }
            let element: JSObject
            // A heading whose level changed needs a new element (the tag carries the level).
            if let existing = overlayButtons[node.identifier], let previous = overlayState[node.identifier], Self.overlayTag(for: previous) != Self.overlayTag(for: node) {
                _ = existing.remove!()
                _ = bridge.overlayRemove!(node.identifier)
                overlayButtons[node.identifier] = nil
                overlayState[node.identifier] = nil
            }
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
                        self.scene.setValue(semanticsIdentifier: id, value: value)
                        self.scheduleFrame()
                    }
                case .text, .heading, .image, .group, .list:
                    break
                default:
                    on(element, "click") { [weak self] _ in
                        self?.scene.activate(semanticsIdentifier: id)
                        self?.scheduleFrame()
                    }
                }
                // Keyboard focus is mirrored into the scene: the ring shows for keyboard focus
                // (`:focus-visible`), not for a click.
                if node.isFocusable || ![.text, .heading, .image, .group].contains(node.role) {
                    on(element, "focus") { [weak self] e in
                        guard let self else { return }
                        let visible = e.target.object?.matches?(":focus-visible").boolean ?? true
                        self.scene.focus(semanticsIdentifier: id, keyboard: visible)
                        self.scheduleFrame()
                    }
                    on(element, "blur") { [weak self] _ in
                        self?.scene.blur(semanticsIdentifier: id)
                        self?.scheduleFrame()
                    }
                }
                _ = overlay.appendChild!(element)
                overlayButtons[node.identifier] = element
                _ = bridge.overlayAdd!(node.identifier, element)
            }
            let previous = overlayState[node.identifier]
            if previous?.frame != node.frame {
                let resized = previous?.frame.size != node.frame.size
                moved += [Double(node.identifier), node.frame.minX, node.frame.minY, resized ? node.frame.width : -1, resized ? node.frame.height : -1]
            }
            var unmoved = node
            unmoved.frame = previous?.frame ?? .zero
            if previous == nil || previous != unmoved {
                Self.applyAttributes(of: node, to: element)
            }
            if previous?.customActions != node.customActions || previous?.rotors != node.rotors {
                syncActionsAndRotors(of: node, in: element)
            }
            overlayState[node.identifier] = node
            // Programmatic focus (`FocusState`, a click on a focusable view) moves the host's focus.
            if scene.focusedIdentifier == node.identifier, !(document.activeElement.object === element) {
                _ = element.focus?()
            }
        }
        for (id, element) in overlayButtons where !seen.contains(id) {
            _ = element.remove!()
            _ = bridge.overlayRemove!(id)
            overlayButtons[id] = nil
            overlayState[id] = nil
        }
        if !moved.isEmpty { _ = bridge.overlayFrames!(JSTypedArray<Double>(moved)) }
        deliverAccessibilityEvents()
    }

    /// Speaks the announcements the scene posted (the live region's text changes; the same text
    /// twice gets a zero-width space so it is spoken again) and moves focus where asked.
    private func deliverAccessibilityEvents() {
        for event in scene.takeAccessibilityEvents() {
            switch event {
            case .announce(let text):
                let previous = announcer.textContent.string ?? ""
                announcer.textContent = .string(previous == text ? text + "\u{200B}" : text)
            case .focus(let identifier):
                if let element = overlayButtons[identifier] { _ = element.focus?() }
            case .layoutChanged, .screenChanged:
                break
            }
        }
    }

    /// The overlay element for a semantics role: real controls where the browser has them
    /// (buttons, range inputs), headings (at their level) and plain elements for static content.
    private static func overlayTag(for node: SemanticsNode) -> String {
        switch node.role {
        case .slider: return "input"
        case .heading: return "h\(min(max(node.headingLevel ?? 2, 1), 6))"
        case .text, .image, .group, .list: return "div"
        default: return "button"
        }
    }

    /// Custom actions become buttons inside the element (reachable by assistive technology,
    /// each performing its action), rotors a `nav` landmark named after the rotor with a link
    /// per entry that focuses the entry's element.
    private func syncActionsAndRotors(of node: SemanticsNode, in element: JSObject) {
        let stale = element.querySelectorAll!("[data-swiftuiweb-extra]").object!
        var index = 0
        while let child = stale[index].object {
            _ = child.remove!()
            index += 1
        }
        let id = node.identifier
        for name in node.customActions {
            let button = document.createElement!("button").object!
            _ = button.setAttribute!("data-swiftuiweb-extra", "action")
            _ = button.setAttribute!("aria-label", name)
            button.textContent = .string(name)
            Self.hide(button)
            on(button, "click") { [weak self] e in
                _ = e.stopPropagation?()
                self?.scene.performAccessibilityAction(semanticsIdentifier: id, name: name)
                self?.scheduleFrame()
            }
            _ = element.appendChild!(button)
        }
        for rotor in node.rotors {
            let nav = document.createElement!("nav").object!
            _ = nav.setAttribute!("data-swiftuiweb-extra", "rotor")
            _ = nav.setAttribute!("aria-label", rotor.label)
            Self.hide(nav)
            for entry in rotor.entries {
                let link = document.createElement!("a").object!
                _ = link.setAttribute!("href", "#")
                _ = link.setAttribute!("aria-label", entry.label)
                link.textContent = .string(entry.label)
                let target = entry.target
                on(link, "click") { [weak self] e in
                    _ = e.preventDefault?()
                    _ = e.stopPropagation?()
                    guard let self, let target else { return }
                    self.scene.focus(semanticsIdentifier: target, keyboard: true)
                    self.scheduleFrame()
                }
                _ = nav.appendChild!(link)
            }
            _ = element.appendChild!(nav)
        }
    }

    private static func hide(_ element: JSObject) {
        let style = element.style.object!
        style.position = .string("absolute")
        style.opacity = .string("0")
        style.pointerEvents = .string("none")
        style.margin = .string("0")
        style.padding = .string("0")
        style.border = .string("0")
    }

    /// ARIA attributes and text for an element from its semantics.
    private static func applyAttributes(of node: SemanticsNode, to element: JSObject) {
        // The label is the element's first text node (`textContent` would drop the action
        // buttons and rotor landmarks inside it).
        if let first = element.firstChild.object, first.nodeType.number == 3 {
            first.nodeValue = .string(node.label)
        } else {
            let text = element.ownerDocument.object!.createTextNode!(node.label).object!
            if let first = element.firstChild.object { _ = element.insertBefore!(text, first) } else { _ = element.appendChild!(text) }
        }
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
        if let hint = node.hint { _ = element.setAttribute!("aria-description", hint) } else { _ = element.removeAttribute!("aria-description") }
        if let identifier = node.accessibilityIdentifier { _ = element.setAttribute!("data-testid", identifier) }
        if let description = node.description { _ = element.setAttribute!("title", description) } else { _ = element.removeAttribute!("title") }
        if node.isLive { _ = element.setAttribute!("aria-live", "polite") } else { _ = element.removeAttribute!("aria-live") }
        if let selected = node.isSelected { _ = element.setAttribute!("aria-selected", selected ? "true" : "false") } else { _ = element.removeAttribute!("aria-selected") }
        if node.isEnabled { _ = element.removeAttribute!("aria-disabled") } else { _ = element.setAttribute!("aria-disabled", "true") }
    }

    /// A text field's editor: a real `<input>` over the text line with transparent text (the
    /// canvas paints it), so typing, IME composition, caret, selection and copy/paste are the
    /// browser's. Its value flows into the binding on every `input` event.
    private func updateInputElement(_ node: SemanticsNode, _ info: TextInputInfo, moved: inout [Double]) {
        let element: JSObject
        if let existing = overlayButtons[node.identifier] {
            element = existing
        } else {
            element = document.createElement!(info.isMultiline ? "textarea" : "input").object!
            let style = element.style.object!
            style.position = .string("absolute")
            style.margin = .string("0")
            style.padding = .string("0")
            style.border = .string("0")
            style.outline = .string("none")
            style.background = .string("transparent")
            style.color = .string("transparent")
            // The scene paints the caret and selection (TextInputInfo.paintsCaret): the
            // element's stay invisible (`::selection` through the overlay's style rule).
            style.caretColor = .string(info.paintsCaret ? "transparent" : "black")
            style.pointerEvents = .string("auto")
            style.boxSizing = .string("border-box")
            if info.paintsCaret { _ = element.classList.object?.add?("swiftuiweb-input") }
            installInputStyleRule()
            if info.isMultiline {
                style.resize = .string("none")
                style.overflow = .string("hidden")
                style.whiteSpace = .string("pre-wrap")
                style.wordBreak = .string("break-word")
            }
            _ = element.setAttribute!("autocomplete", "off")
            _ = element.setAttribute!("autocapitalize", "off")
            _ = element.setAttribute!("spellcheck", "false")
            let id = node.identifier
            on(element, "input") { [weak self] e in
                guard let self, let target = e.target.object else { return }
                self.scene.textField(id, didChange: target.value.string ?? "")
                self.reportSelection(id, target)
                self.scheduleFrame()
            }
            // The caret and selection follow keys, the pointer and programmatic moves.
            for event in ["select", "keyup", "mouseup", "focus"] {
                on(element, event) { [weak self] e in
                    guard let self, let target = e.target.object else { return }
                    self.reportSelection(id, target)
                    self.scheduleFrame()
                }
            }
            on(element, "keydown") { [weak self] e in
                guard let self, e.key.string == "Enter" else { return }
                // A text field submits on Return, even a multi-line one; an editor keeps the newline.
                guard self.overlayState[id]?.textInput?.submitsOnReturn ?? true else { return }
                if e.shiftKey.boolean != true { _ = e.preventDefault?() }
                self.scene.textFieldDidSubmit(id)
                self.scheduleFrame()
            }
            on(element, "focus") { [weak self] _ in
                self?.scene.textField(id, focused: true)
                self?.scheduleFrame()
            }
            on(element, "blur") { [weak self] _ in
                self?.scene.textField(id, focused: false)
                self?.scheduleFrame()
            }
            _ = overlay.appendChild!(element)
            overlayButtons[node.identifier] = element
            _ = bridge.overlayAdd!(node.identifier, element)
        }
        let previous = overlayState[node.identifier]?.textInput
        if previous?.textRect != info.textRect {
            moved += [Double(node.identifier), info.textRect.minX, info.textRect.minY, info.textRect.width, info.textRect.height]
        }
        if previous == nil || previous?.font != info.font || previous?.lineHeight != info.lineHeight
            || previous?.firstBaseline != info.firstBaseline || previous?.textRect.height != info.textRect.height
            || previous?.isSecure != info.isSecure || previous?.isEnabled != info.isEnabled || previous?.inputType != info.inputType {
            let style = element.style.object!
            style.font = .string(DisplayListEncoder.cssFont(info.font))
            if info.isMultiline {
                // The textarea's first baseline lands where the canvas paints it: pad the top by
                // the difference between the scene's first baseline and the line box's own.
                style.lineHeight = .string("\(info.lineHeight)px")
                style.paddingTop = .string("\(max(0, info.firstBaseline - info.lineHeight * 0.8))px")
            } else {
                style.lineHeight = .string("\(info.textRect.height)px")
                element.type = .string(info.isSecure ? "password" : (info.inputType ?? "text"))
            }
            element.disabled = .boolean(!info.isEnabled)
        }
        // The keyboard attributes (submitLabel, keyboardType, textContentType, autocapitalization,
        // autocorrection) reach the element as it changes.
        if previous == nil || previous?.inputMode != info.inputMode || previous?.autocomplete != info.autocomplete
            || previous?.autocapitalize != info.autocapitalize || previous?.enterKeyHint != info.enterKeyHint || previous?.autocorrect != info.autocorrect {
            setOrRemove(element, "inputmode", info.inputMode)
            setOrRemove(element, "autocomplete", info.autocomplete ?? "off")
            setOrRemove(element, "autocapitalize", info.autocapitalize ?? "off")
            setOrRemove(element, "enterkeyhint", info.enterKeyHint)
            setOrRemove(element, "autocorrect", info.autocorrect ? "on" : "off")
            setOrRemove(element, "spellcheck", info.autocorrect ? "true" : "false")
        }
        if overlayState[node.identifier]?.label != node.label { _ = element.setAttribute!("aria-label", node.label) }
        overlayState[node.identifier] = node
        if element.value.string != info.text { element.value = .string(info.text) }
        // A field the scene focused (a canvas press) takes the browser focus too.
        if scene.focusedTextFieldIdentifier == node.identifier, document.activeElement.object != element {
            _ = element.focus?()
        }
    }

    private func setOrRemove(_ element: JSObject, _ name: String, _ value: String?) {
        if let value { _ = element.setAttribute!(name, value) } else { _ = element.removeAttribute!(name) }
    }

    /// Tells the scene where the element's caret or selection is (UTF-16 offsets).
    private func reportSelection(_ id: Int, _ element: JSObject) {
        guard let start = element.selectionStart.number, let end = element.selectionEnd.number else { return }
        scene.textField(id, selectionStart: Int(start), end: Int(end))
    }

    private var installedInputStyleRule = false

    /// The overlay inputs' own selection highlight is invisible: the scene paints it.
    private func installInputStyleRule() {
        guard !installedInputStyleRule else { return }
        installedInputStyleRule = true
        let style = document.createElement!("style").object!
        style.textContent = .string(".swiftuiweb-input::selection { background: transparent; color: transparent; }")
        _ = document.head.object?.appendChild!(style)
    }

    /// `window.__swiftuiwebDebug`: probe frames, display list and frame count for Tier B tests.
    private func installDebugBridge() {
        let debug = JSObject.global.Object.function!.new()
        let frames = JSClosure { [weak self] _ in
            guard let self else { return .undefined }
            let object = JSObject.global.Object.function!.new()
            for (id, frame) in self.scene.probeFrames {
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
        let framePhases = JSClosure { [weak self] _ in
            let object = JSObject.global.Object.function!.new()
            let phases = self?.framePhases ?? [0, 0, 0, 0, 0]
            object.layout = .number(phases[0]); object.render = .number(phases[1]); object.paint = .number(phases[2])
            object.semantics = .number(phases[3]); object.overlay = .number(phases[4])
            return .object(object)
        }
        let pendingImages = JSClosure { [weak self] _ in self?.bridge.pendingImages!() ?? .number(0) }
        let animating = JSClosure { [weak self] _ in .boolean(self?.scene.isAnimating ?? false) }
        let semantics = JSClosure { [weak self] _ in
            guard let self else { return .undefined }
            let array = JSObject.global.Array.function!.new()
            for node in self.scene.semanticsTree() {
                let object = JSObject.global.Object.function!.new()
                object.role = .string(node.role.rawValue)
                object.label = .string(node.label)
                if let value = node.value { object.value = .string(value) }
                if let identifier = node.accessibilityIdentifier { object.identifier = .string(identifier) }
                _ = array.push!(object)
            }
            return .object(array)
        }
        // WebFoundation as the host wired it: the zone `Intl` named, its offsets on a date, the
        // locale, a formatted date (Playwright/foundation-probe.mjs reads them).
        let foundation = JSClosure { arguments in
            let object = JSObject.global.Object.function!.new()
            let zone = TimeZone.current
            let date = arguments.first?.number.map { Date(timeIntervalSince1970: $0) } ?? Date()
            object.timeZone = .string(zone.identifier)
            object.secondsFromGMT = .number(Double(zone.secondsFromGMT(for: date)))
            object.isDaylightSavingTime = .boolean(zone.isDaylightSavingTime(for: date))
            object.abbreviation = .string(zone.abbreviation(for: date) ?? "")
            object.zoneName = .string(zone.localizedName(for: .standard, locale: nil) ?? "")
            object.locale = .string(Locale.current.identifier)
            object.knownZones = .number(Double(TimeZone.knownTimeZoneIdentifiers.count))
            object.formatted = .string(date.formatted(date: .complete, time: .complete))
            if let berlin = TimeZone(identifier: "Europe/Berlin") {
                object.berlinOffset = .number(Double(berlin.secondsFromGMT(for: date)))
                object.berlinName = .string(berlin.abbreviation(for: date) ?? "")
            }
            return .object(object)
        }
        closures += [frames, displayList, frameCount, frameMillis, framePhases, pendingImages, animating, semantics, foundation]
        debug.foundation = .object(foundation)
        debug.framePhases = .object(framePhases)
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

/// The browser's image loader: `Image` elements kept by the painter script, asked by URL.
@MainActor
final class CanvasImageLoader: _ImageLoading {
    private let bridge: JSObject
    init(bridge: JSObject) { self.bridge = bridge }

    func state(for url: String) -> _ImageLoadState {
        let state = bridge.imageState!(url)
        if let text = state.string { return text == "failed" ? .failed : .loading }
        guard let array = state.object, let width = array[0].number, let height = array[1].number else { return .loading }
        return .loaded(pixelSize: CGSize(width: width, height: height))
    }
}


/// The browser's `Intl` behind WebFoundation's named time zones and the current locale.
enum IntlBridge {
    /// One `Intl.DateTimeFormat` per zone and name style, made on first use.
    nonisolated(unsafe) private static var formatters: [String: JSObject] = [:]

    static func install() {
        let intl = JSObject.global.Intl
        guard let dateTimeFormat = intl.DateTimeFormat.function else { return }
        if let zone = dateTimeFormat.new().resolvedOptions?().timeZone.string, !zone.isEmpty { TimeZone._hostIdentifier = zone }
        TimeZone._hostOffset = { identifier, time in
            guard let parts = formatParts(identifier, style: "longOffset", time: time) else { return nil }
            return parseOffset(parts)
        }
        TimeZone._hostName = { identifier, time, style in formatParts(identifier, style: style, time: time) }
        TimeZone._hostKnownIdentifiers = {
            guard let values = JSObject.global.Intl.supportedValuesOf.function?("timeZone").object else { return ["GMT"] }
            let count = Int(values.length.number ?? 0)
            return (0..<count).compactMap { values[$0].string }
        }
        let navigator = JSObject.global.navigator
        if let language = navigator.language.string, !language.isEmpty { Locale._hostIdentifier = language }
        if let languages = navigator.languages.object {
            let count = Int(languages.length.number ?? 0)
            let list = (0..<count).compactMap { languages[$0].string }
            if !list.isEmpty { Locale._hostPreferredLanguages = list }
        }
    }

    /// The `timeZoneName` part of a format in the given style, nil for a zone `Intl` rejects.
    private static func formatParts(_ identifier: String, style: String, time: Double) -> String? {
        let key = identifier + "|" + style
        let formatter: JSObject
        if let known = formatters[key] {
            formatter = known
        } else {
            guard let constructor = JSObject.global.Intl.DateTimeFormat.function else { return nil }
            let options = JSObject.global.Object.function!.new()
            options.timeZone = .string(identifier)
            options.timeZoneName = .string(style)
            guard let made = try? JSThrowingFunction(constructor).new("en-US", options) else { return nil }
            formatters[key] = made
            formatter = made
        }
        guard let parts = formatter.formatToParts?(time * 1000).object else { return nil }
        let count = Int(parts.length.number ?? 0)
        for index in 0..<count where parts[index].type.string == "timeZoneName" { return parts[index].value.string }
        return nil
    }

    /// Seconds east of GMT from "GMT", "GMT+2", "GMT-04:00" or "GMT+05:45".
    private static func parseOffset(_ text: String) -> Int? {
        let body = text.hasPrefix("GMT") ? text.dropFirst(3) : text.hasPrefix("UTC") ? text.dropFirst(3) : Substring(text)
        if body.isEmpty { return 0 }
        guard let sign = body.first, sign == "+" || sign == "-" || sign == "\u{2212}" else { return nil }
        let pieces = body.dropFirst().split(separator: ":")
        guard let hours = pieces.first.flatMap({ Int($0) }) else { return nil }
        let minutes = pieces.count > 1 ? Int(pieces[1]) ?? 0 : 0
        return (hours * 3600 + minutes * 60) * (sign == "+" ? 1 : -1)
    }
}

#else
/// The canvas host exists only on wasm; this keeps the module importable elsewhere.
public enum WebGraphicsCanvas {}
#endif
