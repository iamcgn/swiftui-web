// ContentUnavailableView (Docs/elements/ContentUnavailableView.md): a large secondary title,
// a description and actions, top-aligned in the space the view fills.

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

    public var body: some View {
        VStack(spacing: PlatformMetrics.unavailableSpacing) {
            label.labelStyle(.titleOnly).font(.largeTitle).fontWeight(.bold).foregroundStyle(.secondary)
            description.font(.body).foregroundStyle(.secondary)
            HStack { actions }
        }
        .padding(.top, PlatformMetrics.unavailableTopPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
