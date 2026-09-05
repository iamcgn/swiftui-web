// The window toolbar (API/Toolbar.swift): `ToolbarNode`s register items while mounted; a host that
// paints window chrome gets a 52 pt bar across the top of the window (the macOS unified toolbar,
// measured 2026-09-04) holding the navigation title and the items in 36 pt capsule platters, and
// the content is laid out below it.

/// `toolbar`: transparent to layout; registers its items with the runtime.
@MainActor
package final class ToolbarNode<Content: View>: UnaryLayoutModifierNode<Content, _ToolbarModifier> {
    override package init(_ context: _NodeContext<ModifiedContent<Content, _ToolbarModifier>>) {
        super.init(context)
        runtime.registerToolbar(self, items: modifier.items)
    }

    override package func update(view: ModifiedContent<Content, _ToolbarModifier>, environment: EnvironmentValues, force: Bool) {
        super.update(view: view, environment: environment, force: force)
        runtime.registerToolbar(self, items: view.modifier.items)
    }

    override package func unmount() {
        runtime.unregisterToolbar(self)
        super.unmount()
    }
}

/// `toolbar(_:for:)`: hides the bar while mounted with `.hidden`.
@MainActor
package final class ToolbarVisibilityNode<Content: View>: UnaryLayoutModifierNode<Content, _ToolbarVisibilityModifier> {
    override package init(_ context: _NodeContext<ModifiedContent<Content, _ToolbarVisibilityModifier>>) {
        super.init(context)
        runtime.setToolbarVisibility(self, modifier.visibility)
    }

    override package func update(view: ModifiedContent<Content, _ToolbarVisibilityModifier>, environment: EnvironmentValues, force: Bool) {
        super.update(view: view, environment: environment, force: force)
        runtime.setToolbarVisibility(self, view.modifier.visibility)
    }

    override package func unmount() {
        runtime.setToolbarVisibility(self, nil)
        super.unmount()
    }
}

/// The bar's view: leading items, the title, principal items centred, trailing items.
struct _ToolbarBarView: View {
    let items: [_ToolbarItemData]
    let title: String?

    private func platters(_ group: ToolbarItemPlacement.Group) -> some View {
        ForEach(Array(items.enumerated()).filter { $0.element.placement.group == group }, id: \.offset) { entry in
            entry.element.view.fixedSize(horizontal: true, vertical: false)
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            platters(.leading)
            if let title {
                Text(title).font(.system(size: 15, weight: .bold)).lineLimit(1).padding(.leading, 8)
            }
            Spacer(minLength: 8)
            platters(.principal)
            Spacer(minLength: 8)
            platters(.trailing)
        }
        .padding(.horizontal, 8)
        .frame(height: Runtime.toolbarHeight)
        .buttonStyle(_ToolbarButtonStyle())
        .font(.system(size: 13, weight: .semibold))
    }
}

/// Toolbar buttons: the label in a 36 pt capsule platter (macOS 26's glass pill, approximated
/// as a translucent grey), darker while pressed.
struct _ToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 8)
            .frame(minWidth: 36, minHeight: 36, maxHeight: 36)
            .background(Capsule().fill(Color(.sRGB, white: 0.5, opacity: configuration.isPressed ? 0.3 : 0.12)))
    }
}

