// A widget extension's own types (Docs/support.json, "WidgetKit"): `Widget`, `WidgetBundle`,
// the configurations (`StaticConfiguration`, `IntentConfiguration`, `AppIntentConfiguration`)
// and the timeline providers they ask for entries. A page has no home screen to put a widget on,
// so nothing asks a provider for a timeline; the types are here so a widget's files, often in the
// same package or target as the app (Dime's widgets), compile with it. A configuration keeps its
// kind, the provider, the entry view and its modifiers' values, so an app or a test can still
// draw a widget's view for an entry it makes, as a preview does.
import SwiftUI
import Intents
import AppIntents

// MARK: - Widgets and bundles

/// The configuration and content of a widget to show on the Home screen or the Lock screen.
@MainActor @preconcurrency
public protocol Widget {
    associatedtype Body: WidgetConfiguration
    init()
    @WidgetConfigurationBuilder var body: Body { get }
}

/// A container of the widgets an extension offers.
@MainActor @preconcurrency
public protocol WidgetBundle {
    associatedtype Body: Widget
    init()
    @WidgetBundleBuilder var body: Body { get }
}

extension Widget {
    /// The extension's entry point when the widget is its `@main` type. A page runs no widget
    /// extension, so there is nothing to start.
    public static func main() {}
}

extension WidgetBundle {
    /// The extension's entry point when the bundle is its `@main` type (see `Widget.main()`).
    public static func main() {}
}

/// Builds a bundle's widgets.
@resultBuilder
public enum WidgetBundleBuilder {
    public static func buildBlock<each W: Widget>(_ widgets: repeat each W) -> _WidgetBundleContent<repeat each W> {
        _WidgetBundleContent()
    }
    public static func buildExpression<W: Widget>(_ widget: W) -> W { widget }
    public static func buildLimitedAvailability<W: Widget>(_ widget: W) -> W { widget }
}

/// The widgets a bundle lists (they are made again when asked for, as each is a value).
public struct _WidgetBundleContent<each W: Widget>: Widget {
    // The builders run outside the main actor, so the values they make are made outside it.
    nonisolated public init() {}
    public var body: EmptyWidgetConfiguration { EmptyWidgetConfiguration() }
}

// MARK: - Configurations

/// A type that describes a widget's content.
@MainActor @preconcurrency
public protocol WidgetConfiguration {
    associatedtype Body: WidgetConfiguration
    @WidgetConfigurationBuilder var body: Body { get }
}

extension Never: WidgetConfiguration {
    public var body: Never { fatalError("Never has no body") }
}

/// A configuration with nothing in it.
public struct EmptyWidgetConfiguration: WidgetConfiguration {
    nonisolated public init() {}
    public var body: Never { fatalError("EmptyWidgetConfiguration has no body") }
}

/// Builds a widget's configuration.
@resultBuilder
public enum WidgetConfigurationBuilder {
    public static func buildBlock() -> EmptyWidgetConfiguration { EmptyWidgetConfiguration() }
    public static func buildBlock<C: WidgetConfiguration>(_ content: C) -> C { content }
    public static func buildExpression<C: WidgetConfiguration>(_ content: C) -> C { content }
    public static func buildEither<T: WidgetConfiguration, F: WidgetConfiguration>(first: T) -> _ConditionalWidgetConfiguration<T, F> { .init(content: .first(first)) }
    public static func buildEither<T: WidgetConfiguration, F: WidgetConfiguration>(second: F) -> _ConditionalWidgetConfiguration<T, F> { .init(content: .second(second)) }
    public static func buildOptional<C: WidgetConfiguration>(_ content: C?) -> _ConditionalWidgetConfiguration<C, EmptyWidgetConfiguration> {
        .init(content: content.map { .first($0) } ?? .second(EmptyWidgetConfiguration()))
    }
    public static func buildLimitedAvailability<C: WidgetConfiguration>(_ content: C) -> C { content }
}

/// One of two configurations, as an `if` in a widget's body chose.
// Not on the main actor (nor its stored choice), since the builder makes it outside it.
nonisolated public struct _ConditionalWidgetConfiguration<T: WidgetConfiguration, F: WidgetConfiguration>: WidgetConfiguration {
    enum Content { case first(T), second(F) }
    let content: Content
    init(content: Content) { self.content = content }
    public var body: Never { fatalError("_ConditionalWidgetConfiguration has no body") }
}

