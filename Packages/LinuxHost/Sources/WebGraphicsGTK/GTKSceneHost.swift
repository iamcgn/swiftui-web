// The GTK4 window host (pf-linux): a `GtkApplication` with one window whose `GtkDrawingArea`
// paints the scene through the Cairo painter on every draw, and whose event controllers feed
// the scene — a click gesture for presses and releases, a motion controller for hovers and
// drags, a scroll controller for the wheel, a key controller for keys (typing reaches the
// focused text field as the browser's would, through `textField(_:didChange:)` from the key
// strokes). A frame-clock tick callback advances animations while the scene says it needs
// frames. The window's title follows the scene's.
#if canImport(CGtk)
import CGtk
import WebFoundation
import WebGraphics
import WebGraphicsCairo

@MainActor
public final class GTKSceneHost {
    public let scene: any HostedScene
    public let painter = CairoPainter()
    public let textEngine = CairoTextEngine()
    private let size: CGSize
    private let title: String
    private var application: UnsafeMutablePointer<GtkApplication>?
    private var window: UnsafeMutablePointer<GtkWidget>?
    private var area: UnsafeMutablePointer<GtkWidget>?
    private var lastFrameTime: Int64 = 0
    private var pressing = false
    /// The focused text field's text as last typed, so key strokes append and delete.
    private var typed: [Int: String] = [:]

    public init(size: CGSize, title: String, scene: any HostedScene) {
        self.scene = scene
        self.size = size
        self.title = title
        scene.textEngine = textEngine
        scene.onNeedsFrame = { [weak self] in self?.queueDraw() }
    }

    /// The window's scale factor (GTK renders the area in points; the painter is told the scale
    /// for its own rounding).
    public var pixelScale: CGFloat { area.map { CGFloat(gtk_widget_get_scale_factor($0)) } ?? 1 }

