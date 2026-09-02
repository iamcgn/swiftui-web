/// A color or pattern to use when rendering a shape.
public protocol ShapeStyle: Sendable {}

extension Color: ShapeStyle {}

package struct ForegroundStyleKey: EnvironmentKey {
    package static let defaultValue: Color? = nil
}

extension EnvironmentValues {
    /// The foreground colour set by `foregroundStyle`/`foregroundColor`, if any.
    package var foregroundColor: Color? {
        get { self[ForegroundStyleKey.self] }
        set { self[ForegroundStyleKey.self] = newValue }
    }
}

extension View {
    /// Sets a view's foreground elements to use a given style.
    nonisolated public func foregroundStyle<S: ShapeStyle>(_ style: S) -> some View {
        environment(\.foregroundColor, style as? Color)
    }

    /// Sets the color of the foreground elements displayed by this view.
    nonisolated public func foregroundColor(_ color: Color?) -> some View {
        environment(\.foregroundColor, color)
    }
}
