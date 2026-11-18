// Text renderers (iOS 18, macOS 15): a renderer set with `textRenderer(_:)` draws the text views
// under it from their laid-out lines and runs, in a graphics context the size of the text.
// A run carries the custom attributes of the text it came from (`Text.customAttribute`), so a
// renderer can fill behind some runs and draw the rest as they would have drawn (Harbour's
// highlighted search matches). Each run draws its glyphs, inline images and decorations as the
// text would have; a renderer's own sizing (`sizeThatFits`) is not consulted.
import WebFoundation

/// A value a text carries for its renderer to read (`Text.customAttribute`).
public protocol TextAttribute: Hashable {}

/// A custom attribute, held erased in a text's modifiers.
package struct _AnyTextAttribute: Equatable, @unchecked Sendable {
    package let value: AnyHashable
    package let type: ObjectIdentifier
}

extension Text {
    /// Adds a custom attribute for a text renderer to read from the runs this text lays out as.
    public func customAttribute<T: TextAttribute>(_ value: T) -> Text {
        var t = self
        t.modifiers.customAttributes.append(_AnyTextAttribute(value: AnyHashable(value), type: ObjectIdentifier(T.self)))
        return t
    }
}

/// A value that draws text views from their layout (`textRenderer(_:)`).
@MainActor @preconcurrency
public protocol TextRenderer: Animatable {
    /// Draws the layout into the context, whose origin is the text view's.
    func draw(layout: Text.Layout, in context: inout GraphicsContext)
    /// How far the drawing may spill past the text's frame.
    var displayPadding: EdgeInsets { get }
}

extension TextRenderer {
    public var displayPadding: EdgeInsets { EdgeInsets() }
}

package struct TextRendererKey: EnvironmentKey {
    package nonisolated(unsafe) static let defaultValue: (any TextRenderer)? = nil
}

extension EnvironmentValues {
    package var _textRenderer: (any TextRenderer)? {
        get { self[TextRendererKey.self] }
        set { self[TextRendererKey.self] = newValue }
    }
}

extension View {
    /// Draws the text views under this view with the renderer.
    nonisolated public func textRenderer<T: TextRenderer>(_ renderer: T) -> some View {
        nonisolated(unsafe) let renderer = renderer
        return environment(\._textRenderer, renderer)
    }
}

extension Text {
    /// A text's lines as laid out for its renderer.
    public struct Layout: RandomAccessCollection {
        public typealias Index = Int
        public typealias Element = Line
        package var lines: [Line]
        /// Whether the text was cut short to fit.
        public var isTruncated: Bool
        public var startIndex: Int { 0 }
        public var endIndex: Int { lines.count }
        public subscript(index: Int) -> Line { lines[index] }

        /// A line's or a run's extent: its origin on the baseline, its width, and the font's
        /// ascent and descent above and below it.
        public struct TypographicBounds: Equatable, Sendable {
            public var origin: CGPoint
            public var width: CGFloat
            public var ascent: CGFloat
            public var descent: CGFloat
            public var leading: CGFloat
            /// The rectangle from the ascent to the descent.
            public var rect: CGRect { CGRect(x: origin.x, y: origin.y - ascent, width: width, height: ascent + descent) }
            public init(origin: CGPoint, width: CGFloat, ascent: CGFloat, descent: CGFloat, leading: CGFloat = 0) {
                self.origin = origin
                self.width = width
                self.ascent = ascent
                self.descent = descent
                self.leading = leading
            }
        }

        /// Options for drawing a line or run (accepted; glyphs draw at their positions).
        public struct DrawingOptions: OptionSet, Sendable {
            public let rawValue: UInt32
            public init(rawValue: UInt32) { self.rawValue = rawValue }
            public static let disablesSubpixelQuantization = DrawingOptions(rawValue: 1)
        }

        /// One line: its runs in order.
        public struct Line: RandomAccessCollection {
            public typealias Index = Int
            public typealias Element = Run
            package var runs: [Run]
            public var typographicBounds: TypographicBounds
            /// The line's baseline origin.
            public var origin: CGPoint { typographicBounds.origin }
            public var startIndex: Int { 0 }
            public var endIndex: Int { runs.count }
            public subscript(index: Int) -> Run { runs[index] }
        }

        /// A run of glyphs in one style: as a collection, the one slice of the whole run.
        public struct Run: RandomAccessCollection {
            public typealias Index = Int
            public typealias Element = RunSlice
            /// What the run paints, in the coordinates of the text's display list, and the
            /// transform from the text's own space to those coordinates.
            package var commands: [DisplayCommand]
            package var base: CGAffineTransform
            package var attributes: [_AnyTextAttribute]
            public var typographicBounds: TypographicBounds
            public var layoutDirection: LayoutDirection { .leftToRight }
            public var startIndex: Int { 0 }
            public var endIndex: Int { 1 }
            public subscript(index: Int) -> RunSlice { RunSlice(run: self) }
            /// The run's custom attribute of the type, if its text has one.
            public subscript<T: TextAttribute>(_ type: T.Type) -> T? {
                attributes.last { $0.type == ObjectIdentifier(T.self) }?.value.base as? T
            }
        }

        /// A part of a run.
        public struct RunSlice {
            public let run: Run
            public var typographicBounds: TypographicBounds { run.typographicBounds }
            public subscript<T: TextAttribute>(_ type: T.Type) -> T? { run[type] }
        }
    }
}

extension GraphicsContext {
    /// Draws a run's glyphs, images and decorations as its text would have drawn them.
    @MainActor public func draw(_ run: Text.Layout.Run, options: Text.Layout.DrawingOptions = .init()) {
        _appendRecorded(run.commands, from: run.base, bounds: run.typographicBounds.rect)
    }

    @MainActor public func draw(_ slice: Text.Layout.RunSlice, options: Text.Layout.DrawingOptions = .init()) {
        draw(slice.run, options: options)
    }

    @MainActor public func draw(_ line: Text.Layout.Line, options: Text.Layout.DrawingOptions = .init()) {
        for run in line { draw(run, options: options) }
    }

    @MainActor public func draw(_ layout: Text.Layout, options: Text.Layout.DrawingOptions = .init()) {
        for line in layout { draw(line, options: options) }
    }
}
