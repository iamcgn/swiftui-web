// Pointer hovering: `onHover`, `onContinuousHover`, `help` (a tooltip) and `pointerStyle`. The
// runtime tracks the pointer between presses (hosts forward every move and the leave event);
// nodes conforming to `_HoverTracking` hear when the pointer enters, moves within and leaves
// their frame.

/// The phases of a continuous hover.
public enum HoverPhase: Equatable, Sendable {
    /// The pointer is over the view, at the given location in the requested coordinate space.
    case active(CGPoint)
    case ended
}

/// The appearance of the pointer over a view (`pointerStyle`).
public struct PointerStyle: Equatable, Sendable {
    /// The CSS cursor the browser host uses.
    package let css: String
    package init(css: String) { self.css = css }

    public static let `default` = PointerStyle(css: "default")
    public static let link = PointerStyle(css: "pointer")
    public static let grabIdle = PointerStyle(css: "grab")
    public static let grabActive = PointerStyle(css: "grabbing")
    public static let horizontalText = PointerStyle(css: "text")
    public static let verticalText = PointerStyle(css: "vertical-text")
    public static let rectSelection = PointerStyle(css: "crosshair")
    public static let zoomIn = PointerStyle(css: "zoom-in")
    public static let zoomOut = PointerStyle(css: "zoom-out")

    public static func columnResize(directions: HorizontalDirection.Set = .all) -> PointerStyle {
        PointerStyle(css: directions == .leading ? "w-resize" : directions == .trailing ? "e-resize" : "col-resize")
    }

    public static func rowResize(directions: VerticalDirection.Set = .all) -> PointerStyle {
        PointerStyle(css: directions == .up ? "n-resize" : directions == .down ? "s-resize" : "row-resize")
    }

    public static func frameResize(position: FrameResizePosition, directions: FrameResizeDirection.Set = .all) -> PointerStyle {
        switch position {
        case .top, .bottom: return PointerStyle(css: "ns-resize")
        case .leading, .trailing: return PointerStyle(css: "ew-resize")
        case .topLeading, .bottomTrailing: return PointerStyle(css: "nwse-resize")
        case .topTrailing, .bottomLeading: return PointerStyle(css: "nesw-resize")
        }
    }
}

public enum HorizontalDirection: Int8, CaseIterable, Sendable {
    case leading, trailing

    public struct Set: OptionSet, Sendable {
        public let rawValue: Int8
        public init(rawValue: Int8) { self.rawValue = rawValue }
        public static let leading = Set(rawValue: 1 << 0)
        public static let trailing = Set(rawValue: 1 << 1)
        public static let all: Set = [.leading, .trailing]
    }
}

public enum VerticalDirection: Int8, CaseIterable, Sendable {
    case up, down

    public struct Set: OptionSet, Sendable {
        public let rawValue: Int8
        public init(rawValue: Int8) { self.rawValue = rawValue }
        public static let up = Set(rawValue: 1 << 0)
        public static let down = Set(rawValue: 1 << 1)
        public static let all: Set = [.up, .down]
    }
}

public enum FrameResizePosition: Int8, CaseIterable, Sendable {
    case top, leading, bottom, trailing, topLeading, topTrailing, bottomLeading, bottomTrailing
}

public enum FrameResizeDirection: Int8, CaseIterable, Sendable {
    case inward, outward

    public struct Set: OptionSet, Sendable {
        public let rawValue: Int8
        public init(rawValue: Int8) { self.rawValue = rawValue }
        public static let inward = Set(rawValue: 1 << 0)
        public static let outward = Set(rawValue: 1 << 1)
        public static let all: Set = [.inward, .outward]
    }
}

/// `onHover`: the action hears when the pointer enters or leaves the content.
public struct _HoverModifier {
    package let action: @MainActor (Bool) -> Void
    public init(action: @escaping @MainActor (Bool) -> Void) { self.action = action }
}

extension _HoverModifier: ViewModifier {
    public typealias Body = Never

    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        HoverNode(context)
    }
}

/// `onContinuousHover`: the action follows the pointer over the content.
public struct _ContinuousHoverModifier {
    package let coordinateSpace: CoordinateSpace
    package let action: @MainActor (HoverPhase) -> Void
    public init(coordinateSpace: CoordinateSpace, action: @escaping @MainActor (HoverPhase) -> Void) {
        self.coordinateSpace = coordinateSpace
        self.action = action
    }
}

extension _ContinuousHoverModifier: ViewModifier {
    public typealias Body = Never

    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        ContinuousHoverNode(context)
    }
}

/// `help`: a tooltip after the pointer rests on the content.
@frozen
public struct _HelpModifier: Equatable {
    public var text: String
    public init(text: String) { self.text = text }
}

extension _HelpModifier: ViewModifier {
    public typealias Body = Never

    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        HelpNode(context)
    }
}

/// `pointerStyle`: the pointer's look over the content.
@frozen
public struct _PointerStyleModifier: Equatable {
    public var style: PointerStyle?
    public init(style: PointerStyle?) { self.style = style }
}

extension _PointerStyleModifier: ViewModifier {
    public typealias Body = Never

    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        PointerStyleNode(context)
    }
}

extension View {
    /// Calls `action` with `true` when the pointer enters this view's frame and `false` when it
    /// leaves (or leaves the window).
    nonisolated public func onHover(perform action: @escaping @MainActor (Bool) -> Void) -> some View {
        modifier(_HoverModifier(action: action))
    }

    /// Calls `action` with the pointer's location while it is over this view (in the view's
    /// own space, or the window's for `.global`), then with `.ended`.
    nonisolated public func onContinuousHover(coordinateSpace: CoordinateSpace = .local, perform action: @escaping @MainActor (HoverPhase) -> Void) -> some View {
        modifier(_ContinuousHoverModifier(coordinateSpace: coordinateSpace, action: action))
    }

    /// Calls `action` while the pointer is over this view, in the given coordinate space.
    nonisolated public func onContinuousHover(coordinateSpace: some CoordinateSpaceProtocol, perform action: @escaping @MainActor (HoverPhase) -> Void) -> some View {
        modifier(_ContinuousHoverModifier(coordinateSpace: coordinateSpace.coordinateSpace, action: action))
    }

    /// Shows `text` as a tooltip when the pointer rests on this view.
    nonisolated public func help(_ text: Text) -> some View {
        modifier(_HelpModifier(text: text._plainString))
    }

    /// Shows the string as a tooltip when the pointer rests on this view.
    nonisolated public func help(_ textKey: LocalizedStringKey) -> some View {
        modifier(_HelpModifier(text: Text(textKey)._plainString))
    }

    /// Shows the string as a tooltip when the pointer rests on this view.
    nonisolated public func help<S: StringProtocol>(_ text: S) -> some View {
        modifier(_HelpModifier(text: String(text)))
    }

    /// Sets the pointer's appearance while it is over this view (`nil` restores the default).
    nonisolated public func pointerStyle(_ style: PointerStyle?) -> some View {
        modifier(_PointerStyleModifier(style: style))
    }
}
