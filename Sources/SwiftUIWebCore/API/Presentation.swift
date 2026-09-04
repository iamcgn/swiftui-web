/// Sheets, popovers, alerts and menus: presented over the window by the runtime's presentation
/// layer (`Docs/elements/Presentation.md`). The looks are approximations: on macOS these are
/// separate windows the hosted golden window cannot capture.

/// An action that dismisses a presentation (or pops the enclosing navigation stack).
public struct DismissAction {
    package let action: @MainActor () -> Void
    package init(_ action: @escaping @MainActor () -> Void) { self.action = action }
    @MainActor public func callAsFunction() { action() }
}

package struct DismissKey: EnvironmentKey {
    package nonisolated(unsafe) static let defaultValue = DismissAction {}
}

package struct DismissesOnActivationKey: EnvironmentKey {
    package static let defaultValue = false
}

extension EnvironmentValues {
    /// An action that dismisses the current presentation.
    public var dismiss: DismissAction {
        get { self[DismissKey.self] }
        set { self[DismissKey.self] = newValue }
    }

    /// Whether buttons in this environment dismiss the presentation after their action (alerts).
    package var _dismissesOnActivation: Bool {
        get { self[DismissesOnActivationKey.self] }
        set { self[DismissesOnActivationKey.self] = newValue }
    }
}

/// How a presentation is shown.
public enum _PresentationKind: Sendable, Equatable {
    case sheet
    case popover(arrowEdge: Edge)
    case alert
    case menu
    /// A menu beside the row of a parent menu.
    case submenu

    package var isMenu: Bool { self == .menu || self == .submenu }
}

/// Where a popover attaches to its source view.
public enum PopoverAttachmentAnchor: Sendable {
    case rect(_AnchorSource)
    case point(UnitPoint)
}

public enum _AnchorSource: Sendable {
    case bounds
    case rect(CGRect)
}

/// The modifier behind `sheet`, `popover`, `alert` and friends: its body reads the binding so
/// observation tracks it; `_PresentationSync` presents and dismisses.
public struct _PresentationModifier {
    package let kind: _PresentationKind
    package let isPresented: Binding<Bool>
    package let onDismiss: _DismissBox?
    package let content: _PresentationContentBox

    package init(kind: _PresentationKind, isPresented: Binding<Bool>, onDismiss: (() -> Void)?, content: @escaping () -> AnyView) {
        self.kind = kind
        self.isPresented = isPresented
        self.onDismiss = onDismiss.map { _DismissBox($0) }
        self.content = _PresentationContentBox(content)
    }
}

/// Holds an `onDismiss` callback (a class so the runtime's field reflection ignores it).
package final class _DismissBox {
    package let run: () -> Void
    package init(_ run: @escaping () -> Void) { self.run = run }
}

/// Holds a presentation's content builder (a class so the runtime's field reflection ignores
/// it); the runtime calls it on the main actor.
package final class _PresentationContentBox {
    package let make: () -> AnyView
    package init(_ make: @escaping () -> AnyView) { self.make = make }
}

extension _PresentationModifier: ViewModifier {
    public func body(content: Content) -> some View {
        content.modifier(_PresentationSync(kind: kind, presented: isPresented.wrappedValue, binding: isPresented, onDismiss: onDismiss, content: self.content))
    }
}

public struct _PresentationSync {
    package let kind: _PresentationKind
    package let presented: Bool
    package let binding: Binding<Bool>
    package let onDismiss: _DismissBox?
    package let content: _PresentationContentBox

    package init(kind: _PresentationKind, presented: Bool, binding: Binding<Bool>, onDismiss: _DismissBox?, content: _PresentationContentBox) {
        self.kind = kind
        self.presented = presented
        self.binding = binding
        self.onDismiss = onDismiss
        self.content = content
    }
}

extension _PresentationSync: ViewModifier {
    public typealias Body = Never
    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        PresentationSyncNode(context)
    }
}

extension View {
    /// Presents a sheet when a binding to a Boolean value that you provide is true.
    nonisolated public func sheet<Content: View>(isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil,
                                                 @ViewBuilder content: @escaping () -> Content) -> some View {
        modifier(_PresentationModifier(kind: .sheet, isPresented: isPresented, onDismiss: onDismiss) { AnyView(content()) })
    }

    /// Presents a sheet using the given item as a data source for the sheet's content.
    nonisolated public func sheet<Item: Identifiable, Content: View>(item: Binding<Item?>, onDismiss: (() -> Void)? = nil,
                                                                     @ViewBuilder content: @escaping (Item) -> Content) -> some View {
        modifier(_PresentationModifier(kind: .sheet, isPresented: _itemBinding(item), onDismiss: onDismiss) {
            item.wrappedValue.map { AnyView(content($0)) } ?? AnyView(EmptyView())
        })
    }

    /// Presents a popover when a given condition is true.
    nonisolated public func popover<Content: View>(isPresented: Binding<Bool>, attachmentAnchor: PopoverAttachmentAnchor = .rect(.bounds),
                                                   arrowEdge: Edge = .top, @ViewBuilder content: @escaping () -> Content) -> some View {
        modifier(_PresentationModifier(kind: .popover(arrowEdge: arrowEdge), isPresented: isPresented, onDismiss: nil) { AnyView(content()) })
    }

    /// Presents a popover using the given item as a data source for the popover's content.
    nonisolated public func popover<Item: Identifiable, Content: View>(item: Binding<Item?>, attachmentAnchor: PopoverAttachmentAnchor = .rect(.bounds),
                                                                       arrowEdge: Edge = .top, @ViewBuilder content: @escaping (Item) -> Content) -> some View {
        modifier(_PresentationModifier(kind: .popover(arrowEdge: arrowEdge), isPresented: _itemBinding(item), onDismiss: nil) {
            item.wrappedValue.map { AnyView(content($0)) } ?? AnyView(EmptyView())
        })
    }

