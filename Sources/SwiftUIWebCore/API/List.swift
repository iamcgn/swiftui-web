/// A container that presents rows of data arranged in a single column, optionally providing
/// the ability to select one or more members.
///
/// macOS geometry measured in `Docs/elements/List.md`: rows are their content plus 4 pt above
/// and below (at least 24 pt), 16 pt in from both edges for the inset style (8 for plain, 7 for
/// bordered), separated by 1 pt lines; section headers and footers use the semibold subheadline
/// font in the secondary colour with 6 pt of padding, sections are 20 pt apart, the content
/// starts 10 pt down. The list scrolls vertically and paints an opaque background.
public struct List<SelectionValue: Hashable, Content: View>: View {
    package let content: Content
    package let selection: _ListSelection?

    /// Creates a list with the given content.
    public init(@ViewBuilder content: () -> Content) where SelectionValue == Never {
        self.content = content()
        self.selection = nil
    }

    /// Creates a list with the given content that supports selecting a single row.
    public init(selection: Binding<SelectionValue?>?, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.selection = _ListSelection.single(selection)
    }

    /// Creates a list with the given content that supports selecting multiple rows.
    public init(selection: Binding<Set<SelectionValue>>?, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.selection = _ListSelection.multiple(selection)
    }

    @Environment(\.listStyle) private var style

    public var body: some View {
        let profile = style._profile
        let pinnedTitle = profile.name == "sidebar" ? nil : _firstSectionTitle(of: content)
        ScrollView(.vertical) {
            _ListContent(content: content, selection: selection, profile: profile, pinsFirstHeader: pinnedTitle != nil)
        }
        .background(profile.background)
        .overlay(alignment: .top) { _ListPinnedHeader(title: pinnedTitle, profile: profile) }
        .border(profile.borderColor ?? Color.clear, width: profile.borderColor == nil ? 0 : PlatformMetrics.listBorderWidth)
    }
}

extension List {
    /// Creates a list that identifies its rows by the given key path.
    public init<Data: RandomAccessCollection, ID: Hashable, RowContent: View>(
        _ data: Data, id: KeyPath<Data.Element, ID>, selection: Binding<SelectionValue?>? = nil,
        @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
    ) where Content == ForEach<Data, ID, RowContent> {
        self.content = ForEach(data, id: id, content: rowContent)
        self.selection = _ListSelection.single(selection)
    }

    /// Creates a list that computes its rows from identifiable data.
    public init<Data: RandomAccessCollection, RowContent: View>(
        _ data: Data, selection: Binding<SelectionValue?>? = nil, @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
    ) where Content == ForEach<Data, Data.Element.ID, RowContent>, Data.Element: Identifiable {
        self.content = ForEach(data, content: rowContent)
        self.selection = _ListSelection.single(selection)
    }

    /// Creates a list over a range of integers.
    public init<RowContent: View>(_ data: Range<Int>, selection: Binding<SelectionValue?>? = nil,
                                  @ViewBuilder rowContent: @escaping (Int) -> RowContent) where Content == ForEach<Range<Int>, Int, RowContent> {
        self.content = ForEach(data, content: rowContent)
        self.selection = _ListSelection.single(selection)
    }

    /// Identifiable data with multiple selection.
    public init<Data: RandomAccessCollection, RowContent: View>(
        _ data: Data, selection: Binding<Set<SelectionValue>>?, @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
    ) where Content == ForEach<Data, Data.Element.ID, RowContent>, Data.Element: Identifiable {
        self.content = ForEach(data, content: rowContent)
        self.selection = _ListSelection.multiple(selection)
    }

    public init<Data: RandomAccessCollection, ID: Hashable, RowContent: View>(
        _ data: Data, id: KeyPath<Data.Element, ID>, selection: Binding<Set<SelectionValue>>?,
        @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
    ) where Content == ForEach<Data, ID, RowContent> {
        self.content = ForEach(data, id: id, content: rowContent)
        self.selection = _ListSelection.multiple(selection)
    }
}

