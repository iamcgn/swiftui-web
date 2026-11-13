// The views that show tips: `TipView` inline, `popoverTip` in a popover, and the styles and
// appearance modifiers around them. A tip shows while its status is available; its close button
// invalidates it (`tipClosed`), and an action button calls the view's action handler.
import WebFoundation
import SwiftUI

/// What a tip view style draws: the tip and the handler of its actions.
public struct TipViewStyleConfiguration {
    public let tip: any Tip
    let actionHandler: (Tips.Action) -> Void
    let arrowEdge: Edge?

    /// Runs the action: its own closure, then the view's handler.
    public func perform(_ action: Tips.Action) {
        action.handler()
        actionHandler(action)
    }
}

/// How a `TipView` draws its tip.
@MainActor @preconcurrency
public protocol TipViewStyle {
    associatedtype Body: View
    typealias Configuration = TipViewStyleConfiguration
    @ViewBuilder @MainActor func makeBody(configuration: Configuration) -> Body
}

/// The standard tip: its image, title, message, close button and actions, on a rounded panel.
public struct _DefaultTipViewStyle: TipViewStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View { _TipContent(configuration: configuration) }
}

/// The compact tip, as the standard one here.
public struct MiniTipViewStyle: TipViewStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View { _TipContent(configuration: configuration) }
}

extension TipViewStyle where Self == MiniTipViewStyle {
    public static var miniTip: MiniTipViewStyle { MiniTipViewStyle() }
}

extension TipViewStyle where Self == _DefaultTipViewStyle {
    public static var automatic: _DefaultTipViewStyle { _DefaultTipViewStyle() }
}

struct _AnyTipViewStyle {
    let make: @MainActor (TipViewStyleConfiguration) -> AnyView
}

struct _TipAppearance {
    var style: _AnyTipViewStyle?
    var background: AnyShapeStyle?
    var cornerRadius: CGFloat = 13
    var imageSize: CGSize?
    var imageStyle: AnyShapeStyle?
}

private struct _TipAppearanceKey: EnvironmentKey {
    static var defaultValue: _TipAppearance { _TipAppearance() }
}

extension EnvironmentValues {
    var _tipAppearance: _TipAppearance {
        get { self[_TipAppearanceKey.self] }
        set { self[_TipAppearanceKey.self] = newValue }
    }
}

/// A tip's image, title, message, close button and actions.
struct _TipContent: View {
    let configuration: TipViewStyleConfiguration
    @Environment(\._tipAppearance) private var appearance

    var body: some View {
        let tip = configuration.tip
        let actions = tip.actions
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                if let image = tip.image {
                    image
                        .font(.title2)
                        .foregroundStyle(appearance.imageStyle ?? AnyShapeStyle(.tint))
                        .frame(width: appearance.imageSize?.width, height: appearance.imageSize?.height)
                }
                VStack(alignment: .leading, spacing: 4) {
                    tip.title
                        .font(.headline)
                    if let message = tip.message {
                        message
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                Button {
                    tip.invalidate(reason: .tipClosed)
                } label: {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            if !actions.isEmpty {
                Divider()
                ForEach(Array(actions.enumerated()), id: \.offset) { index, action in
                    Button {
                        configuration.perform(Tips.Action(action, index: index))
                    } label: {
                        (action.title ?? Text(action.id))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                }
            }
        }
    }
}

/// Shows the tip while it may show, and counts its displays.
struct _TipPresence<Content: View>: View {
    let id: String
    let content: Content
    @State private var shownAt: Date?

    var body: some View {
        content
            .onAppear {
                shownAt = Date()
                _TipStore.shared.beginDisplay(id)
            }
            .onDisappear {
                _TipStore.shared.endDisplay(id, seconds: shownAt.map { Date().timeIntervalSince($0) } ?? 0)
                shownAt = nil
            }
    }
}

/// A tip shown inline, where the view is placed, while its status is available.
public struct TipView<Content: Tip>: View {
    let tip: Content
    let arrowEdge: Edge?
    let action: (Tips.Action) -> Void
    @Environment(\._tipAppearance) private var appearance

    public init(_ tip: Content, arrowEdge: Edge? = nil, action: @escaping (Tips.Action) -> Void = { _ in }) {
        self.tip = tip
        self.arrowEdge = arrowEdge
        self.action = action
    }

    public var body: some View {
        let _ = _TipsObserver.shared.revision
        if tip.shouldDisplay {
            let configuration = TipViewStyleConfiguration(tip: tip, actionHandler: action, arrowEdge: arrowEdge)
            _TipPresence(id: tip.id, content: Group {
                if let style = appearance.style {
                    style.make(configuration)
                } else {
                    _TipContent(configuration: configuration)
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: appearance.cornerRadius, style: .continuous)
                                .fill(appearance.background ?? AnyShapeStyle(Color(uiColor: .secondarySystemBackground)))
                        )
                }
            })
        }
    }
}

/// Presents the tip in a popover from the view while its status is available.
struct _PopoverTipModifier<T: Tip>: ViewModifier {
    let tip: T
    let arrowEdge: Edge
    let action: (Tips.Action) -> Void