/// What a configuration's modifiers set: its name and description in the widget gallery, the
/// sizes it comes in, and whether the system's content margins are kept.
public struct _WidgetInfo: Sendable {
    public var displayName: String?
    public var description: String?
    public var supportedFamilies: [WidgetFamily] = WidgetFamily.allCases
    public var contentMarginsDisabled = false
}

/// A configuration that keeps the values its modifiers set (`_WidgetInfo`).
public protocol _WidgetConfigurationValues: WidgetConfiguration {
    var _info: _WidgetInfo { get set }
}

extension WidgetConfiguration {
    /// The name the widget gallery shows for the widget.
    public func configurationDisplayName(_ displayName: String) -> some WidgetConfiguration {
        _setting { $0.displayName = displayName }
    }

    /// The name the widget gallery shows for the widget.
    public func configurationDisplayName(_ displayName: LocalizedStringKey) -> some WidgetConfiguration {
        _setting { $0.displayName = displayName.key }
    }

    /// The name the widget gallery shows for the widget.
    public func configurationDisplayName(_ displayName: Text) -> some WidgetConfiguration {
        _setting { $0.displayName = displayName.resolvedString }
    }

    /// The description the widget gallery shows for the widget.
    public func description(_ description: String) -> some WidgetConfiguration {
        _setting { $0.description = description }
    }

    /// The description the widget gallery shows for the widget.
    public func description(_ description: LocalizedStringKey) -> some WidgetConfiguration {
        _setting { $0.description = description.key }
    }

    /// The description the widget gallery shows for the widget.
    public func description(_ description: Text) -> some WidgetConfiguration {
        _setting { $0.description = description.resolvedString }
    }

    /// The sizes the widget comes in.
    public func supportedFamilies(_ families: [WidgetFamily]) -> some WidgetConfiguration {
        _setting { $0.supportedFamilies = families }
    }

    /// Lets the widget's content reach its edges, without the system's margins.
    public func contentMarginsDisabled() -> some WidgetConfiguration {
        _setting { $0.contentMarginsDisabled = true }
    }

    /// Whether the system may remove the widget's container background (StandBy, the Lock
    /// screen); kept by nothing here.
    public func containerBackgroundRemovable(_ isRemovable: Bool = true) -> some WidgetConfiguration { self }

    /// The background URL session events the widget handles; a page starts none for a widget.
    public func onBackgroundURLSessionEvents(matching matchingString: String? = nil,
                                             _ urlSessionEvent: @escaping (String, @escaping () -> Void) -> Void) -> some WidgetConfiguration { self }

    /// Whether adding the widget asks the person to configure it first; kept by nothing here.
    public func promptsForUserConfiguration() -> some WidgetConfiguration { self }

    /// The configuration with a modifier's value set, when it keeps values (the configurations
    /// here all do); another type is returned as it is.
    func _setting(_ change: (inout _WidgetInfo) -> Void) -> Self {
        guard var values = self as? any _WidgetConfigurationValues else { return self }
        change(&values._info)
        return values as? Self ?? self
    }

    /// The values its modifiers set, when it keeps them.
    public var _widgetInfo: _WidgetInfo? { (self as? any _WidgetConfigurationValues)?._info }
}

/// A configuration whose entries come from a `TimelineProvider`.
public struct StaticConfiguration<Content: View>: _WidgetConfigurationValues {
    /// The string the app reloads the widget's timelines by.
    public let kind: String
    public var _info = _WidgetInfo()
    let entryView: (any TimelineEntry) -> Content?
    let placeholderEntry: (TimelineProviderContext) -> any TimelineEntry

    public init<Provider: TimelineProvider>(kind: String, provider: Provider,
                                            @ViewBuilder content: @escaping (Provider.Entry) -> Content) {
        self.kind = kind
        entryView = { ($0 as? Provider.Entry).map(content) }
        placeholderEntry = { provider.placeholder(in: $0) }
    }

    public var body: Never { fatalError("StaticConfiguration has no body") }

    /// The widget's view for an entry of its provider's kind (nil for another kind), as a preview
    /// draws it.
    public func _view(for entry: any TimelineEntry) -> Content? { entryView(entry) }

    /// The view of the provider's placeholder entry.
    public func _placeholderView(in context: TimelineProviderContext = TimelineProviderContext()) -> Content? {
        entryView(placeholderEntry(context))
    }
}

