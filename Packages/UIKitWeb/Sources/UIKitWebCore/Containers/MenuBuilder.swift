// The menu systems (UIKit's `UIMenuSystem`): the main menu is built at launch from the standard
// menus by `UIResponder.buildMenu(with:)` on the application and the app delegate. A page has
// no menu bar to show it in; its key commands (⌘N and the like) are matched after the responder
// chain's own (Events/Keyboard.swift) and sent down the chain as selectors (decision 0023).
import WebFoundation   // Foundation everywhere, and the Selector stand-in where ObjectiveC is absent

/// The object that builds the app's menus.
@MainActor
public protocol UIMenuBuilder {
    var system: UIMenuSystem { get }
    func menu(for identifier: UIMenu.Identifier) -> UIMenu?
    func action(for identifier: UIAction.Identifier) -> UIAction?
    func command(for action: Selector, propertyList: Any?) -> UICommand?
    func replace(menu replacedIdentifier: UIMenu.Identifier, with replacementMenu: UIMenu)
    func replaceChildren(ofMenu parentIdentifier: UIMenu.Identifier, from childrenBlock: ([UIMenuElement]) -> [UIMenuElement])
    func insertSibling(_ siblingMenu: UIMenu, beforeMenu siblingIdentifier: UIMenu.Identifier)
    func insertSibling(_ siblingMenu: UIMenu, afterMenu siblingIdentifier: UIMenu.Identifier)
    func insertChild(_ childMenu: UIMenu, atStartOfMenu parentIdentifier: UIMenu.Identifier)
    func insertChild(_ childMenu: UIMenu, atEndOfMenu parentIdentifier: UIMenu.Identifier)
    func remove(menu removedIdentifier: UIMenu.Identifier)
}

/// A menu system: the main menu bar's, or the context menus'.
@MainActor
public final class UIMenuSystem {
    public static let main = UIMenuSystem(name: "main")
    public static let context = UIMenuSystem(name: "context")

    let name: String
    /// The built root menu (`UIMenu.Identifier.root`), nil before the first build.
    public private(set) var rootMenu: UIMenu?
    private var needsRebuild = false

    init(name: String) { self.name = name }

    /// Rebuilds the menus on the next rebuild pass (at once when the app has launched).
    public func setNeedsRebuild() {
        needsRebuild = true
        if UIApplication.shared.delegate != nil { rebuildIfNeeded() }
    }

    public func setNeedsRevalidate() {}

    func rebuildIfNeeded() {
        guard needsRebuild, self === UIMenuSystem.main else { return }
        needsRebuild = false
        let builder = MainMenuBuilder(system: self)
        UIApplication.shared.buildMenu(with: builder)
        if let delegate = UIApplication.shared.delegate as? UIResponder, delegate !== UIApplication.shared {
            delegate.buildMenu(with: builder)
        }
        rootMenu = builder.root
    }

    /// Every key command in the built menus, submenus included.
    var keyCommands: [UIKeyCommand] {
        guard let rootMenu else { return [] }
        func collect(_ elements: [UIMenuElement]) -> [UIKeyCommand] {
            elements.flatMap { element -> [UIKeyCommand] in
                if let command = element as? UIKeyCommand { return [command] }
                if let menu = element as? UIMenu { return collect(menu.children) }
                return []
            }
        }
        return collect(rootMenu.children)
    }
}

/// The main menu's builder: a tree of the standard menus the delegate edits.
@MainActor
final class MainMenuBuilder: UIMenuBuilder {
    let system: UIMenuSystem
    private(set) var root: UIMenu

    init(system: UIMenuSystem) {
        self.system = system
        root = MainMenuBuilder.standardMenus()
    }