    private func object<T>(_ pointer: UnsafeMutablePointer<T>) -> UnsafeMutablePointer<GObject> {
        UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: GObject.self)
    }

    private func connect<T>(_ instance: UnsafeMutablePointer<T>, _ signal: String, _ callback: GCallback) {
        g_signal_connect_data(object(instance), signal, callback, Unmanaged.passUnretained(self).toOpaque(), nil, GConnectFlags(rawValue: 0))
    }

    /// Controllers and gestures are opaque to Swift: connected through their raw pointer.
    private func connect(_ instance: OpaquePointer, _ signal: String, _ callback: GCallback) {
        g_signal_connect_data(UnsafeMutableRawPointer(instance).assumingMemoryBound(to: GObject.self), signal, callback, Unmanaged.passUnretained(self).toOpaque(), nil, GConnectFlags(rawValue: 0))
    }

    /// Runs the application: returns its exit status when the window closes.
    public func run() -> Int32 {
        let app = gtk_application_new("dev.swiftuiweb.gtk", GApplicationFlags(rawValue: 0))!
        application = app
        connect(app, "activate", unsafeBitCast(activateCallback, to: GCallback.self))
        let status = g_application_run(UnsafeMutableRawPointer(app).assumingMemoryBound(to: GApplication.self), 0, nil)
        g_object_unref(app)
        return status
    }

    private func asWindow(_ widget: UnsafeMutablePointer<GtkWidget>) -> UnsafeMutablePointer<GtkWindow> {
        UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GtkWindow.self)
    }

    fileprivate func activate() {
        guard let application else { return }
        let window = gtk_application_window_new(application)!
        self.window = window
        gtk_window_set_title(asWindow(window), title)
        gtk_window_set_default_size(asWindow(window), Int32(size.width), Int32(size.height))
        let area = gtk_drawing_area_new()!
        self.area = area
        gtk_widget_set_focusable(area, 1)
        gtk_widget_set_hexpand(area, 1)
        gtk_widget_set_vexpand(area, 1)
        let user = Unmanaged.passUnretained(self).toOpaque()
        gtk_drawing_area_set_draw_func(UnsafeMutableRawPointer(area).assumingMemoryBound(to: GtkDrawingArea.self), drawCallback, user, nil)
        // Presses and releases (any button).
        let click = gtk_gesture_click_new()!
        gtk_gesture_single_set_button(click, 0)
        connect(click, "pressed", unsafeBitCast(pressedCallback, to: GCallback.self))
        connect(click, "released", unsafeBitCast(releasedCallback, to: GCallback.self))
        gtk_widget_add_controller(area, click)
        // Motion: hovers, and drags while pressing.
        let motion = gtk_event_controller_motion_new()!
        connect(motion, "motion", unsafeBitCast(motionCallback, to: GCallback.self))
        connect(motion, "leave", unsafeBitCast(leaveCallback, to: GCallback.self))
        gtk_widget_add_controller(area, motion)
        // The wheel.
        let scroll = gtk_event_controller_scroll_new(GTK_EVENT_CONTROLLER_SCROLL_BOTH_AXES)!
        connect(scroll, "scroll", unsafeBitCast(scrollCallback, to: GCallback.self))
        gtk_widget_add_controller(area, scroll)
        // Keys.
        let keys = gtk_event_controller_key_new()!
        connect(keys, "key-pressed", unsafeBitCast(keyCallback, to: GCallback.self))
        gtk_widget_add_controller(area, keys)
        _ = gtk_widget_add_tick_callback(area, tickCallback, user, nil)
        gtk_window_set_child(asWindow(window), area)
        gtk_window_present(asWindow(window))
        _ = gtk_widget_grab_focus(area)
    }

    private var lastPointer = CGPoint.zero

    fileprivate func draw(_ cr: OpaquePointer, width: Int32, height: Int32) {
        paint(into: cr, size: CGSize(width: CGFloat(width), height: CGFloat(height)))
        if let window, let title = scene.windowTitle { gtk_window_set_title(asWindow(window), title) }
    }

    /// Lays the scene out in `size` and paints its frame into a cairo context (the drawing
    /// area's, or an image surface's in tests).
    public func paint(into cr: OpaquePointer, size: CGSize) {
        scene.layout(in: size)
        painter.paint(scene.render(scale: pixelScale), into: cr)
    }

    @discardableResult
    public func tick(frameTime: Int64) -> Bool {
        let elapsed = lastFrameTime == 0 ? 0 : min(0.1, Double(frameTime - lastFrameTime) / 1_000_000)
        lastFrameTime = frameTime
        let animating = scene.advanceFrame(elapsed: elapsed)
        if animating || scene.isAnimating || scene.needsFrame { queueDraw() }
        return true
    }

    public func pressed(at point: CGPoint, time: Double) {
        pressing = true
        lastPointer = point
        scene.pointerDown(at: point, type: .mouse, time: time)
        queueDraw()
    }

    public func released(at point: CGPoint, time: Double) {
        pressing = false
        scene.pointerUp(at: point, time: time)
        queueDraw()
    }

    public func moved(to point: CGPoint, time: Double) {
        lastPointer = point
        scene.pointerMoved(to: point, time: time)
        if pressing || scene.needsFrame { queueDraw() }
    }

    fileprivate func left() {
        scene.pointerLeft()
        queueDraw()
    }

    public func scrolled(dx: Double, dy: Double) {
        // GTK's scroll units are steps for a wheel; a trackpad gives pixels under
        // `GTK_SCROLL_UNIT_SURFACE` (not distinguished here: a step scrolls 40 pt).
        scene.scrollWheel(by: CGSize(width: dx * 40, height: dy * 40), at: lastPointer)
        queueDraw()
    }

    /// A key: the named keys as key equivalents; printable characters typed into the focused
    /// text field, else as a key equivalent (shortcuts with Control standing in for Command).
    @discardableResult
    public func key(_ keyval: UInt32, modifiers: UInt32) -> Bool {
        var mods: EventModifiers = []
        if modifiers & GDK_SHIFT_MASK.rawValue != 0 { mods.insert(.shift) }
        if modifiers & GDK_CONTROL_MASK.rawValue != 0 { mods.insert(.command) }
        if modifiers & GDK_ALT_MASK.rawValue != 0 { mods.insert(.option) }
        let named: KeyEquivalent?
        switch keyval {
        case UInt32(GDK_KEY_Escape): named = .escape
        case UInt32(GDK_KEY_Return), UInt32(GDK_KEY_KP_Enter): named = .return
        case UInt32(GDK_KEY_Tab), UInt32(GDK_KEY_ISO_Left_Tab): named = .tab
        case UInt32(GDK_KEY_BackSpace): named = .delete
        case UInt32(GDK_KEY_Delete): named = .deleteForward
        case UInt32(GDK_KEY_Up): named = .upArrow
        case UInt32(GDK_KEY_Down): named = .downArrow
        case UInt32(GDK_KEY_Left): named = .leftArrow
        case UInt32(GDK_KEY_Right): named = .rightArrow
        case UInt32(GDK_KEY_Home): named = .home
        case UInt32(GDK_KEY_End): named = .end
        case UInt32(GDK_KEY_Page_Up): named = .pageUp
        case UInt32(GDK_KEY_Page_Down): named = .pageDown
        case UInt32(GDK_KEY_space): named = .space
        default: named = nil
        }
        let unicode = gdk_keyval_to_unicode(keyval)
        if let field = scene.focusedTextFieldIdentifier, mods.isDisjoint(with: [.command, .option]) {
            // Typing into the focused field: the text grows and shrinks by the key.
            var text = typed[field] ?? scene.semanticsTree().first { $0.identifier == field }?.textInput?.text ?? ""
            switch named {
            case .delete?: if !text.isEmpty { text.removeLast() }
            case .return?: scene.textFieldDidSubmit(field); queueDraw(); return true
            case .escape?, .tab?, .upArrow?, .downArrow?, .leftArrow?, .rightArrow?, .home?, .end?, .pageUp?, .pageDown?:
                let handled = scene.keyDown(KeyEvent(key: named!, modifiers: mods))
                queueDraw()
                return handled
            default:
                guard unicode != 0, let scalar = Unicode.Scalar(unicode) else { return false }
                text.append(Character(scalar))
            }
            typed[field] = text
            scene.textField(field, didChange: text)
            queueDraw()
            return true
        }
        typed.removeAll()
        let key: KeyEquivalent
        if let named {
            key = named
        } else if unicode != 0, let scalar = Unicode.Scalar(unicode) {
            key = KeyEquivalent(Character(String(Character(scalar)).lowercased()))
        } else {
            return false
        }
        let characters = unicode != 0 ? Unicode.Scalar(unicode).map { String(Character($0)) } ?? "" : ""
        let handled = scene.keyDown(KeyEvent(key: key, characters: characters, modifiers: mods))
        queueDraw()
        return handled
    }

    private func queueDraw() {
        if let area { gtk_widget_queue_draw(area) }
    }
}

