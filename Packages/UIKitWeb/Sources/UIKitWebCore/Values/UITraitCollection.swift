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
    /// The values of an app's own traits (`UITraitDefinition` types), set through overrides.
    var customTraits = _UICustomTraitValues()

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
            result.customTraits.merge(t.customTraits)
        }
        self = result
    }

    /// The value of a trait: one of UIKit's, or an app's own (its default unless an override
    /// above set it).
    public subscript<T: UITraitDefinition>(trait: T.Type) -> T.Value { T.value(in: self) }

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
@preconcurrency @MainActor
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
    /// An app's own traits set here.
    var customTraits = _UICustomTraitValues()

    public init() {}

    /// Applies the set values to `traits`.
    public func apply(to traits: inout UITraitCollection) {
        if let userInterfaceStyle { traits.userInterfaceStyle = userInterfaceStyle }
        if let horizontalSizeClass { traits.horizontalSizeClass = horizontalSizeClass }
        if let verticalSizeClass { traits.verticalSizeClass = verticalSizeClass }
        if let layoutDirection { traits.layoutDirection = layoutDirection }
        if let preferredContentSizeCategory { traits.preferredContentSizeCategory = preferredContentSizeCategory }
        if let displayScale { traits.displayScale = displayScale }
        traits.customTraits.merge(customTraits)
    }

    /// Whether `trait` is overridden here.
    public func contains<T: UITraitDefinition>(_ trait: T.Type) -> Bool {
        if let storage = T._storage { return storage.overrides.map { self[keyPath: $0] != nil } ?? false }
        return customTraits.values[ObjectIdentifier(T.self)] != nil
    }

    /// Takes the override of `trait` away, so the inherited value shows again.
    public mutating func remove<T: UITraitDefinition>(_ trait: T.Type) {
        if let storage = T._storage { if let key = storage.overrides { self[keyPath: key] = nil }; return }
        customTraits.set(ObjectIdentifier(T.self), nil)
    }
}

/// Traits that can be set: a view's or view controller's `traitOverrides`, where an app's own
/// traits are set with their type (`traitOverrides[MyTrait.self] = value`), as swift-navigation
/// sets its dismiss and push actions.
public protocol UIMutableTraits {
    subscript<T: UITraitDefinition>(trait: T.Type) -> T.Value { get set }
}

extension UITraitOverrides: UIMutableTraits {
    /// The overridden value, else the trait's default; setting overrides it (UIKit's
    /// device idiom can't be overridden and keeps its value).
    public subscript<T: UITraitDefinition>(trait: T.Type) -> T.Value {
        get {
            if let storage = T._storage {
                return storage.overrides.flatMap { self[keyPath: $0] } ?? T.defaultValue
            }
            return customTraits.values[ObjectIdentifier(T.self)] as? T.Value ?? T.defaultValue
        }
        set {
            if let storage = T._storage { if let key = storage.overrides { self[keyPath: key] = newValue }; return }
            customTraits.set(ObjectIdentifier(T.self), newValue)
        }
    }
}

/// The values of an app's own traits, by trait type. Values compare with `==` when their type
/// is Equatable; any other value (an action holding a closure, as swift-navigation's are)
/// counts as changed only when it is set again.
public struct _UICustomTraitValues: Hashable, @unchecked Sendable {
    private(set) var values: [ObjectIdentifier: Any] = [:]
    /// When each value was set: a value that can't be compared is the same value while its
    /// stamp is, however many collections it is passed down through.
    private var stamps: [ObjectIdentifier: UInt64] = [:]
    nonisolated(unsafe) private static var nextStamp: UInt64 = 0

    mutating func set(_ key: ObjectIdentifier, _ value: Any?) {
        values[key] = value
        if value != nil {
            Self.nextStamp &+= 1
            stamps[key] = Self.nextStamp
        } else {
            stamps[key] = nil
        }
    }

    mutating func merge(_ other: _UICustomTraitValues) {
        for (key, value) in other.values { values[key] = value; stamps[key] = other.stamps[key] }
    }

    /// Whether `key`'s value is the same in both: by `==` when its type is Equatable, else by
    /// whether it is the value set at the same time.
    func same(_ key: ObjectIdentifier, as other: _UICustomTraitValues) -> Bool {
        switch (values[key], other.values[key]) {
        case (nil, nil): return true
        case let (mine?, theirs?):
            if mine is any Equatable { return _traitValuesEqual(mine, theirs) }
            return stamps[key] != nil && stamps[key] == other.stamps[key]
        default: return false
        }
    }

    public static func == (lhs: _UICustomTraitValues, rhs: _UICustomTraitValues) -> Bool {
        guard lhs.values.count == rhs.values.count else { return false }
        return lhs.values.keys.allSatisfy { lhs.same($0, as: rhs) }
    }

    public func hash(into hasher: inout Hasher) { hasher.combine(values.count) }
}

/// Whether two values of a trait are equal: by `==` for an Equatable type, else never.
func _traitValuesEqual(_ lhs: Any, _ rhs: Any) -> Bool {
    guard let lhs = lhs as? any Equatable else { return false }
    return lhs._isEqual(toTraitValue: rhs)
}

