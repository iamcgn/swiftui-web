// The environment values SwiftUI shares with the platform's trait collection: the dynamic type
// size, the layout direction and the size classes (Docs/elements/Representable.md, `traits`).
// The runtime reads none of them for its own layout yet (Docs/todo.json: sw-dynamic-type,
// sw-rtl); a hosted UIKit view sees them as its traits.

/// A Dynamic Type size, which specifies how large scalable content should be.
public enum DynamicTypeSize: Int, Hashable, Comparable, CaseIterable, Sendable {
    case xSmall, small, medium, large, xLarge, xxLarge, xxxLarge
    case accessibility1, accessibility2, accessibility3, accessibility4, accessibility5

    /// Whether the size is one of the accessibility sizes.
    public var isAccessibilitySize: Bool { self >= .accessibility1 }

    public static func < (lhs: DynamicTypeSize, rhs: DynamicTypeSize) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// A set of values that indicate the visual size available to the view.
public enum UserInterfaceSizeClass: Hashable, Sendable {
    case compact, regular
}

package struct DynamicTypeSizeKey: EnvironmentKey {
    package static let defaultValue = DynamicTypeSize.large
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
