/// A control that toggles between on and off states.
///
/// macOS styles, measured in `Docs/elements/Toggle.md`: the default is a 16 pt checkbox 5 pt
/// before a `.body` label, centred on the label's cap height; `.switch` is a 54 × 24 capsule
/// after the label; `.button` is a bordered button that turns prominent when on.
public struct Toggle<Label: View>: View {
    package let isOn: Binding<Bool>
    package let label: Label

    /// Creates a toggle that displays a custom label.
    public init(isOn: Binding<Bool>, @ViewBuilder label: () -> Label) {
        self.isOn = isOn
        self.label = label()
    }

    @Environment(\.toggleStyle) private var style
    @Environment(\._formStyle) private var formStyle
    @Environment(\.labelsHidden) private var labelsHidden

    public var body: some View {
        let configuration = ToggleStyleConfiguration(label: ToggleStyleConfiguration.Label(AnyView(label)), isOn: isOn)
        if formStyle == .grouped {
            // A grouped form row: the label leading, a switch trailing (Docs/elements/Form.md).
            _FormLabeledRow(label: labelsHidden ? nil : AnyView(_ControlLabel(label: label)),
                            content: AnyView(_ToggleHost(isOn: isOn, content: AnyView(_SwitchControl(isOn: isOn.wrappedValue, small: true)))),
                            mode: .grouped)
        } else {
            _ToggleHost(isOn: isOn, content: AnyView(style.makeBodyErased(configuration)))
        }
    }
}

extension Toggle where Label == Text {
    /// Creates a toggle that generates its label from a localized string key.
    public init(_ titleKey: LocalizedStringKey, isOn: Binding<Bool>) {
        self.init(isOn: isOn) { Text(titleKey) }
    }

    /// Creates a toggle that generates its label from a string.
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, isOn: Binding<Bool>) {
        self.init(isOn: isOn) { Text(title) }
    }
}

extension Toggle where Label == SwiftUIWebCore.Label<Text, Image> {
    /// Creates a toggle with a label from a title and an image resource.
    public init(_ titleKey: LocalizedStringKey, image name: String, isOn: Binding<Bool>) {
        self.init(isOn: isOn) { SwiftUIWebCore.Label(titleKey, image: name) }
    }

    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, image name: String, isOn: Binding<Bool>) {
        self.init(isOn: isOn) { SwiftUIWebCore.Label(title, image: name) }
    }

    /// Creates a toggle with a label from a title and a system symbol (stub symbol).
    public init(_ titleKey: LocalizedStringKey, systemImage name: String, isOn: Binding<Bool>) {
        self.init(isOn: isOn) { SwiftUIWebCore.Label(titleKey, systemImage: name) }
    }

    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, systemImage name: String, isOn: Binding<Bool>) {
        self.init(isOn: isOn) { SwiftUIWebCore.Label(title, systemImage: name) }
    }
}

extension Toggle where Label == ToggleStyleConfiguration.Label {
    /// Creates a toggle based on a toggle style configuration (for custom styles).
    public init(_ configuration: ToggleStyleConfiguration) {
        self.init(isOn: configuration.$isOn) { configuration.label }
    }
}

// MARK: - Styles

/// The properties of a toggle instance.
public struct ToggleStyleConfiguration {
    /// A type-erased label of a toggle.
    public struct Label: View {
        package let content: AnyView
        package init(_ content: AnyView) { self.content = content }
        public var body: some View { content }
    }

    public let label: Label
    @Binding public var isOn: Bool
    /// Whether the toggle is in a mixed state (never, until `Toggle(sources:isOn:)` exists).
    public var isMixed: Bool = false

    package init(label: Label, isOn: Binding<Bool>) {
        self.label = label
        self._isOn = isOn
    }
}

/// The appearance and behavior of a toggle.
@MainActor @preconcurrency
public protocol ToggleStyle {
    associatedtype Body: View
    @ViewBuilder func makeBody(configuration: Self.Configuration) -> Self.Body
    typealias Configuration = ToggleStyleConfiguration
}