/// The runtime-owned bar node, laid out over the top of the window.
@MainActor
package final class ToolbarChromeNode: ViewNode {
    package private(set) var content: TypedNode<AnyView>!

    package init(runtime: Runtime, view: AnyView, environment: EnvironmentValues) {
        super.init(parent: runtime.root, runtime: runtime, environment: environment)
        content = AnyView._makeNode(_NodeContext(view: view, parent: self, environment: environment))
    }

    package func update(view: AnyView, environment: EnvironmentValues) {
        self.environment = environment
        content.update(view: view, environment: environment, force: false)
    }

    package func layout(in window: CGSize) {
        frame = CGRect(x: 0, y: 0, width: window.width, height: Runtime.toolbarHeight)
        for node in content.layoutChildren {
            node.place(at: .zero, anchor: .topLeading, proposal: ProposedViewSize(frame.size), by: self)
        }
    }

    override package func paint(into list: inout DisplayList, context: PaintContext) {
        let bar = context.absoluteRect(frame)
        list.append(.fillRect(bar, environment._windowBackground))
        let hairline = 1 / context.scale
        list.append(.fillRect(CGRect(x: bar.minX, y: bar.maxY - hairline, width: bar.width, height: hairline), environment._ink(0.12)))
        for node in content.layoutChildren {
            node.paint(into: &list, context: context.child(at: node.presentedFrame))
        }
    }

    override package var isLayoutNode: Bool { true }
    override package var structuralChildren: [ViewNode] { [content] }
    override package var layoutChildren: [ViewNode] { content.layoutChildren }
    override package var paintedChildren: [ViewNode] { content.layoutChildren }
    override package var nodeDescription: String { "Toolbar" }

    package var interactiveNodes: [ViewNode & _Interactive] {
        content.layoutChildren.flatMap { $0.collectNodes(where: { $0 is _Interactive }) }.compactMap { $0 as? (ViewNode & _Interactive) }
    }

    /// The interactive node under a window point, if the point is in the bar.
    package func interactiveNode(at point: CGPoint) -> (ViewNode & _Interactive)? {
        guard frame.contains(point) else { return nil }
        for node in content.layoutChildren.reversed() {
            let local = CGPoint(x: point.x - node.frame.minX, y: point.y - node.frame.minY)
            if let hit = node.hitTest(local, where: { $0 is _Interactive }) { return hit as? (ViewNode & _Interactive) }
        }
        return nil
    }
}

extension Runtime {
    /// The unified toolbar's height (macOS 26, measured on a titled window).
    public static let toolbarHeight: CGFloat = 52

    package func registerToolbar(_ node: ViewNode, items: [_ToolbarItemData]) {
        if let index = toolbarSources.firstIndex(where: { $0.node === node }) {
            toolbarSources[index].items = items
        } else {
            toolbarSources.append(ToolbarSource(node: node, items: items))
        }
        requestLayout()
    }

    package func unregisterToolbar(_ node: ViewNode) {
        toolbarSources.removeAll { $0.node === node || $0.node == nil }
        requestLayout()
    }

    package func setToolbarVisibility(_ node: ViewNode, _ visibility: Visibility?) {
        toolbarVisibility.removeAll { $0.node === node || $0.node == nil }
        if let visibility { toolbarVisibility.append(ToolbarVisibilitySource(node: node, visibility: visibility)) }
        requestLayout()
    }

    /// The items every mounted `toolbar` contributes, in tree order.
    public var toolbarItems: [_ToolbarItemData] {
        toolbarSources.filter { $0.node?.isMounted == true }.flatMap(\.items)
    }

    /// Whether the host should show a toolbar: chrome painting on, items present, not hidden.
    package var showsToolbar: Bool {
        paintsWindowChrome && !toolbarItems.isEmpty && !toolbarVisibility.contains { $0.node?.isMounted == true && $0.visibility == .hidden }
    }

    /// The bar's frame while it shows; the content is laid out below it.
    public var toolbarFrame: CGRect? { toolbar.map(\.frame) }

    /// Creates, refreshes or drops the bar for this layout pass.
    package func layoutToolbar(in size: CGSize) {
        guard showsToolbar else {
            toolbar?.unmount()
            toolbar = nil
            return
        }
        var environment = rootEnvironment
        environment.colorScheme = root.environment.colorScheme
        let view = AnyView(_ToolbarBarView(items: toolbarItems, title: chromeShowsTitle ? navigationTitle : nil))
        if let toolbar {
            toolbar.update(view: view, environment: environment)
        } else {
            toolbar = ToolbarChromeNode(runtime: self, view: view, environment: environment)
        }
        toolbar?.layout(in: size)
    }
}

/// One `toolbar` modifier's contribution.
package struct ToolbarSource {
    weak var node: ViewNode?
    var items: [_ToolbarItemData]
}

package struct ToolbarVisibilitySource {
    weak var node: ViewNode?
    var visibility: Visibility
}
