// Commands (Docs/elements/Windows.md, sw-windows): `Scene.commands` declares the app's menus —
// `CommandMenu`s of their own and `CommandGroup`s placed in the standard ones. The runtime
// mounts every menu's content in a hidden tree so its `keyboardShortcut`s work in every host;
// the native host builds `NSApp.mainMenu` from `Runtime.commandMenus`.

/// Conforming types represent a group of related commands that can be exposed to the user via
/// the main menu on macOS and key commands on iOS.
public protocol Commands {
    associatedtype Body: Commands
    @CommandsBuilder var body: Body { get }
    /// The resolved menus (primitive commands override this).
    var _commandMenus: [_CommandMenuData] { get }
}

extension Commands {
    public var _commandMenus: [_CommandMenuData] { body._commandMenus }
}

/// An empty group of commands.
public struct EmptyCommands: Commands {
    public init() {}
    public var body: Never { fatalError("EmptyCommands has no body") }
    public var _commandMenus: [_CommandMenuData] { [] }
}

extension Never: Commands {
    public var _commandMenus: [_CommandMenuData] { [] }
}

/// A resolved menu: a `CommandMenu` (its own title) or a `CommandGroup` (a placement in a
/// standard menu) with its content, whose buttons, toggles, pickers and dividers are its items.
public struct _CommandMenuData {
    public enum Position: Sendable { case menu, before, after, replacing }
    public let title: String?
    public let placement: CommandGroupPlacement?
    public let position: Position
    public let content: AnyView

    public init(title: String?, placement: CommandGroupPlacement?, position: Position, content: AnyView) {
        self.title = title
        self.placement = placement
        self.position = position
        self.content = content
    }
}

/// Command menus and groups collected by `commands`.
public struct _CommandsGroup: Commands {
    public let menus: [_CommandMenuData]
    public init(_ menus: [_CommandMenuData]) { self.menus = menus }
    public var body: Never { fatalError("_CommandsGroup has no body") }
    public var _commandMenus: [_CommandMenuData] { menus }
}

@resultBuilder
public enum CommandsBuilder {
    public static func buildBlock() -> EmptyCommands { EmptyCommands() }
    public static func buildBlock<C: Commands>(_ c: C) -> C { c }
    public static func buildBlock<each C: Commands>(_ c: repeat each C) -> _CommandsGroup {
        var menus: [_CommandMenuData] = []
        for command in repeat each c { menus += command._commandMenus }
        return _CommandsGroup(menus)
    }
    public static func buildOptional<C: Commands>(_ c: C?) -> _CommandsGroup { _CommandsGroup(c?._commandMenus ?? []) }
    public static func buildEither<C: Commands>(first c: C) -> _CommandsGroup { _CommandsGroup(c._commandMenus) }
    public static func buildEither<C: Commands>(second c: C) -> _CommandsGroup { _CommandsGroup(c._commandMenus) }
    public static func buildExpression<C: Commands>(_ c: C) -> C { c }
}

/// Command menus that are added to the app's main menu.
public struct CommandMenu<Content: View>: Commands {
    package let name: String
    package let content: Content

    public init(_ nameKey: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        name = Text(nameKey).resolvedString
        self.content = content()
    }

    @_disfavoredOverload
    public init<S: StringProtocol>(_ name: S, @ViewBuilder content: () -> Content) {
        self.name = String(name)
        self.content = content()
    }

    public init(_ name: Text, @ViewBuilder content: () -> Content) {
        self.name = name.resolvedString
        self.content = content()
    }

    public var body: Never { fatalError("CommandMenu has no body") }
    public var _commandMenus: [_CommandMenuData] { [_CommandMenuData(title: name, placement: nil, position: .menu, content: AnyView(content))] }
}

/// Groups of controls that you can add to existing command menus.
public struct CommandGroup<Content: View>: Commands {
    package let placement: CommandGroupPlacement
    package let position: _CommandMenuData.Position
    package let content: Content