extension List where SelectionValue == Never {
    public init<Data: RandomAccessCollection, ID: Hashable, RowContent: View>(
        _ data: Data, id: KeyPath<Data.Element, ID>, @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
    ) where Content == ForEach<Data, ID, RowContent> {
        self.content = ForEach(data, id: id, content: rowContent)
        self.selection = nil
    }

    public init<Data: RandomAccessCollection, RowContent: View>(
        _ data: Data, @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
    ) where Content == ForEach<Data, Data.Element.ID, RowContent>, Data.Element: Identifiable {
        self.content = ForEach(data, content: rowContent)
        self.selection = nil
    }

    public init<RowContent: View>(_ data: Range<Int>, @ViewBuilder rowContent: @escaping (Int) -> RowContent)
    where Content == ForEach<Range<Int>, Int, RowContent> {
        self.content = ForEach(data, content: rowContent)
        self.selection = nil
    }
}

/// A list's selection binding, type-erased (a class so the runtime's field reflection ignores it).
@MainActor
package final class _ListSelection {
    package let isSelected: (AnyHashable) -> Bool
    package let toggle: (AnyHashable) -> Void

    package init<V: Hashable>(single binding: Binding<V?>) {
        isSelected = { id in (id.base as? V).map { $0 == binding.wrappedValue } ?? false }
        toggle = { id in
            guard let value = id.base as? V else { return }
            binding.wrappedValue = binding.wrappedValue == value ? nil : value
        }
    }

    package static func single<V: Hashable>(_ binding: Binding<V?>?) -> _ListSelection? {
        guard let binding else { return nil }
        return _ListSelection(single: binding)
    }

    package static func multiple<V: Hashable>(_ binding: Binding<Set<V>>?) -> _ListSelection? {
        guard let binding else { return nil }
        return _ListSelection(multiple: binding)
    }

    package init<V: Hashable>(multiple binding: Binding<Set<V>>) {
        isSelected = { id in (id.base as? V).map { binding.wrappedValue.contains($0) } ?? false }
        toggle = { id in
            guard let value = id.base as? V else { return }
            if binding.wrappedValue.contains(value) { binding.wrappedValue.remove(value) } else { binding.wrappedValue.insert(value) }
        }
    }
}

// MARK: - Styles

/// The geometry and colours of a list style.
public struct _ListProfile: Equatable, Sendable {
    package var name: String
    /// Distance from the list's edges to the row content and separators.
    package var margin: CGFloat
    /// Distance from the top of the list to the first section.
    package var topInset: CGFloat
    package var minimumRowHeight: CGFloat
    package var rowFont: Font?
    package var rowForeground: Color?
    package var background: Color
    package var borderColor: Color?
    package var showsSeparators: Bool
    /// Separators run from the row content's leading edge to `width - separatorTrailing`.
    package var separatorTrailing: CGFloat
    package var rowBackgroundExtendsToEdges: Bool
}

/// A protocol that describes the behavior and appearance of a list.
public protocol ListStyle: Sendable {
    var _profile: _ListProfile { get }
}

/// The list style that describes a platform's default behavior and appearance (inset on macOS).
public struct DefaultListStyle: ListStyle {
    public init() {}
    public var _profile: _ListProfile { InsetListStyle()._profile }
}

/// The list style that describes the behavior and appearance of an inset list.
public struct InsetListStyle: ListStyle {
    public init() {}
    public var _profile: _ListProfile {
        _ListProfile(name: "inset", margin: PlatformMetrics.listInsetMargin, topInset: PlatformMetrics.listTopInset,
                     minimumRowHeight: PlatformMetrics.listRowMinimumHeight, rowFont: nil, rowForeground: nil,
                     background: .white, borderColor: nil, showsSeparators: true,
                     separatorTrailing: PlatformMetrics.listInsetMargin, rowBackgroundExtendsToEdges: true)
    }
}

/// The list style that describes the behavior and appearance of a plain list.
public struct PlainListStyle: ListStyle {
    public init() {}
    public var _profile: _ListProfile {
        _ListProfile(name: "plain", margin: PlatformMetrics.listPlainMargin, topInset: 0,
                     minimumRowHeight: PlatformMetrics.listRowMinimumHeight, rowFont: nil, rowForeground: nil,
                     background: .white, borderColor: nil, showsSeparators: true, separatorTrailing: 0, rowBackgroundExtendsToEdges: true)
    }
}

