#if os(WASI)
import WebFoundation   // never full Foundation on wasm: it links ICU (decisions 0006, 0017)
#else
import Foundation
#endif
// LabeledContent (Docs/elements/LabeledContent.md): a label and a value side by side; in a
// columns form the label takes the label column.

/// A container for attaching a label to a value-bearing view.
public struct LabeledContent<Label: View, Content: View>: View {
    package let label: Label
    package let content: Content

    @Environment(\.labeledContentStyle) private var style
    /// Made from a style's configuration: drawn in the default style, as Apple's.
    package var fromConfiguration = false

    /// Creates a labeled view with a custom label and content.
    public init(@ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
        self.label = label()
        self.content = content()
    }

    public var body: some View {
        let configuration = LabeledContentStyleConfiguration(
            label: LabeledContentStyleConfiguration.Label(view: AnyView(label)),
            content: LabeledContentStyleConfiguration.Content(view: AnyView(content)))
        (fromConfiguration ? AutomaticLabeledContentStyle() : style).makeBodyErased(configuration)
    }
}

extension LabeledContent where Label == Text {
    /// Creates a labeled view with a title generated from a localized string key.
    public init(_ titleKey: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.init(content: content) { Text(titleKey) }
    }

    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, @ViewBuilder content: () -> Content) {
        self.init(content: content) { Text(title) }
    }
}

extension LabeledContent where Label == Text, Content == Text {
    /// Creates a labeled view with a title and a string value.
    public init<S: StringProtocol>(_ titleKey: LocalizedStringKey, value: S) {
        self.init(content: { Text(value) }) { Text(titleKey) }
    }

    @_disfavoredOverload
    public init<S1: StringProtocol, S2: StringProtocol>(_ title: S1, value: S2) {
        self.init(content: { Text(value) }) { Text(title) }
    }

    /// Creates a labeled view with a title and a value formatted by `format` (a number, a
    /// percent, a date: `Text(_:format:)`).
    public init<F: FormatStyle>(_ titleKey: LocalizedStringKey, value: F.FormatInput, format: F) where F.FormatOutput == String {
        self.init(content: { Text(value, format: format) }) { Text(titleKey) }
    }

    @_disfavoredOverload
    public init<S: StringProtocol, F: FormatStyle>(_ title: S, value: F.FormatInput, format: F) where F.FormatOutput == String {
        self.init(content: { Text(value, format: format) }) { Text(title) }
    }
}

extension LabeledContent where Label == LabeledContentStyleConfiguration.Label, Content == LabeledContentStyleConfiguration.Content {
    /// Creates a labeled view based on a style configuration (custom styles).
    public init(_ configuration: LabeledContentStyleConfiguration) {
        label = configuration.label
        content = configuration.content
        fromConfiguration = true
    }
}

// MARK: - Styles

/// The properties of a labeled content instance.
public struct LabeledContentStyleConfiguration {
    public struct Label {
        package let view: AnyView
        package init(view: AnyView) { self.view = view }
    }

    public struct Content {
        package let view: AnyView
        package init(view: AnyView) { self.view = view }
    }

    public let label: Label
    public let content: Content

    package init(label: Label, content: Content) {
        self.label = label
        self.content = content
    }
}

extension LabeledContentStyleConfiguration.Label: View {
    public var body: some View { view }
}

extension LabeledContentStyleConfiguration.Content: View {
    public var body: some View { view }
}

/// The appearance and behavior of a labeled content instance.
@MainActor @preconcurrency
public protocol LabeledContentStyle {
    associatedtype Body: View
    @ViewBuilder func makeBody(configuration: Self.Configuration) -> Self.Body
    typealias Configuration = LabeledContentStyleConfiguration
}

extension LabeledContentStyle {
    @MainActor
    package func makeBodyErased(_ configuration: Configuration) -> AnyView {
        AnyView(makeBody(configuration: configuration))
    }
}

/// The default labeled content style: the label in the body font, 8 pt, the content, centred
/// in the row; in a columns form the label takes the label column (`labelsHidden` drops it).
public struct AutomaticLabeledContentStyle {
    public init() {}
}

extension AutomaticLabeledContentStyle: LabeledContentStyle {
    public func makeBody(configuration: Configuration) -> some View {
        _LabeledContentRow(configuration: configuration)
    }
}

extension LabeledContentStyle where Self == AutomaticLabeledContentStyle {
    public static var automatic: AutomaticLabeledContentStyle { AutomaticLabeledContentStyle() }
}

package struct _LabeledContentRow {
    package let configuration: LabeledContentStyleConfiguration
    @Environment(\._formStyle) private var formStyle
    @Environment(\.labelsHidden) private var labelsHidden
    package init(configuration: LabeledContentStyleConfiguration) { self.configuration = configuration }
}

extension _LabeledContentRow: View {
    package var body: some View {
        if formStyle == .columns {
            _FormLabeledRow(label: labelsHidden ? nil : AnyView(configuration.label), content: AnyView(configuration.content), mode: .firstTextBaseline)
        } else if formStyle == .grouped {
            // A grouped form row: the body-styled label (an 18.5 line), the value in the
            // secondary colour at the trailing edge on the label's baseline, a control (a
            // checkbox, a pop-up) as itself rather than a form row of its own; the row 0.125
            // lower than other rows (measured 2026-10-11, `label/corners`, macOS 27).
            _FormLabeledRow(label: labelsHidden ? nil : AnyView(_ControlLabel(label: configuration.label)),
                            content: AnyView(configuration.content.foregroundStyle(.secondary).environment(\._formStyle, nil)), mode: .groupedBaseline)
                .alignmentGuide(VerticalAlignment._formRowTop) { _ in -PlatformMetrics.formLabeledContentRowOffset }
        } else if labelsHidden {
            configuration.content
        } else {
            HStack(spacing: PlatformMetrics.controlLabelSpacing) {
                _ControlLabel(label: configuration.label)
                configuration.content
            }
        }
    }
}

package struct LabeledContentStyleKey: EnvironmentKey {
    package nonisolated(unsafe) static let defaultValue: any LabeledContentStyle = AutomaticLabeledContentStyle()
}

extension EnvironmentValues {
    package var labeledContentStyle: any LabeledContentStyle {
        get { self[LabeledContentStyleKey.self] }
        set { self[LabeledContentStyleKey.self] = newValue }
    }
}

extension View {
    /// Sets a style for labeled content.
    nonisolated public func labeledContentStyle<S: LabeledContentStyle>(_ style: S) -> some View {
        environment(\.labeledContentStyle, style)
    }
}
