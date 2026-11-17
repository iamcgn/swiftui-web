// The environment values an iOS app reads for system settings and presentation state that a web
// page has no source for (VoiceOver, Switch Control, button shapes, Always On, screen capture),
// with the values an iPhone reports when those settings are off, and the styling values the
// matching modifiers set (`badgeProminence`, `buttonRepeatBehavior`, `menuOrder` and the rest),
// which views here store but draw the standard way.
#if os(WASI)
import WebFoundation   // never full Foundation on wasm: it links ICU (decisions 0006, 0017)
#else
import Foundation
#endif

/// The font weight the system prefers for legibility (the Bold Text setting).
public enum LegibilityWeight: Hashable, Sendable {
    case regular
    case bold
}

/// The prominence of the background beneath a view.
public struct BackgroundProminence: Hashable, Sendable {
    let level: Int
    /// The standard prominence, the one views see unless a selected row or the like raises it.
    public static let standard = BackgroundProminence(level: 0)
    /// A raised background, such as a selected list row's.
    public static let increased = BackgroundProminence(level: 1)
}

/// How prominently a badge shows.
public struct BadgeProminence: Hashable, Sendable {
    let level: Int
    public static let decreased = BadgeProminence(level: -1)
    public static let standard = BadgeProminence(level: 0)
    public static let increased = BadgeProminence(level: 1)
}

/// Whether a button repeats its action while it is held.
public struct ButtonRepeatBehavior: Hashable, Sendable {
    let kind: Int
    public static let automatic = ButtonRepeatBehavior(kind: 0)
    public static let enabled = ButtonRepeatBehavior(kind: 1)
    public static let disabled = ButtonRepeatBehavior(kind: 2)
}

/// Whether a view activates when a drag hovers over it.
public struct SpringLoadingBehavior: Hashable, Sendable {
    let kind: Int
    public static let automatic = SpringLoadingBehavior(kind: 0)
    public static let enabled = SpringLoadingBehavior(kind: 1)
    public static let disabled = SpringLoadingBehavior(kind: 2)
}

extension Image {
    /// The dynamic range an image may show in: a browser canvas shows standard range.
    public struct DynamicRange: Hashable, Sendable {
        let kind: Int
        /// Standard dynamic range.
        public static let standard = DynamicRange(kind: 0)
        /// High dynamic range held back to sit beside standard content.
        public static let constrainedHigh = DynamicRange(kind: 1)
        /// The full high dynamic range the display offers.
        public static let high = DynamicRange(kind: 2)
    }

    /// Sets the dynamic range the image may show in (recorded; images show in standard range).
    public func allowedDynamicRange(_ range: DynamicRange?) -> Image { self }
}

package struct LegibilityWeightKey: EnvironmentKey { package static let defaultValue: LegibilityWeight? = .regular }
package struct BackgroundProminenceKey: EnvironmentKey { package static let defaultValue = BackgroundProminence.standard }
package struct BadgeProminenceKey: EnvironmentKey { package static let defaultValue = BadgeProminence.standard }
package struct ButtonRepeatBehaviorKey: EnvironmentKey { package static let defaultValue = ButtonRepeatBehavior.automatic }
package struct SpringLoadingBehaviorKey: EnvironmentKey { package static let defaultValue = SpringLoadingBehavior.automatic }
package struct AllowedDynamicRangeKey: EnvironmentKey { package static let defaultValue: Image.DynamicRange? = nil }
package struct MenuOrderKey: EnvironmentKey { package static let defaultValue = MenuOrder.automatic }
package struct LabelsVisibilityKey: EnvironmentKey { package static let defaultValue = Visibility.automatic }
package struct BackgroundMaterialKey: EnvironmentKey { package static let defaultValue: Material? = nil }
package struct DefaultMinListHeaderHeightKey: EnvironmentKey { package static let defaultValue: CGFloat? = nil }
package struct ContentTransitionAddsDrawingGroupKey: EnvironmentKey { package static let defaultValue = false }
package struct IsLuminanceReducedKey: EnvironmentKey { package static let defaultValue = false }
package struct IsSceneCapturedKey: EnvironmentKey { package static let defaultValue = false }
package struct AppearsActiveKey: EnvironmentKey { package static let defaultValue = true }
package struct VoiceOverEnabledKey: EnvironmentKey { package static let defaultValue = false }
package struct SwitchControlEnabledKey: EnvironmentKey { package static let defaultValue = false }
package struct ShowButtonShapesKey: EnvironmentKey { package static let defaultValue = false }
package struct DimFlashingLightsKey: EnvironmentKey { package static let defaultValue = false }
package struct PlayAnimatedImagesKey: EnvironmentKey { package static let defaultValue = true }
package struct LargeContentViewerEnabledKey: EnvironmentKey { package static let defaultValue = false }
package struct AssistiveAccessEnabledKey: EnvironmentKey { package static let defaultValue = false }

