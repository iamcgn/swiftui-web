import WebFoundation

/// A view that displays a root view and enables you to present additional views over the root
/// view.
///
/// macOS behaviour measured in `Docs/elements/Navigation.md`: in a hosted window the stack is
/// exactly its content's size (the navigation bar is window chrome); pushing shows the new view
/// centred where the previous one was, the previous views staying laid out beneath it; a
/// `NavigationLink` outside a list is a bordered button, inside a list a plain row.
public struct NavigationStack<Data, Root: View>: View {
    package let root: Root
    package let binding: _NavigationPathBinding?
    @State private var localPath: [AnyHashable] = []

    /// Creates a navigation stack that manages its own navigation state.
    public init(@ViewBuilder root: () -> Root) where Data == NavigationPath {
        self.root = root()
        self.binding = nil
    }

    /// Creates a navigation stack with heterogeneous navigation state that you can control.
    public init(path: Binding<NavigationPath>, @ViewBuilder root: () -> Root) where Data == NavigationPath {
        self.root = root()
        self.binding = _NavigationPathBinding(get: { path.wrappedValue.elements }, set: { path.wrappedValue = NavigationPath(elements: $0) })
    }

    /// Creates a navigation stack with homogeneous navigation state that you can control.
    public init(path: Binding<Data>, @ViewBuilder root: () -> Root)
    where Data: MutableCollection, Data: RandomAccessCollection, Data: RangeReplaceableCollection, Data.Element: Hashable {
        self.root = root()
        self.binding = _NavigationPathBinding(
            get: { path.wrappedValue.map { AnyHashable($0) } },
            set: { values in
                var data = path.wrappedValue
                data.removeAll()
                data.append(contentsOf: values.compactMap { $0.base as? Data.Element })
                path.wrappedValue = data
            })
    }

    public var body: some View {
        let local = $localPath
        let path = binding ?? _NavigationPathBinding(get: { local.wrappedValue }, set: { local.wrappedValue = $0 })
        // Read the path inside the body so observation tracks the model it comes from.
        let values = path.get()
        _NavigationStackHost(root: AnyView(root), path: path, values: values)
    }
}

/// A type-erased list of data representing the content of a navigation stack.
public struct NavigationPath: Equatable {
    package var elements: [AnyHashable]

    /// Creates a new, empty navigation path.
    public init() { elements = [] }

    /// Creates a new navigation path from the contents of a sequence.
    public init<S: Sequence>(_ elements: S) where S.Element: Hashable {
        self.elements = elements.map { AnyHashable($0) }
    }

    package init(elements: [AnyHashable]) { self.elements = elements }

    /// The number of elements in this path.
    public var count: Int { elements.count }

    /// A Boolean that indicates whether this path is empty.
    public var isEmpty: Bool { elements.isEmpty }

    /// Appends a new value to the end of this path.
    public mutating func append<V: Hashable>(_ value: V) { elements.append(AnyHashable(value)) }

    /// Removes values from the end of this path.
    public mutating func removeLast(_ k: Int = 1) { elements.removeLast(Swift.min(k, elements.count)) }

    // MARK: Codable representation

    /// A serializable representation of a navigation path: the elements' type names and JSON,
    /// last element first, as SwiftUI lays it out (`["Swift.Int", "2", "Swift.String", "\"a\""]`).
    public struct CodableRepresentation: Codable, Equatable, Sendable {
        package var items: [String]

        package init(items: [String]) { self.items = items }

        public init(from decoder: any Decoder) throws {
            var container = try decoder.unkeyedContainer()
            var items: [String] = []
            while !container.isAtEnd { items.append(try container.decode(String.self)) }
            self.items = items
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.unkeyedContainer()
            for item in items { try container.encode(item) }
        }
    }

    /// Creates a new navigation path from a serializable version: elements whose type the
    /// program no longer declares, or whose JSON no longer decodes, end the path there.
    public init(_ codable: CodableRepresentation) {
        var elements: [AnyHashable] = []
        var index = 0
        while index + 1 < codable.items.count {
            guard let type = _typeByName(codable.items[index]) as? any (Decodable & Hashable).Type,
                  let value = Self.decode(type, from: codable.items[index + 1]) else { break }
            elements.append(value)
            index += 2
        }
        self.elements = elements.reversed()
    }

