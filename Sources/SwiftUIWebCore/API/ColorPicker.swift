// ColorPicker (Docs/elements/ColorPicker.md): the macOS colour well (a grey rounded rect with a
// concentric swatch over a black/white diagonal ground) with its label; a press opens a popover
// of preset swatches and, when opacity is supported, an opacity slider.
#if os(WASI)
import WebFoundation   // never full Foundation on wasm: it links ICU (decisions 0006, 0017)
#else
import Foundation
#endif

/// A control used to select a colour from the system colour picker UI.
public struct ColorPicker<Label: View>: View {
    package let label: Label
    package let selection: Binding<Color>
    package let supportsOpacity: Bool
    package let title: String?

    @Environment(\.labelsHidden) private var labelsHidden
    @Environment(\._formStyle) private var formStyle

    /// Creates an instance that selects a colour.
    public init(selection: Binding<Color>, supportsOpacity: Bool = true, @ViewBuilder label: () -> Label) {
        self.label = label()
        self.selection = selection
        self.supportsOpacity = supportsOpacity
        title = nil
    }

    package init(title: String, selection: Binding<Color>, supportsOpacity: Bool, label: Label) {
        self.label = label
        self.selection = selection
        self.supportsOpacity = supportsOpacity
        self.title = title
    }

    public var body: some View {
        // Read the selection here so observation tracks the model it comes from.
        let color = selection.wrappedValue
        let well = _ColorWellHost(color: color, selection: _ColorBinding(selection), supportsOpacity: supportsOpacity, title: title)
        let mode: _FormRowMode
        switch formStyle {
        case .grouped: mode = .grouped
        case .columns: mode = .firstTextBaseline
        case nil: mode = .centeredFractional
        }
        return _FormLabeledRow(label: labelsHidden ? nil : AnyView(_ControlLabel(label: label)), content: AnyView(well), mode: mode)
    }
}

extension ColorPicker where Label == Text {
    /// Creates a colour picker with a text label generated from a title string key.
    public init(_ titleKey: LocalizedStringKey, selection: Binding<Color>, supportsOpacity: Bool = true) {
        let text = Text(titleKey)
        self.init(title: text.resolvedString, selection: selection, supportsOpacity: supportsOpacity, label: text)
    }

    /// Creates a colour picker with a text label generated from a title string.
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, selection: Binding<Color>, supportsOpacity: Bool = true) {
        self.init(title: String(title), selection: selection, supportsOpacity: supportsOpacity, label: Text(title))
    }
}

// MARK: - Primitives

/// The selection binding boxed (a class, so field reflection ignores it).
@MainActor
package final class _ColorBinding {
    package let binding: Binding<Color>
    package init(_ binding: Binding<Color>) { self.binding = binding }
}

/// The colour well (`ColorWellNode`).
public struct _ColorWellHost: View {
    package let color: Color
    package let selection: _ColorBinding
    package let supportsOpacity: Bool
    package let title: String?

    package init(color: Color, selection: _ColorBinding, supportsOpacity: Bool, title: String?) {
        self.color = color
        self.selection = selection
        self.supportsOpacity = supportsOpacity
        self.title = title
    }

    public typealias Body = Never
    public static func _makeNode(_ context: _NodeContext<_ColorWellHost>) -> TypedNode<_ColorWellHost> {
        ColorWellNode(context)
    }
}

/// The popover a well opens: a grid of preset swatches (a press picks one and closes the
/// panel) and, when the picker supports opacity, an opacity slider. Apple shows the system
/// colour panel, a separate window that fixtures cannot capture; this panel is unverified.
package struct _ColorPanel: View {
    package let selection: _ColorBinding
    package let supportsOpacity: Bool
    package let dismiss: @MainActor () -> Void
    @Environment(\.self) private var environment

    package static let swatches: [Color] = [.red, .orange, .yellow, .green, .mint, .teal, .cyan, .blue,
                                            .indigo, .purple, .pink, .brown, .black, .gray, .white, .clear]

    package init(selection: _ColorBinding, supportsOpacity: Bool, dismiss: @escaping @MainActor () -> Void) {
        self.selection = selection
        self.supportsOpacity = supportsOpacity
        self.dismiss = dismiss
    }

    private var opacity: Binding<Double> {
        Binding(get: { Double(selection.binding.wrappedValue.resolve(in: environment).alpha) },
                set: { value in
                    let rgba = selection.binding.wrappedValue.resolve(in: environment)
                    selection.binding.wrappedValue = Color(red: Double(rgba.red), green: Double(rgba.green), blue: Double(rgba.blue), opacity: value)
                })
    }

    package var body: some View {
        let size = PlatformMetrics.colorPanelSwatchSize
        VStack(alignment: .leading, spacing: PlatformMetrics.colorPanelSwatchSpacing) {
            ForEach(0..<4) { row in
                HStack(spacing: PlatformMetrics.colorPanelSwatchSpacing) {
                    ForEach(0..<4) { column in
                        let color = Self.swatches[row * 4 + column]
                        Button {
                            let alpha = supportsOpacity ? selection.binding.wrappedValue.resolve(in: environment).alpha : 1
                            selection.binding.wrappedValue = alpha == 1 ? color : color.opacity(Double(alpha))
                            dismiss()
                        } label: {
                            ZStack {
                                _ColorSwatch(color: color, size: size)
                                RoundedRectangle(cornerRadius: 4).stroke(Color.primary.opacity(0.2), lineWidth: 1)
                            }
                            .frame(width: size, height: size)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(_ColorSwatch.name(of: color)))
                    }
                }
            }
            if supportsOpacity {
                Slider(value: opacity, in: 0...1) { Text("Opacity") }
                    .frame(width: 4 * size + 3 * PlatformMetrics.colorPanelSwatchSpacing)
            }
        }
    }
}