    /// Presents an alert with a message when a given condition is true.
    nonisolated public func alert<A: View, M: View>(_ title: Text, isPresented: Binding<Bool>, @ViewBuilder actions: @escaping () -> A,
                                                    @ViewBuilder message: @escaping () -> M) -> some View {
        modifier(_PresentationModifier(kind: .alert, isPresented: isPresented, onDismiss: nil) {
            AnyView(_AlertContent(title: title, message: AnyView(message()), actions: AnyView(actions())))
        })
    }

    nonisolated public func alert<A: View>(_ title: Text, isPresented: Binding<Bool>, @ViewBuilder actions: @escaping () -> A) -> some View {
        alert(title, isPresented: isPresented, actions: actions) { EmptyView() }
    }

    nonisolated public func alert<A: View, M: View>(_ titleKey: LocalizedStringKey, isPresented: Binding<Bool>, @ViewBuilder actions: @escaping () -> A,
                                                    @ViewBuilder message: @escaping () -> M) -> some View {
        alert(Text(titleKey), isPresented: isPresented, actions: actions, message: message)
    }

    nonisolated public func alert<A: View>(_ titleKey: LocalizedStringKey, isPresented: Binding<Bool>, @ViewBuilder actions: @escaping () -> A) -> some View {
        alert(Text(titleKey), isPresented: isPresented, actions: actions) { EmptyView() }
    }

    @_disfavoredOverload
    nonisolated public func alert<S: StringProtocol, A: View, M: View>(_ title: S, isPresented: Binding<Bool>, @ViewBuilder actions: @escaping () -> A,
                                                                        @ViewBuilder message: @escaping () -> M) -> some View {
        alert(Text(title), isPresented: isPresented, actions: actions, message: message)
    }

    @_disfavoredOverload
    nonisolated public func alert<S: StringProtocol, A: View>(_ title: S, isPresented: Binding<Bool>, @ViewBuilder actions: @escaping () -> A) -> some View {
        alert(Text(title), isPresented: isPresented, actions: actions) { EmptyView() }
    }

    /// Presents a confirmation dialog (an alert-like panel here) when a given condition is true.
    nonisolated public func confirmationDialog<A: View, M: View>(_ title: Text, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic,
                                                                 @ViewBuilder actions: @escaping () -> A, @ViewBuilder message: @escaping () -> M) -> some View {
        alert(title, isPresented: isPresented, actions: actions, message: message)
    }

    nonisolated public func confirmationDialog<A: View>(_ title: Text, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic,
                                                        @ViewBuilder actions: @escaping () -> A) -> some View {
        alert(title, isPresented: isPresented, actions: actions) { EmptyView() }
    }

    @_disfavoredOverload
    nonisolated public func confirmationDialog<S: StringProtocol, A: View>(_ title: S, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic,
                                                                            @ViewBuilder actions: @escaping () -> A) -> some View {
        alert(Text(title), isPresented: isPresented, actions: actions) { EmptyView() }
    }

    /// Adds an action to dismiss the presentation from buttons in a subtree (alerts).
    package func _dismissesOnActivation() -> some View { environment(\._dismissesOnActivation, true) }
}

/// A presence binding derived from an optional item: true while the item is non-nil, and
/// setting it to false clears the item.
nonisolated package func _itemBinding<Item>(_ item: Binding<Item?>) -> Binding<Bool> {
    Binding(get: { item.wrappedValue != nil }, set: { if !$0 { item.wrappedValue = nil } })
}

/// The alert panel's content: bold title, message, actions in a row; buttons dismiss.
package struct _AlertContent {
    package let title: Text
    package let message: AnyView
    package let actions: AnyView

    package init(title: Text, message: AnyView, actions: AnyView) {
        self.title = title
        self.message = message
        self.actions = actions
    }
}

extension _AlertContent: View {
    package var body: some View {
        VStack(spacing: 12) {
            title.font(.system(size: 13).bold()).multilineTextAlignment(.center)
            message.font(.system(size: 11)).foregroundStyle(Color.secondary).multilineTextAlignment(.center)
            HStack(spacing: 12) { actions }._dismissesOnActivation()
        }
        .padding(20)
        .frame(width: PlatformMetrics.alertWidth)
    }
}

/// A pop-up picker's menu: one row per option, the selected one checked; a press selects and dismisses.
package struct _MenuList: View {
    package let titles: [String]
    package let selected: Int?
    package let select: _MenuSelection

    package var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(titles.enumerated()), id: \.offset) { index, title in
                _MenuRow(title: title, checked: index == selected, index: index, select: select)
            }
        }
        .padding(.vertical, PlatformMetrics.menuVerticalPadding)
    }
}

package struct _MenuRow: View {
    package let title: String
    package let checked: Bool
    package let index: Int
    package let select: _MenuSelection
    @Environment(\.dismiss) private var dismiss

    package var body: some View {
        Button(action: { select.select(index); dismiss() }) {
            HStack(spacing: 0) {
                Text("✓").font(.system(size: 12)).opacity(checked ? 1 : 0).frame(width: PlatformMetrics.menuCheckWidth)
                Text(title).font(.system(size: PlatformMetrics.buttonLabelSize))
            }
            .padding(.trailing, PlatformMetrics.menuTrailingPadding)
            .frame(minWidth: PlatformMetrics.menuMinimumWidth, minHeight: PlatformMetrics.menuRowHeight, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}

/// Type-erased menu selection (a class so the runtime's field reflection ignores it).
package final class _MenuSelection {
    package let select: @MainActor (Int) -> Void
    package init(_ select: @escaping @MainActor (Int) -> Void) { self.select = select }
}
