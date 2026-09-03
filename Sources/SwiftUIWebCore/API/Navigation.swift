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

    private var isEnabled: Bool { destination != nil || value != nil }

    public var body: some View {
        let action = _ActionBox { [context, destination, value] in
            guard let stack = context?.stack else { return }
            if let value { stack.push(value: value) } else if let destination { stack.push(view: destination) }
        }
        if inListRow {
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

extension View {
    /// Associates a destination view with a presented data type for use within a navigation stack.
    nonisolated public func navigationDestination<D: Hashable, C: View>(for data: D.Type, @ViewBuilder destination: @escaping (D) -> C) -> some View {
        modifier(_NavigationDestinationModifier<D>(destination: destination))
    }

    /// Associates a destination view with a binding that can be used to push the view onto a
    /// navigation stack.
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

    /// Hides the navigation bar back button. Stored only (the back button is window chrome).
    nonisolated public func navigationBarBackButtonHidden(_ hidesBackButton: Bool = true) -> some View { self }
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