/// The list style that describes the behavior and appearance of a list with standard border.
public struct BorderedListStyle: ListStyle {
    public init() {}
    public var _profile: _ListProfile {
        _ListProfile(name: "bordered", margin: PlatformMetrics.listBorderedMargin, topInset: PlatformMetrics.listBorderWidth,
                     minimumRowHeight: PlatformMetrics.listRowMinimumHeight, rowFont: nil, rowForeground: nil,
                     background: .white, borderColor: PlatformMetrics.listBorderColor, showsSeparators: true,
                     separatorTrailing: PlatformMetrics.listBorderedMargin, rowBackgroundExtendsToEdges: true)
    }
}

/// The list style that describes the behavior and appearance of a sidebar list.
public struct SidebarListStyle: ListStyle {
    public init() {}
    public var _profile: _ListProfile {
        _ListProfile(name: "sidebar", margin: PlatformMetrics.listInsetMargin, topInset: PlatformMetrics.listTopInset,
                     minimumRowHeight: PlatformMetrics.listSidebarRowHeight, rowFont: .body, rowForeground: PlatformMetrics.listSidebarForeground,
                     background: PlatformMetrics.listSidebarBackground, borderColor: nil, showsSeparators: false,
                     separatorTrailing: PlatformMetrics.listInsetMargin, rowBackgroundExtendsToEdges: true)
    }
}

extension ListStyle where Self == DefaultListStyle {
    public static var automatic: DefaultListStyle { DefaultListStyle() }
}
extension ListStyle where Self == InsetListStyle {
    public static var inset: InsetListStyle { InsetListStyle() }
}
extension ListStyle where Self == PlainListStyle {
    public static var plain: PlainListStyle { PlainListStyle() }
}
extension ListStyle where Self == BorderedListStyle {
    public static var bordered: BorderedListStyle { BorderedListStyle() }
}
extension ListStyle where Self == SidebarListStyle {
    public static var sidebar: SidebarListStyle { SidebarListStyle() }
}

package struct ListStyleKey: EnvironmentKey {
    package static let defaultValue: any ListStyle = DefaultListStyle()
}

extension EnvironmentValues {
    package var listStyle: any ListStyle {
        get { self[ListStyleKey.self] }
        set { self[ListStyleKey.self] = newValue }
    }
}

extension View {
    /// Sets the style for lists within this view.
    nonisolated public func listStyle<S: ListStyle>(_ style: S) -> some View {
        environment(\.listStyle, style)
    }
}

// MARK: - Row modifiers

/// The visibility of a UI element, chosen automatically based on the platform, current context,
/// and other factors.
public enum Visibility: Hashable, CaseIterable, Sendable {
    case automatic, visible, hidden
}

/// An enumeration to indicate one edge of a rectangle.
public enum VerticalEdge: Int8, CaseIterable, Hashable, Sendable {
    case top = 1, bottom = 2

    /// An efficient set of vertical edges.
    public struct Set: OptionSet, Sendable {
        public let rawValue: Int8
        public init(rawValue: Int8) { self.rawValue = rawValue }
        public init(_ edge: VerticalEdge) { rawValue = edge.rawValue }
        public static let top = Set(.top)
        public static let bottom = Set(.bottom)
        public static let all: Set = [.top, .bottom]
    }
}

package struct ListRowInsetsKey: LayoutValueKey {
    package static let defaultValue: EdgeInsets? = nil
}

package struct ListRowBackgroundKey: LayoutValueKey {
    package nonisolated(unsafe) static let defaultValue: _ListRowBackground? = nil
}

package struct ListRowSeparatorKey: LayoutValueKey {
    package static let defaultValue: (visibility: Visibility, edges: VerticalEdge.Set) = (.automatic, .all)
}

package struct ListRowSeparatorTintKey: LayoutValueKey {
    package static let defaultValue: (color: Color?, edges: VerticalEdge.Set) = (nil, .all)
}

/// A row background view, boxed so the layout value stays reflection-friendly.
package final class _ListRowBackground {
    package let view: AnyView
    package init(_ view: AnyView) { self.view = view }
}