/// A configuration whose entries come from an `IntentTimelineProvider`, with a SiriKit intent
/// the person sets the widget up with.
public struct IntentConfiguration<Intent: INIntent, Content: View>: _WidgetConfigurationValues {
    public let kind: String
    public var _info = _WidgetInfo()
    let entryView: (any TimelineEntry) -> Content?

    public init<Provider: IntentTimelineProvider>(kind: String, intent: Intent.Type, provider: Provider,
                                                  @ViewBuilder content: @escaping (Provider.Entry) -> Content) where Provider.Intent == Intent {
        self.kind = kind
        entryView = { ($0 as? Provider.Entry).map(content) }
    }

    public var body: Never { fatalError("IntentConfiguration has no body") }

    /// The widget's view for an entry of its provider's kind (nil for another kind).
    public func _view(for entry: any TimelineEntry) -> Content? { entryView(entry) }
}

/// A configuration whose entries come from an `AppIntentTimelineProvider`, with an app intent
/// the person sets the widget up with.
public struct AppIntentConfiguration<Intent: WidgetConfigurationIntent, Content: View>: _WidgetConfigurationValues {
    public let kind: String
    public var _info = _WidgetInfo()
    let entryView: (any TimelineEntry) -> Content?

    public init<Provider: AppIntentTimelineProvider>(kind: String, intent: Intent.Type = Intent.self, provider: Provider,
                                                     @ViewBuilder content: @escaping (Provider.Entry) -> Content) where Provider.Intent == Intent {
        self.kind = kind
        entryView = { ($0 as? Provider.Entry).map(content) }
    }

    public var body: Never { fatalError("AppIntentConfiguration has no body") }

    /// The widget's view for an entry of its provider's kind (nil for another kind).
    public func _view(for entry: any TimelineEntry) -> Content? { entryView(entry) }
}

// MARK: - Timeline providers

/// What a provider is told when asked for entries.
public struct TimelineProviderContext: Sendable {
    /// The size the widget is shown at.
    public let family: WidgetFamily
    /// Whether the entries are for the widget gallery's preview.
    public let isPreview: Bool
    /// The widget's size in points.
    public let displaySize: CGSize

    /// A small widget's context on a 390-point-wide phone, as a preview asks.
    public init(family: WidgetFamily = .systemSmall, isPreview: Bool = true, displaySize: CGSize? = nil) {
        self.family = family
        self.isPreview = isPreview
        self.displaySize = displaySize ?? TimelineProviderContext.size(of: family)
    }

    /// The sizes of an iPhone 15's widgets.
    static func size(of family: WidgetFamily) -> CGSize {
        switch family {
        case .systemSmall: CGSize(width: 170, height: 170)
        case .systemMedium: CGSize(width: 364, height: 170)
        case .systemLarge: CGSize(width: 364, height: 382)
        case .systemExtraLarge: CGSize(width: 715, height: 341)  // an iPad's
        case .accessoryCircular: CGSize(width: 76, height: 76)
        case .accessoryRectangular: CGSize(width: 172, height: 76)
        case .accessoryInline: CGSize(width: 257, height: 26)
        case .accessoryCorner: CGSize(width: 50, height: 50)  // a watch's
        }
    }
}

/// A type that tells WidgetKit when to update a widget's display.
public protocol TimelineProvider {
    associatedtype Entry: TimelineEntry
    typealias Context = TimelineProviderContext
    /// An entry to show while the widget's data loads.
    func placeholder(in context: Context) -> Entry
    /// The entry the widget gallery shows.
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void)
    /// The entries to show, and when to ask again.
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void)
}

/// A timeline provider for a widget the person sets up with a SiriKit intent.
public protocol IntentTimelineProvider {
    associatedtype Entry: TimelineEntry
    associatedtype Intent: INIntent
    typealias Context = TimelineProviderContext
    func placeholder(in context: Context) -> Entry
    func getSnapshot(for configuration: Intent, in context: Context, completion: @escaping (Entry) -> Void)
    func getTimeline(for configuration: Intent, in context: Context, completion: @escaping (Timeline<Entry>) -> Void)
}

/// A timeline provider for a widget the person sets up with an app intent.
public protocol AppIntentTimelineProvider {
    associatedtype Entry: TimelineEntry
    associatedtype Intent: WidgetConfigurationIntent
    typealias Context = TimelineProviderContext
    func placeholder(in context: Context) -> Entry
    func snapshot(for configuration: Intent, in context: Context) async -> Entry
    func timeline(for configuration: Intent, in context: Context) async -> Timeline<Entry>
}