extension EnvironmentValues {
    /// The weight the system prefers for legibility: regular, as with Bold Text off.
    public var legibilityWeight: LegibilityWeight? {
        get { self[LegibilityWeightKey.self] }
        set { self[LegibilityWeightKey.self] = newValue }
    }
    /// The size of one display pixel in points.
    public var pixelLength: CGFloat { 1 / displayScale }
    /// The prominence of the background beneath the view.
    public var backgroundProminence: BackgroundProminence {
        get { self[BackgroundProminenceKey.self] }
        set { self[BackgroundProminenceKey.self] = newValue }
    }
    /// How prominently badges in the view show (`badgeProminence(_:)`).
    public var badgeProminence: BadgeProminence {
        get { self[BadgeProminenceKey.self] }
        set { self[BadgeProminenceKey.self] = newValue }
    }
    /// Whether buttons in the view repeat while held (`buttonRepeatBehavior(_:)`).
    public var buttonRepeatBehavior: ButtonRepeatBehavior {
        get { self[ButtonRepeatBehaviorKey.self] }
        set { self[ButtonRepeatBehaviorKey.self] = newValue }
    }
    /// Whether views activate when a drag hovers over them (`springLoadingBehavior(_:)`).
    public var springLoadingBehavior: SpringLoadingBehavior {
        get { self[SpringLoadingBehaviorKey.self] }
        set { self[SpringLoadingBehaviorKey.self] = newValue }
    }
    /// The dynamic range images in the view may show in (`allowedDynamicRange(_:)`).
    public var allowedDynamicRange: Image.DynamicRange? {
        get { self[AllowedDynamicRangeKey.self] }
        set { self[AllowedDynamicRangeKey.self] = newValue }
    }
    /// The order menus in the view present their items in (`menuOrder(_:)`).
    public var menuOrder: MenuOrder {
        get { self[MenuOrderKey.self] }
        set { self[MenuOrderKey.self] = newValue }
    }
    /// Whether menus in the view show their indicator (`menuIndicator(_:)`).
    public var menuIndicatorVisibility: Visibility {
        get { _menuIndicator }
        set { _menuIndicator = newValue }
    }
    /// The prominence of section headers in the view (`headerProminence(_:)`).
    public var headerProminence: Prominence {
        get { _headerProminence }
        set { _headerProminence = newValue }
    }
    /// Whether labels in the view show their titles (`labelsVisibility(_:)`).
    public var labelsVisibility: Visibility {
        get { self[LabelsVisibilityKey.self] }
        set { self[LabelsVisibilityKey.self] = newValue }
    }
    /// The material beneath the view, when a container sets one.
    public var backgroundMaterial: Material? {
        get { self[BackgroundMaterialKey.self] }
        set { self[BackgroundMaterialKey.self] = newValue }
    }
    /// The least height of a list's section headers, when an app sets one.
    public var defaultMinListHeaderHeight: CGFloat? {
        get { self[DefaultMinListHeaderHeightKey.self] }
        set { self[DefaultMinListHeaderHeightKey.self] = newValue }
    }
    /// Whether content transitions draw in a drawing group.
    public var contentTransitionAddsDrawingGroup: Bool {
        get { self[ContentTransitionAddsDrawingGroupKey.self] }
        set { self[ContentTransitionAddsDrawingGroupKey.self] = newValue }
    }
    /// Whether the display is dimmed for Always On (never in a browser).
    public var isLuminanceReduced: Bool {
        get { self[IsLuminanceReducedKey.self] }
        set { self[IsLuminanceReducedKey.self] = newValue }
    }
    /// Whether the scene is being recorded or mirrored (a page cannot tell).
    public var isSceneCaptured: Bool {
        get { self[IsSceneCapturedKey.self] }
        set { self[IsSceneCapturedKey.self] = newValue }
    }
    /// Whether the view's window is active.
    public var appearsActive: Bool {
        get { self[AppearsActiveKey.self] }
        set { self[AppearsActiveKey.self] = newValue }
    }
    /// Whether VoiceOver is running (a page cannot tell, so false).
    public var accessibilityVoiceOverEnabled: Bool {
        get { self[VoiceOverEnabledKey.self] }
        set { self[VoiceOverEnabledKey.self] = newValue }
    }
    /// Whether Switch Control is running (a page cannot tell, so false).
    public var accessibilitySwitchControlEnabled: Bool {
        get { self[SwitchControlEnabledKey.self] }
        set { self[SwitchControlEnabledKey.self] = newValue }
    }
    /// Whether the system shows button shapes (no browser reports it, so false).
    public var accessibilityShowButtonShapes: Bool {
        get { self[ShowButtonShapesKey.self] }
        set { self[ShowButtonShapesKey.self] = newValue }
    }
    /// Whether the system dims flashing lights in video (no browser reports it, so false).
    public var accessibilityDimFlashingLights: Bool {
        get { self[DimFlashingLightsKey.self] }
        set { self[DimFlashingLightsKey.self] = newValue }
    }
    /// Whether animated images play (true, as on an iPhone with the setting on).
    public var accessibilityPlayAnimatedImages: Bool {
        get { self[PlayAnimatedImagesKey.self] }
        set { self[PlayAnimatedImagesKey.self] = newValue }
    }
    /// Whether the large content viewer is on (false: it follows accessibility text sizes on iOS).
    public var accessibilityLargeContentViewerEnabled: Bool {
        get { self[LargeContentViewerEnabledKey.self] }
        set { self[LargeContentViewerEnabledKey.self] = newValue }
    }
    /// Whether Assistive Access is running (false).
    public var accessibilityAssistiveAccessEnabled: Bool {
        get { self[AssistiveAccessEnabledKey.self] }
        set { self[AssistiveAccessEnabledKey.self] = newValue }
    }
}

extension View {
    /// Sets how prominently badges in this view show (recorded; badges draw at standard prominence).
    nonisolated public func badgeProminence(_ prominence: BadgeProminence) -> some View {
        environment(\.badgeProminence, prominence)
    }
    /// Sets whether buttons in this view repeat while held (recorded; a held button acts once).
    nonisolated public func buttonRepeatBehavior(_ behavior: ButtonRepeatBehavior) -> some View {
        environment(\.buttonRepeatBehavior, behavior)
    }
    /// Sets whether this view activates when a drag hovers over it (recorded).
    nonisolated public func springLoadingBehavior(_ behavior: SpringLoadingBehavior) -> some View {
        environment(\.springLoadingBehavior, behavior)
    }
    /// Sets the dynamic range images in this view may show in (recorded; images show standard range).
    nonisolated public func allowedDynamicRange(_ range: Image.DynamicRange?) -> some View {
        environment(\.allowedDynamicRange, range)
    }
    /// Sets whether labels in this view show their titles (recorded).
    nonisolated public func labelsVisibility(_ visibility: Visibility) -> some View {
        environment(\.labelsVisibility, visibility)
    }
}
