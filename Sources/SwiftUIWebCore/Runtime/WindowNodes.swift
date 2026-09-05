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
        let box = descriptor.valueType == nil ? nil : _WindowValueBox(value?.base)
        var environment = rootEnvironment
        environment._windowIdentity = identity
        environment.dismissWindow = DismissWindowAction { [weak self] id, value, current in
            guard let self else { return }
            if current { self.closeWindow(identity: identity) } else { self.dismissWindow(id: id, value: value) }
        }
        let view = descriptor.make(box)
        let node = present(kind: .window(title: descriptor.title, size: descriptor.defaultSize), view: view, environment: environment, anchor: nil) { [weak self] in
            self?.openWindows.removeAll { $0.identity == identity }
        }
        box?.onChange = { [weak node, weak self] in
            guard let node, let self else { return }
            node.update(view: descriptor.make(box))
            self.requestLayout()
        }
        openWindows.append(OpenWindow(identity: identity, descriptor: descriptor, value: value, box: box, node: node))
        return true
    }

    private func bringToFront(_ node: PresentationNode) {
        guard let index = presentations.firstIndex(where: { $0 === node }) else { return }
        presentations.append(presentations.remove(at: index))
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
