// Presentation and bar modifiers of iOS 18-26 that apps put on their views: the zoom navigation
// transition and its source, a sheet's sizing, the tab bar's minimizing on scroll, the bar a
// view shows in its safe area, the focus effect, and a view's visibility in its scroll view.
// The runtime's pushes slide and its sheets keep their platform size, so the transition and
// sizing values are accepted and kept on the view; `safeAreaBar` insets the safe area as
// `safeAreaInset` does, and `onScrollVisibilityChange` follows the view's frame in its scroll
// view after each layout pass.
import WebFoundation

// MARK: - Navigation transitions

/// A style for the transition of a pushed or presented view.
public protocol NavigationTransition {}

/// The default transition: the platform's slide for a push, rise for a sheet.
public struct AutomaticNavigationTransition: NavigationTransition, Sendable {
    public init() {}
}

/// A transition that zooms the presented view from a matched source view.
public struct ZoomNavigationTransition: NavigationTransition {
    /// The source's identity among the namespace's `matchedTransitionSource` views.
    public let sourceID: AnyHashable
    public let namespace: Namespace.ID
}

extension NavigationTransition where Self == AutomaticNavigationTransition {
    /// The default transition.
    public static var automatic: AutomaticNavigationTransition { AutomaticNavigationTransition() }
}

extension NavigationTransition where Self == ZoomNavigationTransition {
    /// Zooms the presented view from the `matchedTransitionSource` with `sourceID` in `namespace`.
    public static func zoom(sourceID: some Hashable, in namespace: Namespace.ID) -> ZoomNavigationTransition {
        ZoomNavigationTransition(sourceID: AnyHashable(sourceID), namespace: namespace)
    }
}

/// How a matched transition source looks while the transition runs.
public protocol MatchedTransitionSourceConfiguration {}

/// The source's own look, before any configuration.
public struct EmptyMatchedTransitionSourceConfiguration: MatchedTransitionSourceConfiguration, Sendable {
    public init() {}
}

extension MatchedTransitionSourceConfiguration {
    /// The background the source shows during the transition.
    public func background(_ style: Color) -> EmptyMatchedTransitionSourceConfiguration { EmptyMatchedTransitionSourceConfiguration() }
    /// The shape the source is clipped to during the transition.
    public func clipShape(_ shape: some Shape) -> EmptyMatchedTransitionSourceConfiguration { EmptyMatchedTransitionSourceConfiguration() }
    /// The shadow the source casts during the transition.
    public func shadow(color: Color? = nil, radius: CGFloat,
                       x: CGFloat = 0, y: CGFloat = 0) -> EmptyMatchedTransitionSourceConfiguration { EmptyMatchedTransitionSourceConfiguration() }
}

extension View {
    /// Sets the transition of this view when it is pushed or presented.
    nonisolated public func navigationTransition(_ style: some NavigationTransition) -> some View { self }

    /// Identifies this view as the source of a zoom transition with `id` in `namespace`.
    nonisolated public func matchedTransitionSource(id: some Hashable, in namespace: Namespace.ID) -> some View { self }

    /// Identifies this view as the source of a zoom transition, styled by `configuration`.
    nonisolated public func matchedTransitionSource<C: MatchedTransitionSourceConfiguration>(
        id: some Hashable, in namespace: Namespace.ID,
        configuration: (EmptyMatchedTransitionSourceConfiguration) -> C
    ) -> some View { self }
}

// MARK: - Presentation sizing

/// How a sheet sizes itself where the platform lets it choose (iPad, Mac, visionOS).
public protocol PresentationSizing {}

/// The platform's default size for the content.
public struct AutomaticPresentationSizing: PresentationSizing, Sendable { public init() {} }
/// A size like a page of paper: the platform's larger sheet.
public struct PagePresentationSizing: PresentationSizing, Sendable { public init() {} }
/// A size for a form: the platform's smaller sheet.
public struct FormPresentationSizing: PresentationSizing, Sendable { public init() {} }
/// The content's own ideal size.
public struct FittedPresentationSizing: PresentationSizing, Sendable {
    public let horizontal: Bool
    public let vertical: Bool
    public init(horizontal: Bool = true, vertical: Bool = true) {
        self.horizontal = horizontal
        self.vertical = vertical
    }
}

extension PresentationSizing where Self == AutomaticPresentationSizing {
    public static var automatic: AutomaticPresentationSizing { AutomaticPresentationSizing() }
}

extension PresentationSizing where Self == PagePresentationSizing {
    public static var page: PagePresentationSizing { PagePresentationSizing() }
}

extension PresentationSizing where Self == FormPresentationSizing {
    public static var form: FormPresentationSizing { FormPresentationSizing() }
}

