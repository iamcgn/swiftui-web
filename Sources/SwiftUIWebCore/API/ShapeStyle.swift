/// A color or pattern to use when rendering a shape.
public protocol ShapeStyle: Sendable {}

extension Color: ShapeStyle {}

package struct ForegroundStyleKey: EnvironmentKey {
    package static let defaultValue: Color? = nil
}

package struct ForegroundGradientKey: EnvironmentKey {
    package static let defaultValue: (any _GradientStyle)? = nil
}

extension EnvironmentValues {
    /// The foreground colour set by `foregroundStyle`/`foregroundColor`, if any.
    package var foregroundColor: Color? {
        get { self[ForegroundStyleKey.self] }
        set { self[ForegroundStyleKey.self] = newValue }
    }

    /// A gradient set by `foregroundStyle`: text draws with it (Docs/elements/Gradient.md); a
    /// colour set afterwards clears it.
    package var foregroundGradient: (any _GradientStyle)? {
        get { self[ForegroundGradientKey.self] }
        set { self[ForegroundGradientKey.self] = newValue }
    }
}

/// A shape style that takes its levels from the current foreground style: `.primary` keeps it,
/// the lower levels fade it (approximate: 50 %, 35 %, 25 % and 18 % of its opacity).
public struct HierarchicalShapeStyle: ShapeStyle, Hashable, Sendable {
    package let level: Int
    package init(level: Int) { self.level = level }

    public static let primary = HierarchicalShapeStyle(level: 0)
    public static let secondary = HierarchicalShapeStyle(level: 1)
    public static let tertiary = HierarchicalShapeStyle(level: 2)
    public static let quaternary = HierarchicalShapeStyle(level: 3)
    public static let quinary = HierarchicalShapeStyle(level: 4)

    package var opacity: Double { [1, 0.5, 0.35, 0.25, 0.18][min(level, 4)] }

    /// The colour a level below the first resolves to when no foreground colour is set: the
    /// secondary label, then on macOS the primary faded by the level; on an iPhone the tertiary
    /// and quaternary labels are the secondary at half and 0.3 (ios/color/system: (60, 60, 67)
    /// at 60 %, 30 % and 18 %).
    package func color(foreground: Color?, isIOS: Bool) -> Color {
        if let foreground { return foreground.opacity(opacity) }
        if level == 1 { return Color.secondary }
        if isIOS { return Color.secondary.opacity(level == 2 ? 0.5 : 0.3) }
        return Color.primary.opacity(opacity)
    }
}

/// A background material: the content beneath, blurred, under a tint of the appearance's
/// ground (`ultraThin` … `ultraThick`, and `bar`, the material of a toolbar). The substrate
/// blurs what the view is over (`backdropBlur`); the tint is white in the light appearance and
/// near-black in the dark one, at an alpha that grows with the thickness (iOS 17 measured
/// over black and white: ultra-thin 0.55 / thin 0.7 / regular 0.82 / thick 0.9 / ultra-thick
/// 0.96; the bar is the regular material).
public struct Material: ShapeStyle, Hashable, Sendable {
    package enum Thickness: Hashable, Sendable { case ultraThin, thin, regular, thick, ultraThick, bar }
    package let thickness: Thickness
    package init(thickness: Thickness) { self.thickness = thickness }

    public static let ultraThinMaterial = Material(thickness: .ultraThin)
    public static let thinMaterial = Material(thickness: .thin)
    public static let regularMaterial = Material(thickness: .regular)
    public static let thickMaterial = Material(thickness: .thick)
    public static let ultraThickMaterial = Material(thickness: .ultraThick)
    public static let bar = Material(thickness: .bar)

    package var tintAlpha: Double {
        switch thickness {
        case .ultraThin: return 0.55
        case .thin: return 0.7
        case .regular, .bar: return 0.82
        case .thick: return 0.9
        case .ultraThick: return 0.96
        }
    }
    package var blurRadius: CGFloat {
        switch thickness {
        case .ultraThin: return 12
        case .thin: return 16
        case .regular, .bar: return 20
        case .thick: return 24
        case .ultraThick: return 28
        }
    }

    /// The tint over the blur, for the appearance.
    package func tint(in environment: EnvironmentValues) -> RGBA {
        environment.colorScheme == .dark ? RGBA(red: 0.12, green: 0.12, blue: 0.12, alpha: tintAlpha) : RGBA(red: 1, green: 1, blue: 1, alpha: tintAlpha)
    }

    /// Paints the material under `path`: the backdrop blurred within it, then the tint.
    @MainActor
    package func _fill(_ path: Path, in bounds: CGRect, environment: EnvironmentValues, into list: inout DisplayList) {
        list.append(.backdropBlur(path, bounds: bounds, radius: blurRadius))
        list.append(.fillPath(path, tint(in: environment), eoFill: false))
    }
}

extension ShapeStyle where Self == Material {
    public static var ultraThinMaterial: Material { .ultraThinMaterial }
    public static var thinMaterial: Material { .thinMaterial }
    public static var regularMaterial: Material { .regularMaterial }
    public static var thickMaterial: Material { .thickMaterial }
    public static var ultraThickMaterial: Material { .ultraThickMaterial }
    public static var bar: Material { .bar }
}

extension ShapeStyle where Self == HierarchicalShapeStyle {
    public static var primary: HierarchicalShapeStyle { .primary }
    public static var secondary: HierarchicalShapeStyle { .secondary }
    public static var tertiary: HierarchicalShapeStyle { .tertiary }
    public static var quaternary: HierarchicalShapeStyle { .quaternary }
    public static var quinary: HierarchicalShapeStyle { .quinary }
}

extension View {
    /// Sets a view's foreground elements to use a given style: a colour or a gradient replaces
    /// the inherited style; a hierarchical style keeps it (`.primary`) or fades it; other styles
    /// (`.foreground`) leave it.
    nonisolated public func foregroundStyle<S: ShapeStyle>(_ style: S) -> some View {
        transformEnvironment(\.self) { environment in
            if let color = style as? Color {
                environment.foregroundColor = color
                environment.foregroundGradient = nil
            } else if let level = style as? HierarchicalShapeStyle {
                if level.level > 0 {
                    // Fading a gradient is not supported: the level applies to the colour.
                    environment.foregroundColor = level.color(foreground: environment.foregroundColor, isIOS: environment.platformProfile.isIOS)
                    environment.foregroundGradient = nil
                }
            } else {
                // Gradient conformances are main-actor isolated; the cast must run there.
                let gradient: (any _GradientStyle)? = MainActor.assumeIsolated { style as? any _GradientStyle }
                if let gradient { environment.foregroundGradient = gradient }
            }
        }
    }

    /// Sets the color of the foreground elements displayed by this view.
    nonisolated public func foregroundColor(_ color: Color?) -> some View {
        transformEnvironment(\.self) { environment in
            environment.foregroundColor = color
            environment.foregroundGradient = nil
        }
    }
}

/// A gradient style held by a `Text` (a class so the text's modifiers stay `Equatable`).
package final class _GradientBox: Equatable, @unchecked Sendable {
    package let style: any _GradientStyle
    package init(_ style: any _GradientStyle) { self.style = style }
    package static func == (lhs: _GradientBox, rhs: _GradientBox) -> Bool { lhs === rhs }
}
