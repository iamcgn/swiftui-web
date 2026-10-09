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

/// The reading direction of the interface (`effectiveUserInterfaceLayoutDirection`).
public enum UIUserInterfaceLayoutDirection: Int, Sendable {
    case leftToRight = 0, rightToLeft = 1
}

/// A Dynamic Type size, from extra small to the accessibility sizes, in UIKit's order.
public struct UIContentSizeCategory: Hashable, Sendable, RawRepresentable, Comparable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let unspecified = UIContentSizeCategory(rawValue: "_UICTContentSizeCategoryUnspecified")
    public static let extraSmall = UIContentSizeCategory(rawValue: "UICTContentSizeCategoryXS")
    public static let small = UIContentSizeCategory(rawValue: "UICTContentSizeCategoryS")
    public static let medium = UIContentSizeCategory(rawValue: "UICTContentSizeCategoryM")
    public static let large = UIContentSizeCategory(rawValue: "UICTContentSizeCategoryL")
    public static let extraLarge = UIContentSizeCategory(rawValue: "UICTContentSizeCategoryXL")
    public static let extraExtraLarge = UIContentSizeCategory(rawValue: "UICTContentSizeCategoryXXL")
    public static let extraExtraExtraLarge = UIContentSizeCategory(rawValue: "UICTContentSizeCategoryXXXL")
    public static let accessibilityMedium = UIContentSizeCategory(rawValue: "UICTContentSizeCategoryAccessibilityM")
    public static let accessibilityLarge = UIContentSizeCategory(rawValue: "UICTContentSizeCategoryAccessibilityL")
    public static let accessibilityExtraLarge = UIContentSizeCategory(rawValue: "UICTContentSizeCategoryAccessibilityXL")
    public static let accessibilityExtraExtraLarge = UIContentSizeCategory(rawValue: "UICTContentSizeCategoryAccessibilityXXL")
    public static let accessibilityExtraExtraExtraLarge = UIContentSizeCategory(rawValue: "UICTContentSizeCategoryAccessibilityXXXL")

    /// The categories from the smallest to the largest.
    public static let ordered: [UIContentSizeCategory] = [
        .extraSmall, .small, .medium, .large, .extraLarge, .extraExtraLarge, .extraExtraExtraLarge,
        .accessibilityMedium, .accessibilityLarge, .accessibilityExtraLarge, .accessibilityExtraExtraLarge, .accessibilityExtraExtraExtraLarge,
    ]

    /// Whether the category is one of the accessibility sizes.
    public var isAccessibilityCategory: Bool { (Self.ordered.firstIndex(of: self) ?? 0) >= 7 }

    /// The short names the recorded metrics use ("XS" … "AXXXXL"; the fixtures' spelling).
    static let shortNames = ["XS", "S", "M", "L", "XL", "XXL", "XXXL", "AXM", "AXL", "AXXL", "AXXXL", "AXXXXL"]
    var shortName: String { Self.ordered.firstIndex(of: self).map { Self.shortNames[$0] } ?? "L" }

    public static func < (lhs: UIContentSizeCategory, rhs: UIContentSizeCategory) -> Bool {
        (ordered.firstIndex(of: lhs) ?? -1) < (ordered.firstIndex(of: rhs) ?? -1)
    }
}

/// The traits a view resolves against.
public struct UITraitCollection: Hashable, Sendable {
    public var userInterfaceStyle: UIUserInterfaceStyle = .light
    public var horizontalSizeClass: UIUserInterfaceSizeClass = .regular
    public var verticalSizeClass: UIUserInterfaceSizeClass = .regular
    public var userInterfaceIdiom: UIUserInterfaceIdiom = .pad
    public var displayScale: CGFloat = 2
    public var layoutDirection: UITraitEnvironmentLayoutDirection = .leftToRight
    public var preferredContentSizeCategory: UIContentSizeCategory = .large

    public init() {}

    public init(preferredContentSizeCategory: UIContentSizeCategory) {
        self.preferredContentSizeCategory = preferredContentSizeCategory
    }

    public init(layoutDirection: UITraitEnvironmentLayoutDirection) {
        self.layoutDirection = layoutDirection
    }

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
            if t.layoutDirection != .unspecified { result.layoutDirection = t.layoutDirection }
            if t.preferredContentSizeCategory != .unspecified { result.preferredContentSizeCategory = t.preferredContentSizeCategory }
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

/// The traits a view overrides for itself and its subtree (`UIView.traitOverrides`): each set
/// value replaces the inherited one.
public struct UITraitOverrides: Hashable, Sendable {
    public var userInterfaceStyle: UIUserInterfaceStyle?
    public var horizontalSizeClass: UIUserInterfaceSizeClass?
    public var verticalSizeClass: UIUserInterfaceSizeClass?
    public var layoutDirection: UITraitEnvironmentLayoutDirection?
    public var preferredContentSizeCategory: UIContentSizeCategory?
    public var displayScale: CGFloat?

    public init() {}

