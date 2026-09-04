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
                    environment.foregroundColor = environment.foregroundColor.map { $0.opacity(level.opacity) } ?? (level.level == 1 ? Color.secondary : Color.primary.opacity(level.opacity))
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
