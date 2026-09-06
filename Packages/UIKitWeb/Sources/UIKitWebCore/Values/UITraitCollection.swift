// Trait collections: the appearance and size classes a view resolves its colours against.

/// The light or dark appearance.
public enum UIUserInterfaceStyle: Int, Sendable {
    case unspecified = 0, light = 1, dark = 2
}

/// The horizontal or vertical size class.
public enum UIUserInterfaceSizeClass: Int, Sendable {
    case unspecified = 0, compact = 1, regular = 2
}

/// The device idiom.
public enum UIUserInterfaceIdiom: Int, Sendable {
    case unspecified = -1, phone = 0, pad = 1, tv = 2, carPlay = 3, mac = 5, vision = 6
}

/// The layout direction.
public enum UITraitEnvironmentLayoutDirection: Int, Sendable {
    case unspecified = -1, leftToRight = 0, rightToLeft = 1
}

/// The traits a view resolves against.
public struct UITraitCollection: Hashable, Sendable {
    public var userInterfaceStyle: UIUserInterfaceStyle = .light
    public var horizontalSizeClass: UIUserInterfaceSizeClass = .regular
    public var verticalSizeClass: UIUserInterfaceSizeClass = .regular
    public var userInterfaceIdiom: UIUserInterfaceIdiom = .pad
    public var displayScale: CGFloat = 2
    public var layoutDirection: UITraitEnvironmentLayoutDirection = .leftToRight

    public init() {}

    public init(userInterfaceStyle: UIUserInterfaceStyle) {
        self.userInterfaceStyle = userInterfaceStyle
    }

    public init(horizontalSizeClass: UIUserInterfaceSizeClass) {
        self.horizontalSizeClass = horizontalSizeClass
    }

    public init(verticalSizeClass: UIUserInterfaceSizeClass) {
        self.verticalSizeClass = verticalSizeClass
    }

    public init(displayScale: CGFloat) {
        self.displayScale = displayScale
    }

    public init(traitsFrom traits: [UITraitCollection]) {
        var result = UITraitCollection()
        for t in traits {
            if t.userInterfaceStyle != .unspecified { result.userInterfaceStyle = t.userInterfaceStyle }
            if t.horizontalSizeClass != .unspecified { result.horizontalSizeClass = t.horizontalSizeClass }
            if t.verticalSizeClass != .unspecified { result.verticalSizeClass = t.verticalSizeClass }
        }
        self = result
    }

    /// The current traits, as UIKit exposes them while resolving dynamic values.
    public static var current: UITraitCollection {
        get { _current }
        set { _current = newValue }
    }
    nonisolated(unsafe) private static var _current = UITraitCollection()

    /// Whether the appearance differs between two collections (`traitCollectionDidChange`).
    public func hasDifferentColorAppearance(comparedTo other: UITraitCollection?) -> Bool {
        userInterfaceStyle != other?.userInterfaceStyle
    }

    /// Runs `body` with these traits current.
    public func performAsCurrent(_ body: () -> Void) {
        let previous = Self._current
        Self._current = self
        body()
        Self._current = previous
    }
}

/// An object that carries a trait collection.
@MainActor
public protocol UITraitEnvironment: AnyObject {
    var traitCollection: UITraitCollection { get }
    func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?)
}