    /// The serializable representation of this path, nil when an element is not `Codable`.
    public var codable: CodableRepresentation? {
        var items: [String] = []
        for element in elements.reversed() {
            guard let encodable = element.base as? any Encodable, let name = _mangledTypeName(type(of: element.base)),
                  let data = try? _TransferJSONEncoder().encode(encodable) else { return nil }
            items.append(name)
            items.append(String(decoding: data, as: UTF8.self))
        }
        return CodableRepresentation(items: items)
    }

    private static func decode(_ type: any (Decodable & Hashable).Type, from json: String) -> AnyHashable? {
        func open<T: Decodable & Hashable>(_: T.Type) -> AnyHashable? {
            (try? _TransferJSONDecoder().decode(T.self, from: Data(json.utf8))).map { AnyHashable($0) }
        }
        return _openExistential(type, do: open)
    }
}

/// Type-erased access to a navigation stack's path (a class so the runtime's field reflection
/// ignores it).
@MainActor
package final class _NavigationPathBinding {
    package let get: () -> [AnyHashable]
    package let set: ([AnyHashable]) -> Void

    package init(get: @escaping () -> [AnyHashable], set: @escaping ([AnyHashable]) -> Void) {
        self.get = get
        self.set = set
    }
}

/// The primitive a `NavigationStack` resolves to (`NavigationStackNode`).
public struct _NavigationStackHost: View {
    package let root: AnyView
    package let path: _NavigationPathBinding
    package let values: [AnyHashable]

    package init(root: AnyView, path: _NavigationPathBinding, values: [AnyHashable]) {
        self.root = root
        self.path = path
        self.values = values
    }

    public typealias Body = Never

    public static func _makeNode(_ context: _NodeContext<_NavigationStackHost>) -> TypedNode<_NavigationStackHost> {
        NavigationStackNode(context)
    }
}

// MARK: - Links

/// A view that controls a navigation presentation.
public struct NavigationLink<Label: View, Destination: View>: View {
    package let label: Label
    package let destination: AnyView?
    package let value: AnyHashable?

    /// Creates a navigation link that presents the destination view.
    public init(@ViewBuilder destination: () -> Destination, @ViewBuilder label: () -> Label) {
        self.label = label()
        self.destination = AnyView(destination())
        self.value = nil
    }

    /// Creates a navigation link that presents the destination view.
    public init(destination: Destination, @ViewBuilder label: () -> Label) {
        self.label = label()
        self.destination = AnyView(destination)
        self.value = nil
    }

    /// Creates a navigation link that presents the view corresponding to a value.
    public init<P: Hashable>(value: P?, @ViewBuilder label: () -> Label) where Destination == Never {
        self.label = label()
        self.destination = nil
        self.value = value.map { AnyHashable($0) }
    }

    @Environment(\._navigationContext) private var context
    @Environment(\._inListRow) private var inListRow
    @Environment(\.platformProfile) private var platform

    private var isEnabled: Bool { destination != nil || value != nil }

    public var body: some View {
        let action = _ActionBox { [context, destination, value] in
            guard let stack = context?.stack else { return }
            if let value { stack.push(value: value) } else if let destination { stack.push(view: destination) }
        }
        if inListRow && platform.isIOS {
            // iOS: the label fills the row, which shows a chevron at its trailing edge.
            label.frame(maxWidth: .infinity, alignment: .leading).layoutValue(key: NavigationLinkActivationKey.self, value: action)
        } else if inListRow {
            // A list row: the row itself is the press target (`ListContentNode`).
            label.layoutValue(key: NavigationLinkActivationKey.self, value: action)
        } else {
            Button(action: action.run) { label }.disabled(!isEnabled)
        }
    }
}

extension NavigationLink where Label == Text {
    /// Creates a navigation link that presents a destination view, with a text label.
    public init(_ titleKey: LocalizedStringKey, @ViewBuilder destination: () -> Destination) {
        self.init(destination: destination) { Text(titleKey) }
    }

    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, @ViewBuilder destination: () -> Destination) {
        self.init(destination: destination) { Text(title) }
    }

    /// Creates a navigation link that presents the view corresponding to a value, with a text label.
    public init<P: Hashable>(_ titleKey: LocalizedStringKey, value: P?) where Destination == Never {
        self.init(value: value) { Text(titleKey) }
    }

    @_disfavoredOverload
    public init<S: StringProtocol, P: Hashable>(_ title: S, value: P?) where Destination == Never {
        self.init(value: value) { Text(title) }
    }
}

