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
        .link: RGBA(r: 0, g: 104, b: 218),              // link/basic: 0, 104, 218
        .controlInk: .black,
        .windowBackground: .white,                      // NSColor.windowBackgroundColor (macOS 26.2)
        .controlBackground: .white,
        .knob: .white,
    ]

    /// System colours in the dark appearance, sampled from `dark/system-colors`, `dark/text` and
    /// `dark/controls` (macOS 26.2, 2026-09-04).
    package static let macOSDarkColors: [Color.SystemColor: RGBA] = [
        .red: RGBA(r: 255, g: 66, b: 69),
        .orange: RGBA(r: 255, g: 146, b: 48),
        .yellow: RGBA(r: 255, g: 214, b: 0),
        .green: RGBA(r: 48, g: 209, b: 88),
        .mint: RGBA(r: 0, g: 218, b: 195),
        .teal: RGBA(r: 0, g: 210, b: 224),
        .cyan: RGBA(r: 60, g: 211, b: 254),
        .blue: RGBA(r: 0, g: 145, b: 255),
        .indigo: RGBA(r: 109, g: 124, b: 255),
        .purple: RGBA(r: 219, g: 52, b: 242),
        .pink: RGBA(r: 255, g: 55, b: 95),
        .brown: RGBA(r: 183, g: 138, b: 102),
        .white: RGBA(r: 255, g: 255, b: 255),
        .gray: RGBA(r: 152, g: 152, b: 157),
        .black: RGBA(r: 0, g: 0, b: 0),
        .clear: .clear,
        .primary: RGBA(r: 255, g: 255, b: 255, a: 216.0 / 255),      // labelColor
        .secondary: RGBA(r: 255, g: 255, b: 255, a: 140.0 / 255),    // secondaryLabelColor
        .accentColor: RGBA(r: 0, g: 122, b: 255),                    // the dark accent is not the dark blue
        .link: RGBA(r: 65, g: 156, b: 255),
        .controlInk: .white,
        .windowBackground: RGBA(r: 30, g: 30, b: 30),
        .controlBackground: RGBA(r: 30, g: 30, b: 30),               // text field and list fills
        .knob: RGBA(r: 255, g: 255, b: 255, a: 222.0 / 255),
    ]

    package func resolve(_ system: Color.SystemColor, scheme: ColorScheme = .light) -> RGBA {
        (scheme == .dark ? Self.macOSDarkColors[system] : Self.macOSLightColors[system]) ?? .black
    }
}

extension EnvironmentValues {
    /// The control ink at `alpha`: black in the light appearance, white in the dark one.
    package func _ink(_ alpha: Double) -> RGBA {
        platformProfile.resolve(.controlInk, scheme: colorScheme).multiplyingAlpha(by: alpha)
    }

    /// The fill of text fields, lists and tables.
    package var _controlBackground: RGBA { platformProfile.resolve(.controlBackground, scheme: colorScheme) }
    package var _windowBackground: RGBA { platformProfile.resolve(.windowBackground, scheme: colorScheme) }
    package var _knob: RGBA { platformProfile.resolve(.knob, scheme: colorScheme) }
    package var _isDark: Bool { colorScheme == .dark }
}

extension Color {
    /// The colour's components in the given environment.
    package func resolve(in environment: EnvironmentValues) -> RGBA {
        let base: RGBA
        switch storage {
        case .rgba(let r, let g, let b, let a):
            base = RGBA(red: r, green: g, blue: b, alpha: a)
        case .system(let system):
            base = environment.platformProfile.resolve(system, scheme: environment.colorScheme)
        case .named(let name):
            // A missing colour set draws nothing (an assumption, see Docs/elements/Image.md).
            base = environment.assetCatalog.color(named: name, scheme: environment.colorScheme, idiom: environment.assetIdiom) ?? .clear
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