/// A preset swatch: the colour over a black/white diagonal, like the well.
package struct _ColorSwatch: View {
    package let color: Color
    package let size: CGFloat

    package static func name(of color: Color) -> String {
        switch color {
        case .red: return "Red"
        case .orange: return "Orange"
        case .yellow: return "Yellow"
        case .green: return "Green"
        case .mint: return "Mint"
        case .teal: return "Teal"
        case .cyan: return "Cyan"
        case .blue: return "Blue"
        case .indigo: return "Indigo"
        case .purple: return "Purple"
        case .pink: return "Pink"
        case .brown: return "Brown"
        case .black: return "Black"
        case .gray: return "Gray"
        case .white: return "White"
        case .clear: return "Clear"
        default: return "Color"
        }
    }

    package var body: some View {
        _ColorSwatchHost(color: color).frame(width: size, height: size)
    }
}

/// A swatch primitive painted like the well's (`ColorSwatchNode`).
public struct _ColorSwatchHost: View {
    package let color: Color
    package init(color: Color) { self.color = color }
    public typealias Body = Never
    public static func _makeNode(_ context: _NodeContext<_ColorSwatchHost>) -> TypedNode<_ColorSwatchHost> {
        ColorSwatchNode(context)
    }
}

// MARK: - CGColor selections (sw-colorpicker)

extension ColorPicker where Label == Text {
    /// Creates a colour picker with a text label and a Core Graphics colour selection.
    public init(_ titleKey: LocalizedStringKey, selection: Binding<CGColor>, supportsOpacity: Bool = true) {
        self.init(titleKey, selection: Self._colorBinding(selection), supportsOpacity: supportsOpacity)
    }

    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, selection: Binding<CGColor>, supportsOpacity: Bool = true) {
        self.init(title, selection: Self._colorBinding(selection), supportsOpacity: supportsOpacity)
    }
}

extension ColorPicker {
    /// Creates a colour picker with a Core Graphics colour selection and a custom label.
    public init(selection: Binding<CGColor>, supportsOpacity: Bool = true, @ViewBuilder label: () -> Label) {
        self.init(selection: Self._colorBinding(selection), supportsOpacity: supportsOpacity, label: label)
    }

    /// A `CGColor` binding seen as a `Color` one: reads convert the components, writes resolve
    /// the colour in the default (light) environment.
    package static func _colorBinding(_ binding: Binding<CGColor>) -> Binding<Color> {
        Binding(get: { Color(cgColor: binding.wrappedValue) },
                set: { binding.wrappedValue = $0.cgColor ?? $0.resolve(in: EnvironmentValues()).cgColor })
    }
}

extension Color {
    /// Creates a colour from a Core Graphics colour (sRGB components; an unreadable colour
    /// space gives black).
    public init(cgColor: CGColor) {
        let rgba = RGBA(cgColor: cgColor) ?? RGBA(red: 0, green: 0, blue: 0, alpha: 1)
        self.init(red: Double(rgba.red), green: Double(rgba.green), blue: Double(rgba.blue), opacity: Double(rgba.alpha))
    }

    /// The colour as a Core Graphics colour when it was made from components; nil for the
    /// system, named and dynamic colours, which resolve per environment (as SwiftUI's).
    public var cgColor: CGColor? {
        guard case .rgba(let r, let g, let b, let a) = storage else { return nil }
        return RGBA(red: r, green: g, blue: b, alpha: a * opacityMultiplier).cgColor
    }
}

extension UTType {
    /// A colour on the pasteboard (AppKit's `NSPasteboard.PasteboardType.color`).
    public static let color = UTType("com.apple.cocoa.pasteboard.color")
}

/// Colours drag and drop (`draggable`, `dropDestination(for: Color.self)`, a colour well): the
/// payload travels as itself; the data form is the sRGB components as text.
extension Color: Transferable {
    public static var transferRepresentation: some TransferRepresentation<Color> {
        DataRepresentation(contentType: .color, exporting: { color in
            let rgba = color.resolve(in: EnvironmentValues())
            return Data("\(rgba.red) \(rgba.green) \(rgba.blue) \(rgba.alpha)".utf8)
        }, importing: { data in
            let parts = String(decoding: data, as: UTF8.self).split(separator: " ").compactMap { Double($0) }
            guard parts.count == 4 else { return .black }
            return Color(red: parts[0], green: parts[1], blue: parts[2], opacity: parts[3])
        })
    }
}
