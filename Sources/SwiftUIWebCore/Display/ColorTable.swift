extension PlatformProfile {
    /// System colours in the light appearance, sampled from `paint/system-colors` goldens
    /// (macOS 26.2, 2026-09-02). Dark appearance arrives with `colorScheme`.
    package static let macOSLightColors: [Color.SystemColor: RGBA] = [
        .red: RGBA(r: 255, g: 56, b: 60),
        .orange: RGBA(r: 255, g: 141, b: 40),
        .yellow: RGBA(r: 255, g: 204, b: 0),
        .green: RGBA(r: 52, g: 199, b: 89),
        .mint: RGBA(r: 0, g: 200, b: 179),
        .teal: RGBA(r: 0, g: 195, b: 208),
        .cyan: RGBA(r: 0, g: 192, b: 232),
        .blue: RGBA(r: 0, g: 136, b: 255),
        .indigo: RGBA(r: 97, g: 85, b: 245),
        .purple: RGBA(r: 203, g: 48, b: 224),
        .pink: RGBA(r: 255, g: 45, b: 85),
        .brown: RGBA(r: 172, g: 127, b: 94),
        .white: RGBA(r: 255, g: 255, b: 255),
        .gray: RGBA(r: 142, g: 142, b: 147),
        .black: RGBA(r: 0, g: 0, b: 0),
        .clear: .clear,
        .primary: RGBA(r: 0, g: 0, b: 0, a: 0.85),      // labelColor (216/255)
        .secondary: RGBA(r: 0, g: 0, b: 0, a: 0.5),     // secondaryLabelColor (127/255)
        .accentColor: RGBA(r: 0, g: 136, b: 255),       // default accent = blue
    ]

    package func resolve(_ system: Color.SystemColor) -> RGBA {
        Self.macOSLightColors[system] ?? .black
    }
}

extension Color {
    /// The colour's components in the given environment.
    package func resolve(in environment: EnvironmentValues) -> RGBA {
        let base: RGBA
        switch storage {
        case .rgba(let r, let g, let b, let a):
            base = RGBA(red: r, green: g, blue: b, alpha: a)
        case .system(let system):
            base = environment.platformProfile.resolve(system)
        }
        return base.multiplyingAlpha(by: opacityMultiplier)
    }
}

/// The foreground style of the current environment (`Color.primary` unless overridden).
@frozen
public struct ForegroundStyle: ShapeStyle, Sendable {
    public init() {}
}

extension ShapeStyle where Self == ForegroundStyle {
    public static var foreground: ForegroundStyle { ForegroundStyle() }
}

extension ShapeStyle where Self == Color {
    public static var red: Color { .red }
    public static var orange: Color { .orange }
    public static var yellow: Color { .yellow }
    public static var green: Color { .green }
    public static var mint: Color { .mint }
    public static var teal: Color { .teal }
    public static var cyan: Color { .cyan }
    public static var blue: Color { .blue }
    public static var indigo: Color { .indigo }
    public static var purple: Color { .purple }
    public static var pink: Color { .pink }
    public static var brown: Color { .brown }
    public static var white: Color { .white }
    public static var gray: Color { .gray }
    public static var black: Color { .black }
    public static var clear: Color { .clear }
    public static var primary: Color { .primary }
    public static var secondary: Color { .secondary }
    public static var accentColor: Color { .accentColor }
}

extension ShapeStyle {
    /// Resolves the style to a flat colour. Gradients and materials arrive in Phase 2.
    package func resolveColor(in environment: EnvironmentValues) -> RGBA {
        if let color = self as? Color {
            return color.resolve(in: environment)
        }
        return (environment.foregroundColor ?? .primary).resolve(in: environment)
    }
}