    public init(before placement: CommandGroupPlacement, @ViewBuilder addition: () -> Content) {
        self.placement = placement; position = .before; content = addition()
    }
    public init(after placement: CommandGroupPlacement, @ViewBuilder addition: () -> Content) {
        self.placement = placement; position = .after; content = addition()
    }
    public init(replacing placement: CommandGroupPlacement, @ViewBuilder addition: () -> Content) {
        self.placement = placement; position = .replacing; content = addition()
    }

    public var body: Never { fatalError("CommandGroup has no body") }
    public var _commandMenus: [_CommandMenuData] { [_CommandMenuData(title: nil, placement: placement, position: position, content: AnyView(content))] }
}

/// Identifier types for standard locations that new command groups can be placed relative to.
public struct CommandGroupPlacement: Hashable, Sendable {
    package let name: String
    package init(_ name: String) { self.name = name }

    public static let appInfo = CommandGroupPlacement("appInfo")
    public static let appSettings = CommandGroupPlacement("appSettings")
    public static let systemServices = CommandGroupPlacement("systemServices")
    public static let appVisibility = CommandGroupPlacement("appVisibility")
    public static let appTermination = CommandGroupPlacement("appTermination")
    public static let newItem = CommandGroupPlacement("newItem")
    public static let saveItem = CommandGroupPlacement("saveItem")
    public static let importExport = CommandGroupPlacement("importExport")
    public static let printItem = CommandGroupPlacement("printItem")
    public static let undoRedo = CommandGroupPlacement("undoRedo")
    public static let pasteboard = CommandGroupPlacement("pasteboard")
    public static let textEditing = CommandGroupPlacement("textEditing")
    public static let textFormatting = CommandGroupPlacement("textFormatting")
    public static let toolbar = CommandGroupPlacement("toolbar")
    public static let sidebar = CommandGroupPlacement("sidebar")
    public static let windowSize = CommandGroupPlacement("windowSize")
    public static let windowArrangement = CommandGroupPlacement("windowArrangement")
    public static let windowList = CommandGroupPlacement("windowList")
    public static let singleWindowList = CommandGroupPlacement("singleWindowList")
    public static let help = CommandGroupPlacement("help")

    /// The standard menu a placement lives in (the native host's menu bar).
    public var menuTitle: String {
        switch name {
        case "newItem", "saveItem", "importExport", "printItem": return "File"
        case "undoRedo", "pasteboard", "textEditing", "textFormatting": return "Edit"
        case "toolbar", "sidebar": return "View"
        case "windowSize", "windowArrangement", "windowList", "singleWindowList": return "Window"
        case "help": return "Help"
        default: return "App"
        }
    }
}

/// The standard toolbar commands (Show/Hide Toolbar, Customize Toolbar…): the native host's
/// menu bar carries them for the painted chrome; nothing to add elsewhere.
public struct ToolbarCommands: Commands {
    public init() {}
    public var body: Never { fatalError("ToolbarCommands has no body") }
    public var _commandMenus: [_CommandMenuData] { [] }
}

/// The standard sidebar command (Show/Hide Sidebar, ⌃⌘S): the runtime handles the shortcut.
public struct SidebarCommands: Commands {
    public init() {}
    public var body: Never { fatalError("SidebarCommands has no body") }
    public var _commandMenus: [_CommandMenuData] { [] }
}

/// The standard text editing commands (the responder edit actions handle them).
public struct TextEditingCommands: Commands {
    public init() {}
    public var body: Never { fatalError("TextEditingCommands has no body") }
    public var _commandMenus: [_CommandMenuData] { [] }
}

/// The standard text formatting commands (accepted).
public struct TextFormattingCommands: Commands {
    public init() {}
    public var body: Never { fatalError("TextFormattingCommands has no body") }
    public var _commandMenus: [_CommandMenuData] { [] }
}

/// Importing from devices (accepted: no devices on the web).
public struct ImportFromDevicesCommands: Commands {
    public init() {}
    public var body: Never { fatalError("ImportFromDevicesCommands has no body") }
    public var _commandMenus: [_CommandMenuData] { [] }
}

/// The inspector commands (accepted).
public struct InspectorCommands: Commands {
    public init() {}
    public var body: Never { fatalError("InspectorCommands has no body") }
    public var _commandMenus: [_CommandMenuData] { [] }
}
