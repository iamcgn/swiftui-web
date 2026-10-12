// Secondary windows: the app's window descriptors live on the runtime; opening one presents
// its root in a `.window` presentation (title bar, traffic lights, cascade) that the pointer
// treats as non-modal.

/// A window opened through `openWindow` or `openSettings`.
package struct OpenWindow {
    package let identity: Int
    package let descriptor: _WindowDescriptor
    package let value: AnyHashable?
    package let box: _WindowValueBox?
    package let node: PresentationNode
}

extension Runtime {
    /// Installs the window actions in the root environment (hosts call this with the app's scenes).
    public func installWindows(_ descriptors: [_WindowDescriptor]) {
        windowDescriptors = descriptors
        installCommands(documentCommands() + descriptors.flatMap(\.commands))
        rootEnvironment.openWindow = OpenWindowAction { [weak self] id, value in self?.openWindow(id: id, value: value) }
        rootEnvironment.dismissWindow = DismissWindowAction { [weak self] id, value, current in
            guard let self else { return }
            if current { return }       // the main window cannot dismiss itself
            self.dismissWindow(id: id, value: value)
        }
        rootEnvironment.openSettings = OpenSettingsAction { [weak self] in self?.openSettings() }
        root.environment = rootEnvironment
        root.reapply?(rootEnvironment)
    }

    /// The window scene for `id` (or the first value-typed group matching `value`).
    package func windowDescriptor(id: String?, value: Any?) -> _WindowDescriptor? {
        if let id { return windowDescriptors.first { $0.id == id && $0.kind != .menuBarExtra } }
        if let value {
            return windowDescriptors.first { descriptor in
                guard let type = descriptor.valueType else { return false }
                return _isInstance(value, of: type)
            }
        }
        return nil
    }

    /// Opens (or brings forward) the window for `id` and `value`.
    @discardableResult
    public func openWindow(id: String?, value: Any?) -> Bool {
        guard let descriptor = windowDescriptor(id: id, value: value) else { return false }
        let key = value.flatMap { $0 as? AnyHashable } ?? (value as? any Hashable).map { AnyHashable($0) }
        if let existing = openWindows.first(where: { $0.descriptor.id == descriptor.id && $0.descriptor.kind == descriptor.kind && $0.value == key }) {
            bringToFront(existing.node)
            return true
        }
        return present(descriptor, value: key)
    }

    public func openSettings() {
        guard let descriptor = windowDescriptors.first(where: { $0.kind == .settings }) else { return }
        if let existing = openWindows.first(where: { $0.descriptor.kind == .settings }) {
            bringToFront(existing.node)
            return
        }
        present(descriptor, value: nil)
    }

    @discardableResult
    private func present(_ descriptor: _WindowDescriptor, value: AnyHashable?) -> Bool {
        let identity = nextWindowIdentity
        nextWindowIdentity += 1
        // A value window's box carries its value; a document window's its document state.
        let box = descriptor.valueType == nil && descriptor.documentType == nil ? nil : _WindowValueBox(value?.base)
        var environment = rootEnvironment
        environment._windowIdentity = identity
        environment.dismissWindow = DismissWindowAction { [weak self] id, value, current in
            guard let self else { return }
            if current { self.closeWindow(identity: identity) } else { self.dismissWindow(id: id, value: value) }
        }
        let view = descriptor.make(box)
        let node = present(kind: .window(title: descriptor.title, size: descriptor.defaultSize), view: view, environment: environment, anchor: nil) { [weak self] in
            self?.openWindows.removeAll { $0.identity == identity }
            self?.persistWindows()
        }
        node.windowOptions = PresentationNode.WindowOptions(defaultPosition: descriptor.defaultPosition, resizable: descriptor.resizable, hidesTitleBar: descriptor.hidesTitleBar)
        box?.onChange = { [weak node, weak self] in
            guard let node, let self else { return }
            node.update(view: descriptor.make(box))
            self.requestLayout()
        }
        openWindows.append(OpenWindow(identity: identity, descriptor: descriptor, value: value, box: box, node: node))
        // A window just opened is the key window (its document is the frontmost).
        keyWindow = node
        persistWindows()
        return true
    }

    // MARK: Restoration (sw-windows)

    /// Where the open windows are remembered between launches (the browser host's
    /// localStorage, UserDefaults natively): ids and the values of value window groups when
    /// they are strings, integers, doubles or booleans. Hosts set it before `installWindows`.
    public var windowStateStore: (get: () -> String?, set: (String) -> Void)? {
        get { windowStore }
        set { windowStore = newValue }
    }

    private func persistWindows() {
        guard let store = windowStateStore else { return }
        let entries: [String] = openWindows.compactMap { window in
            guard window.descriptor.kind != .settings else { return "settings" }
            var entry = "id=" + (window.descriptor.id ?? "")
            if let value = window.value?.base {
                switch value {
                case let string as String: entry += "\ts=" + string
                case let int as Int: entry += "\ti=\(int)"
                case let double as Double: entry += "\td=\(double)"
                case let bool as Bool: entry += "\tb=\(bool)"
                default: return nil
                }
            }
            return entry
        }
        store.set(entries.joined(separator: "\n"))
    }

    /// Reopens the windows a previous launch left open (`windowStateStore`); hosts call it once
    /// the root is mounted.
    public func restoreWindows() {
        guard let stored = windowStateStore?.get(), !stored.isEmpty else { return }
        for line in stored.split(separator: "\n") {
            if line == "settings" { openSettings(); continue }
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard let first = parts.first, first.hasPrefix("id=") else { continue }
            let id = String(first.dropFirst(3))
            var value: Any?
            if parts.count > 1 {
                let field = parts[1]
                let payload = String(field.dropFirst(2))
                switch field.prefix(2) {
                case "s=": value = payload
                case "i=": value = Int(payload)
                case "d=": value = Double(payload)
                case "b=": value = Bool(payload)
                default: break
                }
            }
            if value != nil, id.isEmpty { openWindow(id: nil, value: value) } else { openWindow(id: id.isEmpty ? nil : id, value: value) }
        }
    }

    private func bringToFront(_ node: PresentationNode) {
        guard let index = presentations.firstIndex(where: { $0 === node }) else { return }
        presentations.append(presentations.remove(at: index))
        keyWindow = node
        setNeedsDisplay()
    }

    /// Closes the windows matching `id` and `value` (all windows of a group when both are nil).
    public func dismissWindow(id: String?, value: Any?) {
        let key = value.flatMap { $0 as? AnyHashable } ?? (value as? any Hashable).map { AnyHashable($0) }
        let matching = openWindows.filter { window in
            (id == nil || window.descriptor.id == id) && (key == nil || window.value == key)
        }
        for window in matching { window.node.dismiss() }
    }

    package func closeWindow(identity: Int) {
        openWindows.first { $0.identity == identity }?.node.dismiss()
    }

    /// The open secondary windows, front to back.
    public var openWindowCount: Int { openWindows.count }
}

private func _isInstance(_ value: Any, of type: Any.Type) -> Bool {
    func check<T>(_: T.Type) -> Bool { value is T }
    return _openExistential(type, do: check)
}