    /// Applies the set values to `traits`.
    public func apply(to traits: inout UITraitCollection) {
        if let userInterfaceStyle { traits.userInterfaceStyle = userInterfaceStyle }
        if let horizontalSizeClass { traits.horizontalSizeClass = horizontalSizeClass }
        if let verticalSizeClass { traits.verticalSizeClass = verticalSizeClass }
        if let layoutDirection { traits.layoutDirection = layoutDirection }
        if let preferredContentSizeCategory { traits.preferredContentSizeCategory = preferredContentSizeCategory }
        if let displayScale { traits.displayScale = displayScale }
    }
}

// MARK: - Trait change observation (iOS 17: `registerForTraitChanges`)

/// A trait an observer registers for: the value of a trait collection's property.
public protocol UITraitDefinition {
    associatedtype Value: Equatable
    static func value(in traits: UITraitCollection) -> Value
}
public typealias UITrait = any UITraitDefinition.Type

public enum UITraitUserInterfaceStyle: UITraitDefinition { public static func value(in traits: UITraitCollection) -> UIUserInterfaceStyle { traits.userInterfaceStyle } }
public enum UITraitHorizontalSizeClass: UITraitDefinition { public static func value(in traits: UITraitCollection) -> UIUserInterfaceSizeClass { traits.horizontalSizeClass } }
public enum UITraitVerticalSizeClass: UITraitDefinition { public static func value(in traits: UITraitCollection) -> UIUserInterfaceSizeClass { traits.verticalSizeClass } }
public enum UITraitUserInterfaceIdiom: UITraitDefinition { public static func value(in traits: UITraitCollection) -> UIUserInterfaceIdiom { traits.userInterfaceIdiom } }
public enum UITraitDisplayScale: UITraitDefinition { public static func value(in traits: UITraitCollection) -> CGFloat { traits.displayScale } }
public enum UITraitLayoutDirection: UITraitDefinition { public static func value(in traits: UITraitCollection) -> UITraitEnvironmentLayoutDirection { traits.layoutDirection } }
public enum UITraitPreferredContentSizeCategory: UITraitDefinition { public static func value(in traits: UITraitCollection) -> UIContentSizeCategory { traits.preferredContentSizeCategory } }

extension UITraitCollection {
    /// Whether any of `traits` differs between this collection and `other`.
    func differs(from other: UITraitCollection?, in traits: [UITrait]) -> Bool {
        guard let other else { return true }
        return traits.contains { trait in Self.changed(trait, from: other, to: self) }
    }

    private static func changed(_ trait: UITrait, from a: UITraitCollection, to b: UITraitCollection) -> Bool {
        func check<T: UITraitDefinition>(_ type: T.Type) -> Bool { T.value(in: a) != T.value(in: b) }
        return check(trait)
    }
}

/// The token a registration returns, for `unregisterForTraitChanges`.
public final class UITraitChangeRegistration: Hashable, @unchecked Sendable {
    public static func == (lhs: UITraitChangeRegistration, rhs: UITraitChangeRegistration) -> Bool { lhs === rhs }
    public func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}

/// A registered observer: the traits it watches and what to call (an implementation detail
/// `UITraitChangeObservable` stores on its adopters).
@MainActor
public struct TraitChangeObserver {
    let registration: UITraitChangeRegistration
    let traits: [UITrait]
    let handler: @MainActor (UITraitCollection) -> Void
}

/// An object whose trait changes can be observed with handlers (views and view controllers).
@MainActor
public protocol UITraitChangeObservable: AnyObject {
    var traitChangeObservers: [TraitChangeObserver] { get set }
    var traitCollection: UITraitCollection { get }
}

extension UITraitChangeObservable {
    /// Calls `handler` with this object and its traits whenever one of `traits` changes.
    @discardableResult
    public func registerForTraitChanges(_ traits: [UITrait], handler: @escaping @MainActor (Self, UITraitCollection) -> Void) -> UITraitChangeRegistration {
        let registration = UITraitChangeRegistration()
        traitChangeObservers.append(TraitChangeObserver(registration: registration, traits: traits) { [weak self] previous in
            guard let self else { return }
            handler(self, previous)
        })
        return registration
    }

    /// Calls `action` on `target` (or this object) whenever one of `traits` changes.
    @discardableResult
    public func registerForTraitChanges(_ traits: [UITrait], target: AnyObject? = nil, action: @escaping @MainActor (AnyObject, UITraitCollection) -> Void) -> UITraitChangeRegistration {
        let registration = UITraitChangeRegistration()
        let target = target ?? self
        traitChangeObservers.append(TraitChangeObserver(registration: registration, traits: traits) { [weak target] previous in
            guard let target else { return }
            action(target, previous)
        })
        return registration
    }

    public func unregisterForTraitChanges(_ registration: UITraitChangeRegistration) {
        traitChangeObservers.removeAll { $0.registration == registration }
    }

    /// Runs the observers whose traits differ from `previous`.
    func notifyTraitObservers(previous: UITraitCollection?) {
        guard !traitChangeObservers.isEmpty else { return }
        let current = traitCollection
        for observer in traitChangeObservers where current.differs(from: previous, in: observer.traits) { observer.handler(previous ?? current) }
    }
}