extension ToggleStyle {
    @MainActor
    package func makeBodyErased(_ configuration: Configuration) -> AnyView {
        AnyView(makeBody(configuration: configuration))
    }
}

/// The default toggle style: a checkbox on macOS.
public struct DefaultToggleStyle: ToggleStyle {
    nonisolated public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        _PlatformToggleBody(configuration: configuration, switchStyle: false)
    }
}

/// The platform's look: macOS's checkbox (or switch), iOS's switch row (ios/toggle/basic): the
/// label leading, the switch at the trailing edge of the proposed width, 28 pt tall, and both
/// text baselines at the row's top (an `HStack(alignment: .firstTextBaseline)` hangs the row
/// 18 pt below a neighbouring body text).
struct _PlatformToggleBody: View {
    let configuration: ToggleStyleConfiguration
    let switchStyle: Bool
    @Environment(\.platformProfile) private var profile
    @Environment(\.labelsHidden) private var labelsHidden

    var body: some View {
        if profile.isIOS {
            if labelsHidden {
                _SwitchControl(isOn: configuration.isOn)
            } else {
                HStack(alignment: .center, spacing: profile.metrics.switchLabelSpacing) {
                    _ControlLabel(label: configuration.label)
                    Spacer(minLength: 0)
                    _SwitchControl(isOn: configuration.isOn)
                }
                .frame(maxWidth: .infinity)
                .alignmentGuide(.firstTextBaseline) { _ in 0 }
                .alignmentGuide(.lastTextBaseline) { _ in 0 }
            }
        } else if switchStyle {
            _SwitchToggleBody(configuration: configuration)
        } else {
            _CheckboxToggleBody(configuration: configuration)
        }
    }
}

/// A toggle style that displays a checkbox followed by its label.
public struct CheckboxToggleStyle: ToggleStyle {
    nonisolated public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        _CheckboxToggleBody(configuration: configuration)
    }
}

/// A toggle style that displays a leading label and a trailing switch.
public struct SwitchToggleStyle: ToggleStyle {
    nonisolated public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        _PlatformToggleBody(configuration: configuration, switchStyle: true)
    }
}

/// A toggle style that displays as a button with its label as the title.
public struct ButtonToggleStyle: ToggleStyle {
    nonisolated public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        _ButtonToggleBody(configuration: configuration)
    }
}

extension ToggleStyle where Self == DefaultToggleStyle {
    public static var automatic: DefaultToggleStyle { DefaultToggleStyle() }
}
extension ToggleStyle where Self == CheckboxToggleStyle {
    public static var checkbox: CheckboxToggleStyle { CheckboxToggleStyle() }
}
extension ToggleStyle where Self == SwitchToggleStyle {
    public static var `switch`: SwitchToggleStyle { SwitchToggleStyle() }
}
extension ToggleStyle where Self == ButtonToggleStyle {
    public static var button: ButtonToggleStyle { ButtonToggleStyle() }
}

package struct ToggleStyleKey: EnvironmentKey {
    package nonisolated(unsafe) static let defaultValue: any ToggleStyle = DefaultToggleStyle()
}

extension EnvironmentValues {
    package var toggleStyle: any ToggleStyle {
        get { self[ToggleStyleKey.self] }
        set { self[ToggleStyleKey.self] = newValue }
    }
}

extension View {
    /// Sets the style for toggles in a view hierarchy.
    nonisolated public func toggleStyle<S: ToggleStyle>(_ style: S) -> some View {
        environment(\.toggleStyle, style)
    }
}

// MARK: - Style bodies

/// The label a control shows: hidden by `labelsHidden`, dimmed when disabled, in `.body`.
package struct _ControlLabel<Content: View>: View {
    package let label: Content
    @Environment(\.labelsHidden) private var labelsHidden
    @Environment(\.isEnabled) private var isEnabled

    package init(label: Content) { self.label = label }

    package var body: some View {
        if !labelsHidden {
            _IconAlignedTitle(content: label)
                .font(.body)
                .foregroundColor(isEnabled ? nil : Color.primary.opacity(PlatformMetrics.disabledLabelOpacity))
        }
    }
}