extension PresentationSizing where Self == FittedPresentationSizing {
    public static var fitted: FittedPresentationSizing { FittedPresentationSizing() }
}

extension PresentationSizing {
    /// Fits the content's ideal size along the given dimensions only.
    public func fitted(horizontal: Bool, vertical: Bool) -> FittedPresentationSizing {
        FittedPresentationSizing(horizontal: horizontal, vertical: vertical)
    }
    /// Lets the sheet grow along the dimensions, but not shrink below its first size.
    public func sticky(horizontal: Bool = false, vertical: Bool = false) -> Self { self }
}

extension View {
    /// Sets the sizing of the enclosing presentation. The runtime's sheets keep the platform's
    /// size on iPhone, which every sizing gives there.
    nonisolated public func presentationSizing(_ sizing: some PresentationSizing) -> some View { self }
}

// MARK: - Tab bar and safe area bars

/// Whether the tab bar minimizes when the content scrolls.
public struct TabBarMinimizeBehavior: Hashable, Sendable {
    package let tag: UInt8
    /// The platform's default: the bar stays.
    public static let automatic = TabBarMinimizeBehavior(tag: 0)
    /// The bar minimizes when the content scrolls down, and returns when it scrolls up.
    public static let onScrollDown = TabBarMinimizeBehavior(tag: 1)
    /// The bar minimizes when the content scrolls up.
    public static let onScrollUp = TabBarMinimizeBehavior(tag: 2)
    /// The bar never minimizes.
    public static let never = TabBarMinimizeBehavior(tag: 3)
}

extension View {
    /// Sets whether the tab bar of the enclosing tab view minimizes on scroll. The runtime's
    /// tab bar stays, which `automatic` and `never` both give.
    nonisolated public func tabBarMinimizeBehavior(_ behavior: TabBarMinimizeBehavior) -> some View { self }

    /// Shows `content` along the vertical edge as a bar in the safe area, insetting this view's
    /// safe area by its height.
    nonisolated public func safeAreaBar<V: View>(edge: VerticalEdge, alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil,
                                                 @ViewBuilder content: () -> V) -> some View {
        safeAreaInset(edge: edge, alignment: alignment, spacing: spacing, content: content)
    }

    /// Shows `content` along the horizontal edge as a bar in the safe area, insetting this
    /// view's safe area by its width.
    nonisolated public func safeAreaBar<V: View>(edge: HorizontalEdge, alignment: VerticalAlignment = .center, spacing: CGFloat? = nil,
                                                 @ViewBuilder content: () -> V) -> some View {
        safeAreaInset(edge: edge, alignment: alignment, spacing: spacing, content: content)
    }

    /// Turns off the platform's focus effect for this view. The runtime draws no focus effect
    /// on its views, so there is nothing to turn off.
    nonisolated public func focusEffectDisabled(_ disabled: Bool = true) -> some View { self }

    /// Sets the capitalization of text input in this view.
    @available(*, deprecated, renamed: "textInputAutocapitalization(_:)")
    nonisolated public func autocapitalization(_ style: UITextAutocapitalizationType) -> some View {
        textInputAutocapitalization(TextInputAutocapitalization(style))
    }
}

// MARK: - Scroll visibility

extension GeometryProxy {
    /// The share of the view's area that shows in its nearest scroll view (the window when it
    /// is in none), from 0 to 1.
    nonisolated package var _visibleFraction: Double {
        let node = self.node
        return MainActor.assumeIsolated { Self._visibleFraction(of: node) }
    }

    @MainActor
    private static func _visibleFraction(of node: ViewNode) -> Double {
        let mine = node.frameInRoot
        var viewport = CGRect(origin: .zero, size: node.runtime.layoutSize)
        var ancestor = node.parent
        while let current = ancestor {
            if let scroll = current as? any _ScrollViewport {
                viewport = scroll.frameInRoot
                break
            }
            ancestor = current.parent
        }
        let shown = mine.intersection(viewport)
        guard !shown.isNull, !shown.isEmpty || mine.isEmpty else { return 0 }
        let area = mine.width * mine.height
        guard area > 0 else { return viewport.contains(mine.origin) ? 1 : 0 }
        return Double(shown.width * shown.height / area)
    }
}

extension View {
    /// Runs `action` when the view's visibility in its scroll view crosses `threshold` (the
    /// share of its area that must show): true when it comes into view, false when it leaves.
    /// A view that is visible when it appears reports true then.
    nonisolated public func onScrollVisibilityChange(threshold: Double = 0.5, _ action: @escaping (_ isVisible: Bool) -> Void) -> some View {
        onGeometryChange(for: Bool.self, of: { proxy in proxy._visibleFraction >= max(threshold, 0.000_001) }) { old, new in
            if old != new || new { action(new) }
        }
    }
}