package struct NavigationLinkActivationKey: LayoutValueKey {
    package nonisolated(unsafe) static let defaultValue: _ActionBox? = nil
}

// MARK: - Destinations and titles

/// Type-erased builder of a destination view for a value.
package struct _NavigationDestinationBuilder {
    package let make: (AnyHashable) -> AnyView?
}

/// A `navigationDestination(for:destination:)` modifier.
public struct _NavigationDestinationModifier<D: Hashable> {
    package let builder: _NavigationDestinationBuilder
    package init(destination: @escaping (D) -> some View) {
        builder = _NavigationDestinationBuilder { value in (value.base as? D).map { AnyView(destination($0)) } }
    }
}

extension _NavigationDestinationModifier: ViewModifier {
    public typealias Body = Never
    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        NavigationDestinationNode(context, type: ObjectIdentifier(D.self))
    }
}

/// A `navigationDestination(isPresented:destination:)` modifier. Its body reads the binding so
/// observation tracks it; the primitive `_NavigationPresentedSync` pushes and pops.
public struct _NavigationPresentedDestinationModifier {
    package let isPresented: Binding<Bool>
    package let destination: AnyView
    package init(isPresented: Binding<Bool>, destination: AnyView) {
        self.isPresented = isPresented
        self.destination = destination
    }
}

extension _NavigationPresentedDestinationModifier: ViewModifier {
    public func body(content: Content) -> some View {
        content.modifier(_NavigationPresentedSync(presented: isPresented.wrappedValue, binding: isPresented, destination: destination))
    }
}

public struct _NavigationPresentedSync {
    package let presented: Bool
    package let binding: Binding<Bool>
    package let destination: AnyView
    package init(presented: Bool, binding: Binding<Bool>, destination: AnyView) {
        self.presented = presented
        self.binding = binding
        self.destination = destination
    }
}

/// A `navigationDestination(item:destination:)` modifier: pushes the destination of the bound
/// item while it is non-nil (a new item swaps the pushed view in place), pops when it becomes
/// nil, and sets it to nil when the user pops.
public struct _NavigationItemDestinationModifier<Item: Hashable> {
    package let item: Binding<Item?>
    package let destination: (Item) -> AnyView
    package init(item: Binding<Item?>, destination: @escaping (Item) -> AnyView) {
        self.item = item
        self.destination = destination
    }
}

extension _NavigationItemDestinationModifier: ViewModifier {
    public func body(content: Content) -> some View {
        let current = item.wrappedValue
        let item = item
        return content.modifier(_NavigationPresentedSync(
            presented: current != nil,
            binding: Binding(get: { item.wrappedValue != nil }, set: { if !$0 { item.wrappedValue = nil } }),
            destination: current.map(destination) ?? AnyView(EmptyView())))
    }
}

extension _NavigationPresentedSync: ViewModifier {
    public typealias Body = Never
    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        NavigationPresentedDestinationNode(context)
    }
}

/// A `navigationTitle` modifier: the title is recorded on the runtime for hosts (window chrome).
public struct _NavigationTitleModifier {
    package let title: String
    package init(title: String) { self.title = title }
}

extension _NavigationTitleModifier: ViewModifier {
    public typealias Body = Never
    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        NavigationTitleNode(context)
    }
}

package struct UnderNavigationBarKey: EnvironmentKey {
    package static let defaultValue = false
}

package struct NavigationBarOverhangKey: EnvironmentKey {
    package static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    /// Whether the view is the content of a navigation stack whose bar sits above it (iOS lists
    /// drop their top inset there).
    package var _underNavigationBar: Bool {
        get { self[UnderNavigationBarKey.self] }
        set { self[UnderNavigationBarKey.self] = newValue }
    }

    /// The height of the iOS navigation bar above the screen's content: a scroll view under it
    /// keeps painting that far above its frame, as the content slides under the bar's glass
    /// (ios/nav/scroll `row1`: the first row shows through the bar).
    package var _navigationBarOverhang: CGFloat {
        get { self[NavigationBarOverhangKey.self] }
        set { self[NavigationBarOverhangKey.self] = newValue }
    }
}

/// `navigationBarTitleDisplayMode`: how the iOS navigation bar shows the title.
public enum NavigationBarItem {
    public enum TitleDisplayMode: Sendable, Equatable {
        case automatic, inline, large
    }
}

public struct _NavigationTitleDisplayModeModifier {
    package let mode: NavigationBarItem.TitleDisplayMode
    package init(mode: NavigationBarItem.TitleDisplayMode) { self.mode = mode }
}