extension View {
    /// Applies an inset to the rows in a list.
    nonisolated public func listRowInsets(_ insets: EdgeInsets?) -> some View {
        layoutValue(key: ListRowInsetsKey.self, value: insets)
    }

    /// Places a custom background view behind a list row item.
    nonisolated public func listRowBackground<V: View>(_ view: V?) -> some View {
        layoutValue(key: ListRowBackgroundKey.self, value: view.map { _ListRowBackground(AnyView($0)) })
    }

    /// Sets the display mode for the separator associated with this specific row.
    nonisolated public func listRowSeparator(_ visibility: Visibility, edges: VerticalEdge.Set = .all) -> some View {
        layoutValue(key: ListRowSeparatorKey.self, value: (visibility, edges))
    }

    /// Sets the tint color associated with a row.
    nonisolated public func listRowSeparatorTint(_ color: Color?, edges: VerticalEdge.Set = .all) -> some View {
        layoutValue(key: ListRowSeparatorTintKey.self, value: (color, edges))
    }

    /// Sets the display mode for the separator associated with this specific section. Stored only.
    nonisolated public func listSectionSeparator(_ visibility: Visibility, edges: VerticalEdge.Set = .all) -> some View { self }

    /// Sets the tint color associated with a section. Stored only.
    nonisolated public func listSectionSeparatorTint(_ color: Color?, edges: VerticalEdge.Set = .all) -> some View { self }

    /// Sets a fixed tint color for content in a list. Stored only.
    nonisolated public func listItemTint(_ tint: Color?) -> some View { self }
}

// MARK: - Primitives

/// The rows, headers and footers of a list laid out by `ListContentNode`.
public struct _ListContent<Content: View>: View {
    package let content: Content
    package let selection: _ListSelection?
    package let profile: _ListProfile
    /// The first section's header is shown pinned at the top of the list instead of in its slot.
    package let pinsFirstHeader: Bool

    package init(content: Content, selection: _ListSelection?, profile: _ListProfile, pinsFirstHeader: Bool) {
        self.content = content
        self.selection = selection
        self.profile = profile
        self.pinsFirstHeader = pinsFirstHeader
    }

    public typealias Body = Never

    public static func _makeNode(_ context: _NodeContext<_ListContent<Content>>) -> TypedNode<_ListContent<Content>> {
        ListContentNode(context)
    }
}

/// The first section's header, pinned at the top of the list (macOS floats it above the rows;
/// its in-flow slot stays blank).
struct _ListPinnedHeader: View {
    let title: String?
    let profile: _ListProfile

    var body: some View {
        if let title {
            ZStack(alignment: .bottom) {
                profile.background
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, profile.margin)
                    .frame(height: PlatformMetrics.listPinnedHeaderHeight, alignment: .center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                VStack(spacing: 0) {
                    Color.black.opacity(PlatformMetrics.listPinnedHeaderShadowAlpha).frame(height: PlatformMetrics.listPinnedHeaderLine)
                    Color.black.opacity(PlatformMetrics.listPinnedHeaderLineAlpha).frame(height: PlatformMetrics.listPinnedHeaderLine)
                }
            }
            .frame(height: PlatformMetrics.listPinnedHeaderHeight + PlatformMetrics.listPinnedHeaderLine)
        }
    }
}

/// The title of the first section when its header is a `Text` (the pinned header case).
@MainActor
func _firstSectionTitle<Content: View>(of content: Content) -> String? {
    (content as? any _SectionHeaderProviding)?._headerTitle
    ?? (content as? any _TupleHeadProviding)?._headTitle
}

package protocol _SectionHeaderProviding {
    var _headerTitle: String? { get }
}

extension Section: _SectionHeaderProviding {
    package var _headerTitle: String? { (header as? Text)?.resolvedString }
}

package protocol _TupleHeadProviding {
    var _headTitle: String? { get }
}

extension TupleView: _TupleHeadProviding {
    package var _headTitle: String? {
        let mirror = Mirror(reflecting: value)
        guard let first = mirror.children.first?.value else { return nil }
        return (first as? any _SectionHeaderProviding)?._headerTitle
    }
}
