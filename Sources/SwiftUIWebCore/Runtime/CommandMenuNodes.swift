// Menu commands (API/MenuCommands.swift, sw-windows): the app's `Scene.commands` menus are
// mounted in a hidden tree (never laid out or painted) so their `keyboardShortcut`s match key
// presses in every host; hosts with a menu bar (the native host) read `commandMenus` — each
// menu's items with labels, shortcuts and enabled states — and run them through
// `performCommand(identifier:)`.

/// One item of a command menu as a host's menu bar shows it.
public struct _CommandMenuItem: Equatable, Sendable {
    /// nil for a separator (`Divider`).
    public let label: String?
    public let shortcut: KeyboardShortcut?
    public let isEnabled: Bool
    public let isOn: Bool?
    /// The control's semantics identifier (`performCommand`).
    public let identifier: Int

    public init(label: String?, shortcut: KeyboardShortcut?, isEnabled: Bool, isOn: Bool?, identifier: Int) {
        self.label = label
        self.shortcut = shortcut
        self.isEnabled = isEnabled
        self.isOn = isOn
        self.identifier = identifier
    }
}

/// A command menu as a host's menu bar shows it: its title (a `CommandMenu`'s own, or the
/// standard menu a `CommandGroup`'s placement names) and items.
public struct _CommandMenu: Equatable, Sendable {
    public let title: String
    public let placement: CommandGroupPlacement?
    public let position: _CommandMenuData.Position
    public let items: [_CommandMenuItem]
}

extension _CommandMenuData.Position: Equatable {}

extension Runtime {
    /// Installs the app's menu commands: mounts each menu's content in a hidden root of its own.
    public func installCommands(_ menus: [_CommandMenuData]) {
        commandMenuData = menus
        for root in commandsRoots { root.unmount() }
        commandsRoots = []
        var environment = rootEnvironment
        environment._automaticLabelContext = nil
        for menu in menus {
            commandsRoots.append(AnyView._makeNode(_NodeContext(view: menu.content, parent: root, environment: environment)))
        }
    }

    /// The menus for a host's menu bar: every menu's buttons, toggles and dividers in order,
    /// with their shortcuts and enabled states (read after a layout: the tree updates then).
    public var commandMenus: [_CommandMenu] {
        guard !commandsRoots.isEmpty else { return [] }
        flush()
        var result: [_CommandMenu] = []
        for (menu, box) in zip(commandMenuData, commandsRoots) {
            var items: [_CommandMenuItem] = []
            func walk(_ node: ViewNode, shortcut: KeyboardShortcut?) {
                var shortcut = shortcut
                if let matcher = node as? any _ShortcutProviding { shortcut = matcher._shortcut ?? shortcut }
                if node.isInteractiveNode, let interactive = node as? any _Interactive {
                    let semantics = interactive.semantics
                    items.append(_CommandMenuItem(label: semantics.label, shortcut: shortcut, isEnabled: node.environment.isEnabled, isOn: semantics.isOn, identifier: semantics.identifier))
                    return
                }
                if node is DividerNode { items.append(_CommandMenuItem(label: nil, shortcut: nil, isEnabled: true, isOn: nil, identifier: 0)); return }
                for child in node.structuralChildren { walk(child, shortcut: shortcut) }
            }
            walk(box, shortcut: nil)
            result.append(_CommandMenu(title: menu.title ?? menu.placement?.menuTitle ?? "App", placement: menu.placement, position: menu.position, items: items))
        }
        return result
    }

    /// Runs a command the host's menu bar chose (`_CommandMenuItem.identifier`).
    public func performCommand(identifier: Int) {
        let nodes = commandsRoots.flatMap { $0.descendants(where: { ($0 as? any _Interactive)?.semantics.identifier == identifier }) }
        guard let node = nodes.first as? any _Interactive else { return }
        node.pressBegan()
        node.pressEnded(inside: true)
        setNeedsDisplay()
    }
}

/// A shortcut node tells the menu walk its shortcut.
@MainActor
package protocol _ShortcutProviding: AnyObject {
    var _shortcut: KeyboardShortcut? { get }
}

extension KeyboardShortcutNode: _ShortcutProviding {
    package var _shortcut: KeyboardShortcut? { modifier.shortcut }
}