extension Equatable {
    fileprivate func _isEqual(toTraitValue other: Any) -> Bool { (other as? Self) == self }
}

// MARK: - Trait change observation (iOS 17: `registerForTraitChanges`)

/// A trait: one of UIKit's (the appearance, the size classes and the rest) or an app's own,
/// which declares its default and is set through `traitOverrides` (iOS 17's custom traits).
public protocol UITraitDefinition {
    associatedtype Value = Self
    /// The value when nothing above overrides it.
    static var defaultValue: Value { get }
    static var identifier: String { get }
    static var name: String { get }
    static var affectsColorAppearance: Bool { get }
    /// Where a collection and overrides keep one of UIKit's traits; nil for an app's own.
    static var _storage: _UITraitStorage<Value>? { get }
}

/// Where one of UIKit's traits lives in a collection and in overrides.
public struct _UITraitStorage<Value> {
    let collection: KeyPath<UITraitCollection, Value>
    let overrides: WritableKeyPath<UITraitOverrides, Value?>?
}

extension UITraitDefinition {
    public static var identifier: String { String(reflecting: Self.self) }
    public static var name: String { String(describing: Self.self) }
    public static var affectsColorAppearance: Bool { false }
    public static var _storage: _UITraitStorage<Value>? { nil }

    /// The trait's value in `traits`.
    public static func value(in traits: UITraitCollection) -> Value {
        if let storage = _storage { return traits[keyPath: storage.collection] }
        return traits.customTraits.values[ObjectIdentifier(Self.self)] as? Value ?? defaultValue
    }
}
public typealias UITrait = any UITraitDefinition.Type

public enum UITraitUserInterfaceStyle: UITraitDefinition {
    public static var defaultValue: UIUserInterfaceStyle { .unspecified }
    public static var affectsColorAppearance: Bool { true }
    public static var _storage: _UITraitStorage<UIUserInterfaceStyle>? { _UITraitStorage(collection: \.userInterfaceStyle, overrides: \.userInterfaceStyle) }
}
public enum UITraitHorizontalSizeClass: UITraitDefinition {
    public static var defaultValue: UIUserInterfaceSizeClass { .unspecified }
    public static var _storage: _UITraitStorage<UIUserInterfaceSizeClass>? { _UITraitStorage(collection: \.horizontalSizeClass, overrides: \.horizontalSizeClass) }
}
public enum UITraitVerticalSizeClass: UITraitDefinition {
    public static var defaultValue: UIUserInterfaceSizeClass { .unspecified }
    public static var _storage: _UITraitStorage<UIUserInterfaceSizeClass>? { _UITraitStorage(collection: \.verticalSizeClass, overrides: \.verticalSizeClass) }
}
public enum UITraitUserInterfaceIdiom: UITraitDefinition {
    public static var defaultValue: UIUserInterfaceIdiom { .unspecified }
    public static var _storage: _UITraitStorage<UIUserInterfaceIdiom>? { _UITraitStorage(collection: \.userInterfaceIdiom, overrides: nil) }
}
public enum UITraitDisplayScale: UITraitDefinition {
    public static var defaultValue: CGFloat { 0 }
    public static var _storage: _UITraitStorage<CGFloat>? { _UITraitStorage(collection: \.displayScale, overrides: \.displayScale) }
}
public enum UITraitLayoutDirection: UITraitDefinition {
    public static var defaultValue: UITraitEnvironmentLayoutDirection { .unspecified }
    public static var _storage: _UITraitStorage<UITraitEnvironmentLayoutDirection>? { _UITraitStorage(collection: \.layoutDirection, overrides: \.layoutDirection) }
}
public enum UITraitPreferredContentSizeCategory: UITraitDefinition {
    public static var defaultValue: UIContentSizeCategory { .unspecified }
    public static var _storage: _UITraitStorage<UIContentSizeCategory>? { _UITraitStorage(collection: \.preferredContentSizeCategory, overrides: \.preferredContentSizeCategory) }
}

extension UITraitCollection {
    /// Whether any of `traits` differs between this collection and `other`.
    func differs(from other: UITraitCollection?, in traits: [UITrait]) -> Bool {
        guard let other else { return true }
        return traits.contains { trait in Self.changed(trait, from: other, to: self) }
    }

    private static func changed(_ trait: UITrait, from a: UITraitCollection, to b: UITraitCollection) -> Bool {
        func check<T: UITraitDefinition>(_ type: T.Type) -> Bool {
            guard T._storage == nil else { return !_traitValuesEqual(T.value(in: a), T.value(in: b)) }
            // An app's trait changed when it was set or cleared, or set to another value.
            return !a.customTraits.same(ObjectIdentifier(T.self), as: b.customTraits)
        }
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
@preconcurrency @MainActor
public struct TraitChangeObserver {
    let registration: UITraitChangeRegistration
    let traits: [UITrait]
    let handler: @MainActor (UITraitCollection) -> Void
}

/// An object whose trait changes can be observed with handlers (views and view controllers).
@preconcurrency @MainActor
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