extension _NavigationTitleDisplayModeModifier: ViewModifier {
    public typealias Body = Never
    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        NavigationTitleDisplayModeNode(context)
    }
}

extension View {
    /// Configures the title display mode for this view (the iOS navigation bar; no effect on macOS).
    nonisolated public func navigationBarTitleDisplayMode(_ displayMode: NavigationBarItem.TitleDisplayMode) -> some View {
        modifier(_NavigationTitleDisplayModeModifier(mode: displayMode))
    }

    /// Associates a destination view with a presented data type for use within a navigation stack.
    nonisolated public func navigationDestination<D: Hashable, C: View>(for data: D.Type, @ViewBuilder destination: @escaping (D) -> C) -> some View {
        modifier(_NavigationDestinationModifier<D>(destination: destination))
    }

    /// Associates a destination view with a binding that can be used to push the view onto a
    /// navigation stack.
    /// Associates a destination view with a bound value: the destination is pushed while the
    /// value is non-nil and popped when it becomes nil; popping sets it to nil.
    nonisolated public func navigationDestination<D: Hashable, C: View>(item: Binding<D?>, @ViewBuilder destination: @escaping (D) -> C) -> some View {
        modifier(_NavigationItemDestinationModifier(item: item, destination: { AnyView(destination($0)) }))
    }

    nonisolated public func navigationDestination<V: View>(isPresented: Binding<Bool>, @ViewBuilder destination: () -> V) -> some View {
        modifier(_NavigationPresentedDestinationModifier(isPresented: isPresented, destination: AnyView(destination())))
    }

    /// Configures the view's title for purposes of navigation.
    nonisolated public func navigationTitle(_ title: Text) -> some View {
        modifier(_NavigationTitleModifier(title: title.resolvedString))
    }

    nonisolated public func navigationTitle(_ titleKey: LocalizedStringKey) -> some View {
        modifier(_NavigationTitleModifier(title: Text(titleKey).resolvedString))
    }

    @_disfavoredOverload
    nonisolated public func navigationTitle<S: StringProtocol>(_ title: S) -> some View {
        modifier(_NavigationTitleModifier(title: String(title)))
    }

    /// Configures the view's subtitle for purposes of navigation. Stored only.
    nonisolated public func navigationSubtitle<S: StringProtocol>(_ subtitle: S) -> some View { self }
    nonisolated public func navigationSubtitle(_ subtitleKey: LocalizedStringKey) -> some View { self }
    nonisolated public func navigationSubtitle(_ subtitle: Text) -> some View { self }

    /// Hides the navigation bar back button (the iOS bar; macOS has no painted back button).
    nonisolated public func navigationBarBackButtonHidden(_ hidesBackButton: Bool = true) -> some View {
        modifier(_NavigationBackButtonHiddenModifier(hidden: hidesBackButton))
    }
}

public struct _NavigationBackButtonHiddenModifier {
    package let hidden: Bool
    package init(hidden: Bool) { self.hidden = hidden }
}

extension _NavigationBackButtonHiddenModifier: ViewModifier {
    public typealias Body = Never
    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        NavigationBackButtonHiddenNode(context)
    }
}

/// The back button an iOS navigation bar shows over a pushed screen (Runtime/NavigationNodes.swift).
public struct _NavigationBackButton: View {
    package init() {}
    public typealias Body = Never
    public static func _makeNode(_ context: _NodeContext<_NavigationBackButton>) -> TypedNode<_NavigationBackButton> {
        NavigationBackButtonNode(context)
    }
}

// MARK: - Environment

/// The navigation stack a link or destination registration belongs to.
@MainActor
package final class _NavigationContext {
    package weak var stack: NavigationStackNode?
    package init(stack: NavigationStackNode) { self.stack = stack }
}

package struct NavigationContextKey: EnvironmentKey {
    package static let defaultValue: _NavigationContext? = nil
}

package struct InListRowKey: EnvironmentKey {
    package static let defaultValue = false
}

extension EnvironmentValues {
    package var _navigationContext: _NavigationContext? {
        get { self[NavigationContextKey.self] }
        set { self[NavigationContextKey.self] = newValue }
    }

    /// Whether the view is a row of a `List` (links render as plain rows there).
    package var _inListRow: Bool {
        get { self[InListRowKey.self] }
        set { self[InListRowKey.self] = newValue }
    }
}
