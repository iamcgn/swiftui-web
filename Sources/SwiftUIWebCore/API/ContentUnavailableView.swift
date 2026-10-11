// ContentUnavailableView (Docs/elements/ContentUnavailableView.md): the label's symbol above
// its title (title3 bold, secondary), a description (title3, secondary) and actions, top-aligned
// in the space the view fills (macOS 27 and iOS; a NavigationStack centres it at its own height).

/// An interface, consisting of a label and additional content, that you display when the
/// content of your app is unavailable to users.
public struct ContentUnavailableView<Label: View, Description: View, Actions: View>: View {
    package let label: Label
    package let description: Description
    package let actions: Actions

    /// Creates an interface with a label, a description and actions.
    public init(@ViewBuilder label: () -> Label, @ViewBuilder description: () -> Description = { EmptyView() },
                @ViewBuilder actions: () -> Actions = { EmptyView() }) {
        self.label = label()
        self.description = description()
        self.actions = actions()
    }

    @Environment(\._navigationContext) private var navigation
    @Environment(\.platformProfile) private var profile

    public var body: some View {
        let column = VStack(spacing: 0) {
            label.labelStyle(_UnavailableLabelStyle())
            if Description.self != EmptyView.self {
                description.font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.top, PlatformMetrics.unavailableDescriptionGap)
            }
            if Actions.self != EmptyView.self {
                HStack { actions }.padding(.top, PlatformMetrics.unavailableActionsGap)
            }
        }
        .padding(.top, PlatformMetrics.unavailableTopPadding)
        .padding(.bottom, PlatformMetrics.unavailableBottomPadding)
        .fixedSize(horizontal: false, vertical: true)   // keeps its lines in a short cell (iOS `search` wraps to two)
        // Inside a NavigationStack the view keeps its own height and the stack centres it
        // (measured on macOS 27: 129.5 for a symbol and a title in a 190 pt stack). An iPhone
        // centres the column in the space it fills; a Mac keeps it at the top.
        if navigation != nil {
            column.frame(maxWidth: .infinity)
        } else {
            column.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: profile.isIOS ? .center : .top)
        }
    }
}

/// The unavailable view's label: the symbol (36 pt, the tertiary colour) above the title
/// (title3 bold, secondary), 24 apart, both centred. A catalog image icon does not show (the
/// harness's `Label(_:image:)` measured a title-only label, `unavailable/basic` `customLabel`).
struct _UnavailableLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: PlatformMetrics.unavailableIconGap) {
            if configuration.icon.content._isSystemSymbol {
                configuration.icon.font(.system(size: PlatformMetrics.unavailableIconSize)).foregroundStyle(.tertiary)
            }
            configuration.title.font(.title3).fontWeight(.bold).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
    }
}

extension AnyView {
    /// Whether the erased view is a system symbol image (`Image(systemName:)`), possibly probed.
    @MainActor package var _isSystemSymbol: Bool {
        if let image = (storage as? AnyViewStorage<Image>)?.view, case .system = image.source { return true }
        var visitor = _SymbolFinder()
        return storage.visit(&visitor)
    }
}

/// Finds a system symbol under modifiers (the fixture probe's background, a frame): the
/// `content` of each `ModifiedContent` in turn.
private struct _SymbolFinder: _AnyViewVisitor {
    @MainActor mutating func visit<V: View>(_ view: V) -> Bool {
        var current: Any = view
        for _ in 0..<8 {
            if let image = current as? Image { if case .system = image.source { return true } else { return false } }
            if let erased = current as? AnyView { return erased._isSystemSymbol }
            guard let inner = Mirror(reflecting: current).children.first(where: { $0.label == "content" })?.value else { return false }
            current = inner
        }
        return false
    }
}

extension ContentUnavailableView where Label == SwiftUIWebCore.Label<Text, Image>, Description == Text?, Actions == EmptyView {
    /// Creates an interface with a title, an image and a description.
    public init(_ title: LocalizedStringKey, image: String, description: Text? = nil) {
        label = SwiftUIWebCore.Label(title, image: image)
        self.description = description
        actions = EmptyView()
    }

    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, image: String, description: Text? = nil) {
        label = SwiftUIWebCore.Label(title, image: image)
        self.description = description
        actions = EmptyView()
    }

    /// Creates an interface with a title, a system image and a description.
    public init(_ title: LocalizedStringKey, systemImage: String, description: Text? = nil) {
        label = SwiftUIWebCore.Label(title, systemImage: systemImage)
        self.description = description
        actions = EmptyView()
    }

    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, systemImage: String, description: Text? = nil) {
        label = SwiftUIWebCore.Label(title, systemImage: systemImage)
        self.description = description
        actions = EmptyView()
    }
}

extension ContentUnavailableView where Label == SwiftUIWebCore.Label<Text, Image>, Description == Text?, Actions == EmptyView {
    /// The interface for an empty search: "No Results" with a spelling hint.
    public static var search: ContentUnavailableView {
        ContentUnavailableView("No Results", systemImage: "magnifyingglass", description: Text("Check the spelling or try a new search."))
    }

    /// The interface for a search with no results for `text`.
    public static func search(text: String) -> ContentUnavailableView {
        ContentUnavailableView("No Results for \u{201C}\(text)\u{201D}", systemImage: "magnifyingglass", description: Text("Check the spelling or try a new search."))
    }
}
