/// A type that collects multiple instances of a content type — like views, scenes, or commands —
/// into a single unit.
///
/// `Group` is transparent to layout: its children contribute directly to the enclosing container,
/// so `HStack { Group { A; B }; C }` lays out three children.
@frozen
public struct Group<Content> {
    @usableFromInline
    package let content: Content

    @usableFromInline
    package init(_content: Content) {
        self.content = _content
    }
}

extension Group: View where Content: View {
    public typealias Body = Never

    /// Creates a group of views.
    @inlinable
    public init(@ViewBuilder content: () -> Content) {
        self.init(_content: content())
    }
}

/// A group of toolbar items: its items join the enclosing toolbar's (Mlem's `MarkAllAsReadButton`
/// returns its `ToolbarItem`s in one).
extension Group: ToolbarContent where Content: ToolbarContent {
    /// Creates a group of toolbar content.
    public init(@ToolbarContentBuilder content: () -> Content) {
        self.init(_content: content())
    }

    public var body: Never { fatalError("Group has no body") }
    nonisolated public var _toolbarItems: [_ToolbarItemData] { content._toolbarItems }
}

extension Group: CustomizableToolbarContent where Content: CustomizableToolbarContent {}

/// A group of commands: its menus join the enclosing `commands`.
extension Group: Commands where Content: Commands {
    /// Creates a group of commands.
    public init(@CommandsBuilder content: () -> Content) {
        self.init(_content: content())
    }

    public var body: Never { fatalError("Group has no body") }
    nonisolated public var _commandMenus: [_CommandMenuData] { content._commandMenus }
}