    nonisolated init(tip: T, arrowEdge: Edge, action: @escaping (Tips.Action) -> Void) {
        self.tip = tip
        self.arrowEdge = arrowEdge
        self.action = action
    }

    func body(content: Content) -> some View {
        let _ = _TipsObserver.shared.revision
        let tip = tip
        content.popover(isPresented: Binding(get: { tip.shouldDisplay },
                                             set: { shown in if !shown { tip.invalidate(reason: .tipClosed) } }),
                        arrowEdge: arrowEdge) {
            _TipPresence(id: tip.id, content: _TipContent(configuration: TipViewStyleConfiguration(tip: tip, actionHandler: action, arrowEdge: arrowEdge))
                .padding(16)
                .frame(minWidth: 280, idealWidth: 320, maxWidth: 360))
                .presentationCompactAdaptation(.popover)
        }
    }
}

extension View {
    /// Presents the tip in a popover anchored to the view while its status is available.
    nonisolated public func popoverTip<Content: Tip>(_ tip: Content, arrowEdge: Edge? = nil, action: @escaping (Tips.Action) -> Void = { _ in }) -> some View {
        modifier(_PopoverTipModifier(tip: tip, arrowEdge: arrowEdge ?? .top, action: action))
    }

    /// How the tip views inside draw their tips.
    nonisolated public func tipViewStyle<S: TipViewStyle>(_ style: S) -> some View {
        nonisolated(unsafe) let style = style
        return transformEnvironment(\._tipAppearance) { appearance in
            appearance.style = _AnyTipViewStyle { configuration in AnyView(style.makeBody(configuration: configuration)) }
        }
    }

    /// The panel behind the tip views inside.
    nonisolated public func tipBackground<S: ShapeStyle>(_ style: S) -> some View {
        transformEnvironment(\._tipAppearance) { $0.background = AnyShapeStyle(style) }
    }

    /// The corner radius of the tip views' panels.
    nonisolated public func tipCornerRadius(_ cornerRadius: CGFloat, antialiased: Bool = true) -> some View {
        transformEnvironment(\._tipAppearance) { $0.cornerRadius = cornerRadius }
    }

    /// The size of the tip views' images.
    nonisolated public func tipImageSize(_ size: CGSize) -> some View {
        transformEnvironment(\._tipAppearance) { $0.imageSize = size }
    }

    /// The style of the tip views' images.
    nonisolated public func tipImageStyle<S: ShapeStyle>(_ style: S) -> some View {
        transformEnvironment(\._tipAppearance) { $0.imageStyle = AnyShapeStyle(style) }
    }
    nonisolated public func tipImageStyle<S1: ShapeStyle, S2: ShapeStyle>(_ primary: S1, _ secondary: S2) -> some View {
        transformEnvironment(\._tipAppearance) { $0.imageStyle = AnyShapeStyle(primary) }
    }
}