// MARK: - C callbacks (the host is the user data; GTK calls them on the main thread)

/// The host behind GTK's user-data pointer; the pointers are passed as raw bits so the
/// main-actor closures capture nothing isolated (GTK's main loop is the main thread).
private func host(_ data: gpointer?) -> GTKSceneHost? {
    data.map { Unmanaged<GTKSceneHost>.fromOpaque($0).takeUnretainedValue() }
}

private let activateCallback: @convention(c) (UnsafeMutablePointer<GtkApplication>?, gpointer?) -> Void = { _, data in
    let bits = data.map { UInt(bitPattern: $0) }
    MainActor.assumeIsolated { host(bits.map { UnsafeMutableRawPointer(bitPattern: $0)! })?.activate() }
}

private let drawCallback: GtkDrawingAreaDrawFunc = { _, cr, width, height, data in
    guard let cr else { return }
    let bits = data.map { UInt(bitPattern: $0) }, crBits = UInt(bitPattern: cr)
    MainActor.assumeIsolated { host(bits.map { UnsafeMutableRawPointer(bitPattern: $0)! })?.draw(OpaquePointer(bitPattern: crBits)!, width: width, height: height) }
}

private let tickCallback: GtkTickCallback = { _, clock, data in
    let time = clock.map { gdk_frame_clock_get_frame_time($0) } ?? 0
    let bits = data.map { UInt(bitPattern: $0) }
    return MainActor.assumeIsolated { (host(bits.map { UnsafeMutableRawPointer(bitPattern: $0)! })?.tick(frameTime: time) ?? false) ? G_SOURCE_CONTINUE : G_SOURCE_REMOVE }
}

private let pressedCallback: @convention(c) (OpaquePointer?, gint, gdouble, gdouble, gpointer?) -> Void = { _, _, x, y, data in
    let bits = data.map { UInt(bitPattern: $0) }
    MainActor.assumeIsolated { host(bits.map { UnsafeMutableRawPointer(bitPattern: $0)! })?.pressed(at: CGPoint(x: x, y: y), time: Double(g_get_monotonic_time()) / 1_000_000) }
}

private let releasedCallback: @convention(c) (OpaquePointer?, gint, gdouble, gdouble, gpointer?) -> Void = { _, _, x, y, data in
    let bits = data.map { UInt(bitPattern: $0) }
    MainActor.assumeIsolated { host(bits.map { UnsafeMutableRawPointer(bitPattern: $0)! })?.released(at: CGPoint(x: x, y: y), time: Double(g_get_monotonic_time()) / 1_000_000) }
}

private let motionCallback: @convention(c) (OpaquePointer?, gdouble, gdouble, gpointer?) -> Void = { _, x, y, data in
    let bits = data.map { UInt(bitPattern: $0) }
    MainActor.assumeIsolated { host(bits.map { UnsafeMutableRawPointer(bitPattern: $0)! })?.moved(to: CGPoint(x: x, y: y), time: Double(g_get_monotonic_time()) / 1_000_000) }
}

private let leaveCallback: @convention(c) (OpaquePointer?, gpointer?) -> Void = { _, data in
    let bits = data.map { UInt(bitPattern: $0) }
    MainActor.assumeIsolated { host(bits.map { UnsafeMutableRawPointer(bitPattern: $0)! })?.left() }
}

private let scrollCallback: @convention(c) (OpaquePointer?, gdouble, gdouble, gpointer?) -> gboolean = { _, dx, dy, data in
    let bits = data.map { UInt(bitPattern: $0) }
    MainActor.assumeIsolated { host(bits.map { UnsafeMutableRawPointer(bitPattern: $0)! })?.scrolled(dx: dx, dy: dy) }
    return 1
}

private let keyCallback: @convention(c) (OpaquePointer?, guint, guint, GdkModifierType, gpointer?) -> gboolean = { _, keyval, _, state, data in
    let bits = data.map { UInt(bitPattern: $0) }, modifiers = state.rawValue
    return MainActor.assumeIsolated { (host(bits.map { UnsafeMutableRawPointer(bitPattern: $0)! })?.key(keyval, modifiers: modifiers) ?? false) ? 1 : 0 }
}
#endif
