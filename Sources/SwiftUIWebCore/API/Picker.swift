/// A control for selecting from a set of mutually exclusive values.
///
/// macOS geometry measured in `Docs/elements/Picker.md`: the default style is a pop-up button
/// (24 pt, the widest option plus 47.5), `.segmented` a row of equal segments (the widest option
/// plus 21, 24 pt tall), `.radioGroup` and `.inline` a column of 16 pt radio circles with
/// body-font labels; the label sits 8 pt before the control in the body font.
public struct Picker<Label: View, SelectionValue: Hashable, Content: View>: View {
    package let label: Label
    package let selection: Binding<SelectionValue>
    package let content: Content

    /// Creates a picker that displays a custom label.
    public init(selection: Binding<SelectionValue>, @ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
        self.label = label()
        self.selection = selection
        self.content = content()
    }

    @Environment(\.pickerStyle) private var style
    @Environment(\.labelsHidden) private var labelsHidden

    public var body: some View {
        let selected = AnyHashable(selection.wrappedValue)   // read here so observation tracks it
        let binding = selection
        _PickerHost(label: labelsHidden ? nil : AnyView(label), content: AnyView(content), selected: selected,
                    select: _PickerSelection { if let value = $0.base as? SelectionValue { binding.wrappedValue = value } },
                    style: style._kind)
    }
}

extension Picker where Label == Text {
    /// Creates a picker that generates its label from a localized string key.
    public init(_ titleKey: LocalizedStringKey, selection: Binding<SelectionValue>, @ViewBuilder content: () -> Content) {
        self.init(selection: selection, content: content) { Text(titleKey) }
    }

    /// Creates a picker that generates its label from a string.
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, selection: Binding<SelectionValue>, @ViewBuilder content: () -> Content) {
        self.init(selection: selection, content: content) { Text(title) }
    }
}

/// Type-erased selection setter (a class so the runtime's field reflection ignores it).
@MainActor
package final class _PickerSelection {
    package let select: (AnyHashable) -> Void
    package init(_ select: @escaping (AnyHashable) -> Void) { self.select = select }
}

/// The primitive a `Picker` resolves to (`PickerNode`).
public struct _PickerHost: View {
    package let label: AnyView?
    package let content: AnyView
    package let selected: AnyHashable
    package let select: _PickerSelection
    package let style: _PickerStyleKind

    package init(label: AnyView?, content: AnyView, selected: AnyHashable, select: _PickerSelection, style: _PickerStyleKind) {
        self.label = label
        self.content = content
        self.selected = selected
        self.select = select
        self.style = style
    }

    public typealias Body = Never

    public static func _makeNode(_ context: _NodeContext<_PickerHost>) -> TypedNode<_PickerHost> {
        PickerNode(context)
    }
}

// MARK: - Tags

package struct TagKey: LayoutValueKey {
    package nonisolated(unsafe) static let defaultValue: AnyHashable? = nil
}

extension View {
    /// Sets the unique tag value of this view (the selection value of a picker option).
    nonisolated public func tag<V: Hashable>(_ tag: V) -> some View {
        layoutValue(key: TagKey.self, value: AnyHashable(tag))
    }
}

// MARK: - Styles

/// How a picker lays out and paints its options.
public enum _PickerStyleKind: Sendable {
    case menu, segmented, radioGroup
}

/// A type that specifies the appearance and interaction of all pickers within a view hierarchy.
public protocol PickerStyle: Sendable {
    var _kind: _PickerStyleKind { get }
}

/// The default picker style, based on the picker's context (a pop-up button on macOS).
public struct DefaultPickerStyle: PickerStyle {
    public init() {}
    public var _kind: _PickerStyleKind { .menu }
}

/// A picker style that presents the options as a menu when the user presses a button.
public struct MenuPickerStyle: PickerStyle {
    public init() {}
    public var _kind: _PickerStyleKind { .menu }
}

/// A picker style that presents the options in a segmented control.
public struct SegmentedPickerStyle: PickerStyle {
    public init() {}
    public var _kind: _PickerStyleKind { .segmented }
}

/// A picker style that presents the options as a group of radio buttons.
public struct RadioGroupPickerStyle: PickerStyle {
    public init() {}
    public var _kind: _PickerStyleKind { .radioGroup }
}

/// A picker style that presents the options in a row or column (radio buttons on macOS).
public struct InlinePickerStyle: PickerStyle {
    public init() {}
    public var _kind: _PickerStyleKind { .radioGroup }
}

/// A picker style that presents the options as a compact row of icons (a menu here).
public struct PalettePickerStyle: PickerStyle {
    public init() {}
    public var _kind: _PickerStyleKind { .menu }
}

extension PickerStyle where Self == DefaultPickerStyle {
    public static var automatic: DefaultPickerStyle { DefaultPickerStyle() }
}
extension PickerStyle where Self == MenuPickerStyle {
    public static var menu: MenuPickerStyle { MenuPickerStyle() }
}
extension PickerStyle where Self == SegmentedPickerStyle {
    public static var segmented: SegmentedPickerStyle { SegmentedPickerStyle() }
}
extension PickerStyle where Self == RadioGroupPickerStyle {
    public static var radioGroup: RadioGroupPickerStyle { RadioGroupPickerStyle() }
}
extension PickerStyle where Self == InlinePickerStyle {
    public static var inline: InlinePickerStyle { InlinePickerStyle() }
}
extension PickerStyle where Self == PalettePickerStyle {
    public static var palette: PalettePickerStyle { PalettePickerStyle() }
}

package struct PickerStyleKey: EnvironmentKey {
    package static let defaultValue: any PickerStyle = DefaultPickerStyle()
}

extension EnvironmentValues {
    package var pickerStyle: any PickerStyle {
        get { self[PickerStyleKey.self] }
        set { self[PickerStyleKey.self] = newValue }
    }
}

extension View {
    /// Sets the style for pickers within this view.
    nonisolated public func pickerStyle<S: PickerStyle>(_ style: S) -> some View {
        environment(\.pickerStyle, style)
    }
}