struct _CheckboxToggleBody: View {
    let configuration: ToggleStyleConfiguration

    var body: some View {
        HStack(alignment: ._iconCenter, spacing: PlatformMetrics.checkboxLabelSpacing) {
            _CheckboxControl(isOn: configuration.isOn)
            _ControlLabel(label: configuration.label)
        }
    }
}

struct _SwitchToggleBody: View {
    let configuration: ToggleStyleConfiguration

    var body: some View {
        HStack(alignment: .center, spacing: PlatformMetrics.switchLabelSpacing) {
            _ControlLabel(label: configuration.label)
            _SwitchControl(isOn: configuration.isOn)
        }
    }
}

struct _ButtonToggleBody: View {
    let configuration: ToggleStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let on = configuration.isOn
        configuration.label
            .font(.system(size: PlatformMetrics.buttonLabelSize))
            .foregroundColor(on ? Color.white : (isEnabled ? nil : Color.primary.opacity(PlatformMetrics.disabledLabelOpacity)))
            .padding(.horizontal, PlatformMetrics.buttonHorizontalPadding)
            .padding(.vertical, PlatformMetrics.buttonVerticalPadding)
            .frame(minHeight: PlatformMetrics.buttonHeight)
            .background(
                RoundedRectangle(cornerRadius: PlatformMetrics.buttonCornerRadius, style: .circular)
                    .fill(on ? Color.accentColor : PlatformMetrics.buttonFill))
    }
}

// MARK: - Primitives

/// Owns a toggle's activation: a press released inside flips the binding. Transparent to layout.
public struct _ToggleHost: View {
    package let isOn: Binding<Bool>
    package let content: AnyView

    package init(isOn: Binding<Bool>, content: AnyView) {
        self.isOn = isOn
        self.content = content
    }

    public typealias Body = Never

    public static func _makeNode(_ context: _NodeContext<_ToggleHost>) -> TypedNode<_ToggleHost> {
        ToggleHostNode(context)
    }
}

/// The 16 × 16 macOS checkbox.
public struct _CheckboxControl: View {
    package let isOn: Bool
    package init(isOn: Bool) { self.isOn = isOn }

    public typealias Body = Never

    public static func _makeNode(_ context: _NodeContext<_CheckboxControl>) -> TypedNode<_CheckboxControl> {
        CheckboxNode(context)
    }
}

/// The 54 × 24 macOS switch (or the small one grouped forms use).
public struct _SwitchControl: View {
    package let isOn: Bool
    package let small: Bool
    package init(isOn: Bool, small: Bool = false) {
        self.isOn = isOn
        self.small = small
    }

    public typealias Body = Never

    public static func _makeNode(_ context: _NodeContext<_SwitchControl>) -> TypedNode<_SwitchControl> {
        SwitchNode(context)
    }
}

// MARK: - Environment: labelsHidden, isEnabled

package struct LabelsHiddenKey: EnvironmentKey {
    package static let defaultValue = false
}

package struct IsEnabledKey: EnvironmentKey {
    package static let defaultValue = true
}

extension EnvironmentValues {
    /// Whether controls in this environment hide their labels.
    package var labelsHidden: Bool {
        get { self[LabelsHiddenKey.self] }
        set { self[LabelsHiddenKey.self] = newValue }
    }

    /// Whether the view associated with this environment allows user interaction.
    public var isEnabled: Bool {
        get { self[IsEnabledKey.self] }
        set { self[IsEnabledKey.self] = newValue }
    }
}

extension View {
    /// Hides the labels of any controls contained within this view.
    nonisolated public func labelsHidden() -> some View {
        environment(\.labelsHidden, true)
    }

    /// Adds a condition that controls whether users can interact with this view.
    nonisolated public func disabled(_ disabled: Bool) -> some View {
        transformEnvironment(\.isEnabled) { $0 = $0 && !disabled }
    }
}
