// The environment values SwiftUI shares with the platform's trait collection: the dynamic type
// size, the layout direction and the size classes (Docs/elements/Representable.md, `traits`).
// The iOS profile's text styles and `@ScaledMetric` follow the dynamic type size (sw-dynamic-type,
// Docs/elements/Text.md), every container mirrors under a right-to-left direction (sw-rtl), and a
// hosted UIKit view sees them all as its traits.

/// A Dynamic Type size, which specifies how large scalable content should be.
public enum DynamicTypeSize: Int, Hashable, Comparable, CaseIterable, Sendable {
    case xSmall, small, medium, large, xLarge, xxLarge, xxxLarge
    case accessibility1, accessibility2, accessibility3, accessibility4, accessibility5

    /// Whether the size is one of the accessibility sizes.
    public var isAccessibilitySize: Bool { self >= .accessibility1 }

    public static func < (lhs: DynamicTypeSize, rhs: DynamicTypeSize) -> Bool { lhs.rawValue < rhs.rawValue }

    /// UIKit's short name for the content size category, the key of the measured tables
    /// (`SystemFontMetricsTables.iOSDynamicTypeSizes`, the recorded metrics' `style:body:XXXL`).
    package var _categoryName: String {
        switch self {
        case .xSmall: return "XS"
        case .small: return "S"
        case .medium: return "M"
        case .large: return "L"
        case .xLarge: return "XL"
        case .xxLarge: return "XXL"
        case .xxxLarge: return "XXXL"
        case .accessibility1: return "AXM"
        case .accessibility2: return "AXL"
        case .accessibility3: return "AXXL"
        case .accessibility4: return "AXXXL"
        case .accessibility5: return "AXXXXL"
        }
    }

    /// The size for one of UIKit's short names.
    package init?(_categoryName name: String) {
        guard let size = DynamicTypeSize.allCases.first(where: { $0._categoryName == name }) else { return nil }
        self = size
    }
}

/// A dynamic property that scales a numeric value with the Dynamic Type size, relative to a text
/// style: the value times the ratio of the style's line height at the size to its line height at
/// `.large`, rounded to the display scale (measured on `ios/text/dynamic-*`). On macOS, which has
/// no Dynamic Type, the value is returned as it is (`text/dynamic-type`).
@propertyWrapper
public struct ScaledMetric<Value: BinaryFloatingPoint>: DynamicProperty {
    private let base: Value
    private let textStyle: Font.TextStyle
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.platformProfile) private var platformProfile
    @Environment(\.displayScale) private var displayScale

    public init(wrappedValue: Value, relativeTo textStyle: Font.TextStyle) {
        base = wrappedValue
        self.textStyle = textStyle
    }

    public init(wrappedValue: Value) {
        self.init(wrappedValue: wrappedValue, relativeTo: .body)
    }

    public var wrappedValue: Value {
        let ratio = platformProfile._dynamicTypeScale(for: textStyle, size: dynamicTypeSize)
        guard ratio != 1 else { return base }
        let scale = Value(displayScale > 0 ? displayScale : 1)
        return (base * Value(ratio) * scale).rounded() / scale
    }
}

extension PlatformProfile {
    /// The factor `@ScaledMetric` scales by for a text style at a Dynamic Type size: the ratio of
    /// the style's line heights (ascender − descender + leading) at the size and at `.large` in
    /// the iOS profile; 1 on macOS.
    package func _dynamicTypeScale(for style: Font.TextStyle, size: DynamicTypeSize) -> CGFloat {
        guard isIOS, size != .large, let table = SystemFontMetricsTables.iOSDynamicTypeSizes[style],
              let scaled = table[size._categoryName], let large = table["L"], large.lineHeight > 0 else { return 1 }
        return scaled.lineHeight / large.lineHeight
    }

    /// The point size of a text style at a Dynamic Type size in the iOS profile (the HIG table,
    /// measured on the simulator); the profile's size elsewhere.
    package func _dynamicTypePointSize(for style: Font.TextStyle, size: DynamicTypeSize) -> CGFloat? {
        guard isIOS, size != .large, let table = SystemFontMetricsTables.iOSDynamicTypeSizes[style],
              let scaled = table[size._categoryName] else { return nil }
        return scaled.pointSize
    }
}

/// A set of values that indicate the visual size available to the view.
public enum UserInterfaceSizeClass: Hashable, Sendable {
    case compact, regular
}

package struct DynamicTypeSizeKey: EnvironmentKey {
    package static let defaultValue = DynamicTypeSize.large
}

package struct DisplayScaleKey: EnvironmentKey {
    /// Two pixels per point: the goldens' scale; hosts set theirs (`Runtime.hostDisplayScale`).
    package static let defaultValue: CGFloat = 2
}

extension EnvironmentValues {
    /// The display's pixels per point.
    public var displayScale: CGFloat {
        get { self[DisplayScaleKey.self] }
        set { self[DisplayScaleKey.self] = newValue }
    }
}

package struct LayoutDirectionKey: EnvironmentKey {
    package static let defaultValue = LayoutDirection.leftToRight
}

package struct HorizontalSizeClassKey: EnvironmentKey {
    package static let defaultValue: UserInterfaceSizeClass? = nil
}

package struct VerticalSizeClassKey: EnvironmentKey {
    package static let defaultValue: UserInterfaceSizeClass? = nil
}

extension EnvironmentValues {
    /// The current Dynamic Type size (the host's setting is not read yet: `.large`).
    public var dynamicTypeSize: DynamicTypeSize {
        get { self[DynamicTypeSizeKey.self] }
        set { self[DynamicTypeSizeKey.self] = newValue }
    }

    /// The layout direction associated with the current environment.
    public var layoutDirection: LayoutDirection {
        get { self[LayoutDirectionKey.self] }
        set { self[LayoutDirectionKey.self] = newValue }
    }

    /// The horizontal size class of this environment: compact on the iOS profile (every iOS
    /// fixture is an iPhone screen), nil on macOS, unless set.
    public var horizontalSizeClass: UserInterfaceSizeClass? {
        get { self[HorizontalSizeClassKey.self] ?? (platformProfile.isIOS ? .compact : nil) }
        set { self[HorizontalSizeClassKey.self] = newValue }
    }

    /// The vertical size class of this environment: regular on the iOS profile, nil on macOS,
    /// unless set.
    public var verticalSizeClass: UserInterfaceSizeClass? {
        get { self[VerticalSizeClassKey.self] ?? (platformProfile.isIOS ? .regular : nil) }
        set { self[VerticalSizeClassKey.self] = newValue }
    }
}

extension View {
    /// Sets the Dynamic Type size within the view to the given value.
    nonisolated public func dynamicTypeSize(_ size: DynamicTypeSize) -> some View {
        environment(\.dynamicTypeSize, size)
    }

    /// Limits the Dynamic Type size within the view to the given range.
    nonisolated public func dynamicTypeSize<T: RangeExpression>(_ range: T) -> some View where T.Bound == DynamicTypeSize {
        transformEnvironment(\.dynamicTypeSize) { size in
            guard !range.contains(size) else { return }
            let allowed = DynamicTypeSize.allCases.filter { range.contains($0) }
            if let first = allowed.first, size < first { size = first }
            if let last = allowed.last, size > last { size = last }
        }
    }
}
