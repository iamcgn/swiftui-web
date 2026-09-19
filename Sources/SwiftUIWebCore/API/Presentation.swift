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
    /// A confirmation dialog: an alert on macOS; on iOS a glass panel above its source.
    case dialog
    case menu
    /// A menu beside the row of a parent menu.
    case submenu
    /// A secondary window (`openWindow`): a floating panel with a title bar, non-modal.
    case window(title: String?, size: CGSize?)

    package var isMenu: Bool { self == .menu || self == .submenu }
    package var isWindow: Bool { if case .window = self { return true } else { return false } }
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

    /// Presents a confirmation dialog when a given condition is true: an alert-like panel on
    /// macOS, a glass panel above the source on iOS (`titleVisibility` hides the title).
    nonisolated public func confirmationDialog<A: View, M: View>(_ title: Text, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic,
                                                                 @ViewBuilder actions: @escaping () -> A, @ViewBuilder message: @escaping () -> M) -> some View {
        modifier(_PresentationModifier(kind: .dialog, isPresented: isPresented, onDismiss: nil) {
            AnyView(_DialogContent(title: titleVisibility == .hidden ? nil : title, message: AnyView(message()), actions: AnyView(actions())))
        })
    }

    nonisolated public func confirmationDialog<A: View>(_ title: Text, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic,
                                                        @ViewBuilder actions: @escaping () -> A) -> some View {
        confirmationDialog(title, isPresented: isPresented, titleVisibility: titleVisibility, actions: actions) { EmptyView() }
    }

    @_disfavoredOverload
    nonisolated public func confirmationDialog<S: StringProtocol, A: View>(_ title: S, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic,
                                                                            @ViewBuilder actions: @escaping () -> A) -> some View {
        confirmationDialog(Text(title), isPresented: isPresented, titleVisibility: titleVisibility, actions: actions) { EmptyView() }
    }

    @_disfavoredOverload
    nonisolated public func confirmationDialog<S: StringProtocol, A: View, M: View>(_ title: S, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic,
                                                                                     @ViewBuilder actions: @escaping () -> A, @ViewBuilder message: @escaping () -> M) -> some View {
        confirmationDialog(Text(title), isPresented: isPresented, titleVisibility: titleVisibility, actions: actions, message: message)
    }

    nonisolated public func confirmationDialog<A: View>(_ titleKey: LocalizedStringKey, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic,
                                                        @ViewBuilder actions: @escaping () -> A) -> some View {
        confirmationDialog(Text(titleKey), isPresented: isPresented, titleVisibility: titleVisibility, actions: actions) { EmptyView() }
    }

    nonisolated public func confirmationDialog<A: View, M: View>(_ titleKey: LocalizedStringKey, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic,
                                                                 @ViewBuilder actions: @escaping () -> A, @ViewBuilder message: @escaping () -> M) -> some View {
        confirmationDialog(Text(titleKey), isPresented: isPresented, titleVisibility: titleVisibility, actions: actions, message: message)
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
        _AlertBody(title: title, message: message, actions: actions)
    }
}

/// The alert's layout per platform: macOS centres a 13 pt title, an 11 pt secondary message
/// and the buttons in a row inside 20 pt; iOS (ios/alert/basic) left-aligns a 17 pt bold title
/// and a 15 pt message 15 in from the capsule buttons, which share the width, the cancel button
/// first (Docs/elements/iOS.md).
private struct _AlertBody: View {
    let title: Text
    let message: AnyView
    let actions: AnyView
    @Environment(\.platformProfile) private var profile

    var body: some View {
        let m = profile.metrics
        if profile.isIOS {
            VStack(alignment: .leading, spacing: 0) {
                title.font(.system(size: m.alertTitleSize, weight: .bold)).padding(.horizontal, m.alertTextInset).padding(.bottom, m.alertTitleMessageGap)
                message.font(.system(size: m.alertMessageSize)).padding(.horizontal, m.alertTextInset)
                _AlertActionsLayout(vertical: false, spacing: m.alertButtonGap, height: m.alertButtonHeight) { actions }
                    .buttonStyle(_AlertButtonStyle(height: m.alertButtonHeight, fillAlpha: m.alertButtonFillAlpha, destructive: m.alertDestructiveColor, size: m.alertTitleSize, dialog: false))
                    ._dismissesOnActivation()
                    .padding(.top, m.alertMessageButtonsGap)
            }
            .padding(m.alertInsets)
            .frame(width: m.alertWidth)
        } else {
            VStack(spacing: 12) {
                title.font(.system(size: 13).bold()).multilineTextAlignment(.center)
                message.font(.system(size: 11)).foregroundStyle(Color.secondary).multilineTextAlignment(.center)
                HStack(spacing: 12) { actions }._dismissesOnActivation()
            }
            .padding(20)
            .frame(width: m.alertWidth)
        }
    }
}

/// A confirmation dialog's content: the alert's on macOS; on iOS (ios/dialog/basic) a 17 pt
/// bold title, a 17 pt message and the actions stacked as full-width capsules, cancel buttons
/// left out (the panel dismisses on a tap outside).
package struct _DialogContent {
    package let title: Text?
    package let message: AnyView
    package let actions: AnyView
    @Environment(\.platformProfile) private var profile

    package init(title: Text?, message: AnyView, actions: AnyView) {
        self.title = title
        self.message = message
        self.actions = actions
    }
}