    /// The standard menu bar: the application, File, Edit, Format, View, Window and Help menus,
    /// with the edit commands that reach the responder chain as selectors.
    static func standardMenus() -> UIMenu {
        func key(_ title: String, _ selector: String, _ input: String, _ flags: UIKeyModifierFlags = .command) -> UIKeyCommand {
            UIKeyCommand(title: title, action: Selector(selector), input: input, modifierFlags: flags)
        }
        let standardEdit = UIMenu(identifier: .standardEdit, options: .displayInline, children: [
            key("Cut", "cut:", "x"), key("Copy", "copy:", "c"), key("Paste", "paste:", "v"),
            key("Delete", "delete:", "\u{08}", []), key("Select All", "selectAll:", "a"),
        ])
        let undoRedo = UIMenu(identifier: .undoRedo, options: .displayInline, children: [
            key("Undo", "undo:", "z"), key("Redo", "redo:", "z", [.command, .shift]),
        ])
        return UIMenu(identifier: .root, children: [
            UIMenu(title: "Application", identifier: .application, children: [
                UIMenu(identifier: .about, options: .displayInline), UIMenu(identifier: .preferences, options: .displayInline),
                UIMenu(identifier: .services, options: .displayInline), UIMenu(identifier: .hide, options: .displayInline),
                UIMenu(identifier: .quit, options: .displayInline),
            ]),
            UIMenu(title: "File", identifier: .file, children: [
                UIMenu(identifier: .newScene, options: .displayInline), UIMenu(identifier: .openRecent, options: .displayInline),
                UIMenu(identifier: .close, options: .displayInline), UIMenu(identifier: .print, options: .displayInline),
            ]),
            UIMenu(title: "Edit", identifier: .edit, children: [
                undoRedo, standardEdit,
                UIMenu(identifier: .find, options: .displayInline), UIMenu(identifier: .spelling, options: .displayInline),
                UIMenu(identifier: .substitutions, options: .displayInline), UIMenu(identifier: .transformations, options: .displayInline),
                UIMenu(identifier: .speech, options: .displayInline),
            ]),
            UIMenu(title: "Format", identifier: .format, children: [
                UIMenu(title: "Font", identifier: .font), UIMenu(title: "Text", identifier: .text),
            ]),
            UIMenu(title: "View", identifier: .view, children: [
                UIMenu(identifier: .toolbar, options: .displayInline), UIMenu(identifier: .sidebar, options: .displayInline),
                UIMenu(identifier: .fullscreen, options: .displayInline),
            ]),
            UIMenu(title: "Window", identifier: .window, children: [
                UIMenu(identifier: .minimizeAndZoom, options: .displayInline), UIMenu(identifier: .bringAllToFront, options: .displayInline),
            ]),
            UIMenu(title: "Help", identifier: .help),
        ])
    }

    // MARK: Lookup

    private func find(_ identifier: UIMenu.Identifier, in menu: UIMenu) -> (parent: UIMenu, index: Int)? {
        for (index, child) in menu.children.enumerated() {
            if let submenu = child as? UIMenu {
                if submenu.identifier == identifier { return (menu, index) }
                if let found = find(identifier, in: submenu) { return found }
            }
        }
        return nil
    }

    func menu(for identifier: UIMenu.Identifier) -> UIMenu? {
        if identifier == .root { return root }
        guard let (parent, index) = find(identifier, in: root) else { return nil }
        return parent.children[index] as? UIMenu
    }

    func action(for identifier: UIAction.Identifier) -> UIAction? {
        root.flattenedActions.first { $0.identifier == identifier }
    }

    func command(for action: Selector, propertyList: Any?) -> UICommand? {
        func search(_ elements: [UIMenuElement]) -> UICommand? {
            for element in elements {
                if let command = element as? UICommand, command.action == action { return command }
                if let menu = element as? UIMenu, let found = search(menu.children) { return found }
            }
            return nil
        }
        return search(root.children)
    }

    // MARK: Edits (the standard menus are mutable in place; a replaced menu keeps its place)

    private func replace(at place: (parent: UIMenu, index: Int), with menu: UIMenu) {
        place.parent.children[place.index] = menu
    }

    func replace(menu replacedIdentifier: UIMenu.Identifier, with replacementMenu: UIMenu) {
        if replacedIdentifier == .root { root = replacementMenu; return }
        guard let place = find(replacedIdentifier, in: root) else { return }
        replace(at: place, with: replacementMenu)
    }

    func replaceChildren(ofMenu parentIdentifier: UIMenu.Identifier, from childrenBlock: ([UIMenuElement]) -> [UIMenuElement]) {
        guard let menu = menu(for: parentIdentifier) else { return }
        menu.children = childrenBlock(menu.children)
    }

    func insertSibling(_ siblingMenu: UIMenu, beforeMenu siblingIdentifier: UIMenu.Identifier) {
        guard let place = find(siblingIdentifier, in: root) else { return }
        place.parent.children.insert(siblingMenu, at: place.index)
    }

    func insertSibling(_ siblingMenu: UIMenu, afterMenu siblingIdentifier: UIMenu.Identifier) {
        guard let place = find(siblingIdentifier, in: root) else { return }
        place.parent.children.insert(siblingMenu, at: place.index + 1)
    }

    func insertChild(_ childMenu: UIMenu, atStartOfMenu parentIdentifier: UIMenu.Identifier) {
        menu(for: parentIdentifier)?.children.insert(childMenu, at: 0)
    }

    func insertChild(_ childMenu: UIMenu, atEndOfMenu parentIdentifier: UIMenu.Identifier) {
        menu(for: parentIdentifier)?.children.append(childMenu)
    }

    func remove(menu removedIdentifier: UIMenu.Identifier) {
        guard let place = find(removedIdentifier, in: root) else { return }
        place.parent.children.remove(at: place.index)
    }
}
