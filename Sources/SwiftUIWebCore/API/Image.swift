// Image: a named image from the app's asset catalogs (decision 0011), its resizing, rendering
// and interpolation modifiers, and the aspect-ratio layout modifier. Docs/elements/Image.md.
#if !os(WASI)
import Foundation
#endif

/// A view that displays an image.
public struct Image: Equatable, Sendable {
    package enum Source: Equatable, Sendable {
        case named(String)
        case system(String)
    }

    /// How a resizable image fills its frame.
    public enum ResizingMode: Hashable, CaseIterable, Sendable {
        case tile
        case stretch
    }

    /// Whether an image draws its own colours or is used as a mask for the foreground style.
    public enum TemplateRenderingMode: Hashable, CaseIterable, Sendable {
        case template
        case original
    }

    /// The quality of scaling applied when drawing.
    public enum Interpolation: Hashable, CaseIterable, Sendable {
        case none
        case low
        case medium
        case high
    }

    /// A scale to apply to symbol images relative to the text they accompany.
    public enum Scale: Hashable, CaseIterable, Sendable {
        case small
        case medium
        case large
    }

    package struct Resizing: Equatable, Sendable {
        package var capInsets: EdgeInsets
        package var mode: ResizingMode
    }

    package var source: Source
    package var label: String?
    package var isDecorative = false
    package var resizing: Resizing?
    package var renderingMode: TemplateRenderingMode?
    package var interpolation: Interpolation = .high
    package var isAntialiased = true

    package init(source: Source, label: String?) {
        self.source = source
        self.label = label
    }

    #if os(WASI)
    /// Creates a labeled image that you can use as content for controls. The bundle is the app's
    /// asset manifest; there is no `Bundle` on wasm.
    public init(_ name: String) {
        self.init(source: .named(name), label: name)
    }

    /// Creates an unlabeled, decorative image.
    public init(decorative name: String) {
        self.init(source: .named(name), label: nil)
        isDecorative = true
    }

    /// Creates a labeled image that you can use as content for controls, with the specified label.
    public init(_ name: String, label: Text) {
        self.init(source: .named(name), label: label.resolvedString)
    }

    /// Creates an image with a variable value (the value is ignored).
    public init(_ name: String, variableValue: Double?) {
        self.init(source: .named(name), label: name)
    }
    #else
    /// Creates a labeled image that you can use as content for controls. The bundle is ignored:
    /// every catalog of the app is in one manifest.
    public init(_ name: String, bundle: Bundle? = nil) {
        self.init(source: .named(name), label: name)
    }

    /// Creates an unlabeled, decorative image.
    public init(decorative name: String, bundle: Bundle? = nil) {
        self.init(source: .named(name), label: nil)
        isDecorative = true
    }

    /// Creates a labeled image that you can use as content for controls, with the specified label.
    public init(_ name: String, bundle: Bundle? = nil, label: Text) {
        self.init(source: .named(name), label: label.resolvedString)
    }

    /// Creates an image with a variable value (the value is ignored).
    public init(_ name: String, variableValue: Double?, bundle: Bundle? = nil) {
        self.init(source: .named(name), label: name)
    }
    #endif

    /// Creates a system symbol image. Stub: SF Symbols are not available; lays out at 0 × 0.
    public init(systemName: String) {
        self.init(source: .system(systemName), label: systemName)
    }

    /// Creates a system symbol image with a variable value. Stub, as `init(systemName:)`.
    public init(systemName: String, variableValue: Double?) {
        self.init(source: .system(systemName), label: systemName)
    }

    /// Sets the mode by which SwiftUI resizes an image to fit its space.
    public func resizable(capInsets: EdgeInsets = EdgeInsets(), resizingMode: ResizingMode = .stretch) -> Image {
        var copy = self
        copy.resizing = Resizing(capInsets: capInsets, mode: resizingMode)
        return copy
    }

    /// Indicates whether SwiftUI renders an image as-is, or by using a different mode.
    public func renderingMode(_ renderingMode: TemplateRenderingMode?) -> Image {
        var copy = self
        copy.renderingMode = renderingMode
        return copy
    }

    /// Specifies the current level of quality for rendering an image that requires interpolation.
    public func interpolation(_ interpolation: Interpolation) -> Image {
        var copy = self
        copy.interpolation = interpolation
        return copy
    }

    /// Specifies whether SwiftUI applies antialiasing when rendering the image.
    public func antialiased(_ isAntialiased: Bool) -> Image {
        var copy = self
        copy.isAntialiased = isAntialiased
        return copy
    }
}

extension Image: View {
    public typealias Body = Never

    public static func _makeNode(_ context: _NodeContext<Image>) -> TypedNode<Image> {
        ImageNode(context)
    }
}

package struct ImageScaleKey: EnvironmentKey {
    package static let defaultValue = Image.Scale.medium
}

extension EnvironmentValues {
    /// The size to apply to symbol images (no effect yet: symbols are stubs).
    public var imageScale: Image.Scale {
        get { self[ImageScaleKey.self] }
        set { self[ImageScaleKey.self] = newValue }
    }
}

extension View {
    /// Scales images within the view according to one of the relative sizes available.
    nonisolated public func imageScale(_ scale: Image.Scale) -> some View {
        environment(\.imageScale, scale)
    }
}

// MARK: - Aspect ratio

/// Constants that define how a view's content fills the available space.
public enum ContentMode: Hashable, CaseIterable, Sendable {
    case fit
    case fill
}

/// Constrains the content's dimensions to an aspect ratio. Measured rules in
/// Docs/elements/Image.md: the ratio is the explicit one or the content's ideal size; the
/// content is proposed the fitted (or filling) rectangle of the proposal and the modifier takes
/// the content's answer, so a rigid image stays rigid and a resizable one follows the ratio.
@frozen
public struct _AspectRatioLayout: Equatable {
    package let aspectRatio: CGFloat?
    package let contentMode: ContentMode

    package init(aspectRatio: CGFloat?, contentMode: ContentMode) {
        self.aspectRatio = aspectRatio
        self.contentMode = contentMode
    }
}

extension _AspectRatioLayout: ViewModifier {
    public typealias Body = Never

    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        AspectRatioNode(context)
    }
}

extension View {
    /// Constrains this view's dimensions to the specified aspect ratio.
    nonisolated public func aspectRatio(_ aspectRatio: CGFloat? = nil, contentMode: ContentMode) -> some View {
        modifier(_AspectRatioLayout(aspectRatio: aspectRatio, contentMode: contentMode))
    }

    /// Constrains this view's dimensions to the aspect ratio of the given size.
    nonisolated public func aspectRatio(_ aspectRatio: CGSize, contentMode: ContentMode) -> some View {
        modifier(_AspectRatioLayout(aspectRatio: aspectRatio.width / aspectRatio.height, contentMode: contentMode))
    }

    /// Scales this view to fit its parent.
    nonisolated public func scaledToFit() -> some View {
        aspectRatio(nil, contentMode: .fit)
    }

    /// Scales this view to fill its parent.
    nonisolated public func scaledToFill() -> some View {
        aspectRatio(nil, contentMode: .fill)
    }
}