extension _DialogContent: View {
    package var body: some View {
        let m = profile.metrics
        if profile.isIOS {
            VStack(alignment: .leading, spacing: 0) {
                if let title {
                    title.font(.system(size: m.dialogTitleSize, weight: .bold)).padding(.horizontal, m.dialogTextInset).padding(.bottom, m.dialogTitleMessageGap)
                }
                message.font(.system(size: m.dialogMessageSize)).padding(.horizontal, m.dialogTextInset)
                _AlertActionsLayout(vertical: true, spacing: m.dialogButtonGap, height: m.dialogButtonHeight) { actions }
                    .buttonStyle(_AlertButtonStyle(height: m.dialogButtonHeight, fillAlpha: m.dialogButtonFillAlpha, destructive: m.alertDestructiveColor, size: m.dialogTitleSize, dialog: true))
                    ._dismissesOnActivation()
                    .padding(.top, m.dialogMessageButtonsGap)
            }
            .padding(m.dialogInsets)
            .frame(width: m.dialogWidth)
        } else {
            _AlertBody(title: title ?? Text(""), message: message, actions: actions)
        }
    }
}

/// The role of an alert action, read by `_AlertActionsLayout`.
package struct _ButtonRoleKey: LayoutValueKey {
    package static let defaultValue: ButtonRole? = nil
}

/// iOS alert and dialog buttons: capsules. The cancel role fills with the accent under a bold
/// white label, the destructive role shows red, the rest the accent (alerts) or the primary
/// colour (dialogs) on a grey fill.
package struct _AlertButtonStyle: ButtonStyle {
    let height: CGFloat
    let fillAlpha: Double
    let destructive: RGBA
    let size: CGFloat
    let dialog: Bool

    package func makeBody(configuration: Configuration) -> some View {
        let cancel = configuration.role == .cancel && !dialog
        let color: Color = configuration.role == .destructive ? Color(red: destructive.red, green: destructive.green, blue: destructive.blue)
            : cancel ? .white : dialog ? .primary : .accentColor
        return configuration.label
            .font(.system(size: size, weight: cancel ? .semibold : .regular))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
            .background(Capsule().fill(cancel ? Color.accentColor : Color.black.opacity(fillAlpha)))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Places alert actions: in a row sharing the width with the cancel button first, or stacked
/// full width with cancel buttons left out (iOS dialogs).
package struct _AlertActionsLayout: Layout {
    let vertical: Bool
    let spacing: CGFloat
    let height: CGFloat

    private func shown(_ subviews: Subviews) -> [Subviews.Element] {
        let ordered = subviews.sorted { ($0[_ButtonRoleKey.self] == .cancel ? 0 : 1) < ($1[_ButtonRoleKey.self] == .cancel ? 0 : 1) }
        return vertical ? ordered.filter { $0[_ButtonRoleKey.self] != .cancel } : ordered
    }

    package func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let count = CGFloat(shown(subviews).count)
        guard count > 0 else { return .zero }
        let width = proposal.width ?? subviews.map { $0.sizeThatFits(.unspecified).width }.reduce(0, +)
        return CGSize(width: width, height: vertical ? count * height + (count - 1) * spacing : height)
    }

    package func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let visible = shown(subviews)
        let hidden = subviews.filter { subview in !visible.contains { $0 == subview } }
        for subview in hidden { subview.place(at: bounds.origin, proposal: ProposedViewSize(width: 0, height: 0)) }
        guard !visible.isEmpty else { return }
        if vertical {
            var y = bounds.minY
            for subview in visible {
                subview.place(at: CGPoint(x: bounds.minX, y: y), proposal: ProposedViewSize(width: bounds.width, height: height))
                y += height + spacing
            }
        } else {
            let width = (bounds.width - spacing * CGFloat(visible.count - 1)) / CGFloat(visible.count)
            var x = bounds.minX
            for subview in visible {
                subview.place(at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(width: width, height: height))
                x += width + spacing
            }
        }
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

// MARK: - Sheet options

/// A height a sheet can rest at (iOS): the full height, half of it, a fraction or a point
/// height. The runtime honours `medium` and `large`; the others resolve to their heights.
public enum PresentationDetent: Hashable, Sendable {
    case medium
    case large
    case fraction(CGFloat)
    case height(CGFloat)
}

/// `presentationDetents` and `presentationDragIndicator`: the sheet's options, told to the
/// presentation node above (`PresentationOptionsNode`).
public struct _PresentationOptionsModifier {
    package let detents: Set<PresentationDetent>?
    package let dragIndicator: Visibility?
}

extension _PresentationOptionsModifier: ViewModifier {
    public typealias Body = Never
    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        PresentationOptionsNode(context)
    }
}

extension View {
    /// Sets the heights the sheet presenting this view can rest at.
    nonisolated public func presentationDetents(_ detents: Set<PresentationDetent>) -> some View {
        modifier(_PresentationOptionsModifier(detents: detents, dragIndicator: nil))
    }

    /// Sets the heights and a binding to the selected one (the binding is not written here).
    nonisolated public func presentationDetents(_ detents: Set<PresentationDetent>, selection: Binding<PresentationDetent>) -> some View {
        modifier(_PresentationOptionsModifier(detents: detents, dragIndicator: nil))
    }

    /// Shows or hides the sheet's drag indicator.
    nonisolated public func presentationDragIndicator(_ visibility: Visibility) -> some View {
        modifier(_PresentationOptionsModifier(detents: nil, dragIndicator: visibility))
    }
}
