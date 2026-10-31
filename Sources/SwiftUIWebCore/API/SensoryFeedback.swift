// `sensoryFeedback` (Docs/coverage.md: 3 apps): haptics on a value's change. A page has no
// haptic engine to drive (the browser's vibration call reaches only some Android phones, and
// never a desktop), so the modifiers compile and leave the view as it is.

/// A type that represents a sensory feedback, a haptic on iOS.
public struct SensoryFeedback: Equatable, Sendable {
    package enum Kind: Equatable, Sendable {
        case success, warning, error, selection, increase, decrease, start, stop, alignment, levelChange, pathComplete
        case impact(weight: Weight, intensity: Double)
        case flexibleImpact(flexibility: Flexibility, intensity: Double)
    }
    package let kind: Kind

    /// The weight of an impact.
    public struct Weight: Equatable, Sendable {
        package let value: Int
        public static let light = Weight(value: 0)
        public static let medium = Weight(value: 1)
        public static let heavy = Weight(value: 2)
    }

    /// The flexibility of an impact.
    public struct Flexibility: Equatable, Sendable {
        package let value: Int
        public static let rigid = Flexibility(value: 0)
        public static let solid = Flexibility(value: 1)
        public static let soft = Flexibility(value: 2)
    }

    public static let success = SensoryFeedback(kind: .success)
    public static let warning = SensoryFeedback(kind: .warning)
    public static let error = SensoryFeedback(kind: .error)
    public static let selection = SensoryFeedback(kind: .selection)
    public static let increase = SensoryFeedback(kind: .increase)
    public static let decrease = SensoryFeedback(kind: .decrease)
    public static let start = SensoryFeedback(kind: .start)
    public static let stop = SensoryFeedback(kind: .stop)
    public static let alignment = SensoryFeedback(kind: .alignment)
    public static let levelChange = SensoryFeedback(kind: .levelChange)
    public static let pathComplete = SensoryFeedback(kind: .pathComplete)
    public static let impact = SensoryFeedback(kind: .impact(weight: .medium, intensity: 1))

    public static func impact(weight: Weight = .medium, intensity: Double = 1) -> SensoryFeedback {
        SensoryFeedback(kind: .impact(weight: weight, intensity: intensity))
    }

    public static func impact(flexibility: Flexibility, intensity: Double = 1) -> SensoryFeedback {
        SensoryFeedback(kind: .flexibleImpact(flexibility: flexibility, intensity: intensity))
    }
}

extension View {
    /// Plays the feedback when the trigger value changes.
    nonisolated public func sensoryFeedback<T: Equatable>(_ feedback: SensoryFeedback, trigger: T) -> some View { self }

    /// Plays the feedback when the trigger value changes and the condition holds.
    nonisolated public func sensoryFeedback<T: Equatable>(_ feedback: SensoryFeedback, trigger: T, condition: @escaping (_ oldValue: T, _ newValue: T) -> Bool) -> some View { self }

    /// Plays the feedback the closure returns when the trigger value changes.
    nonisolated public func sensoryFeedback<T: Equatable>(trigger: T, _ feedback: @escaping (_ oldValue: T, _ newValue: T) -> SensoryFeedback?) -> some View { self }

    /// Plays the feedback the closure returns when the trigger value changes.
    nonisolated public func sensoryFeedback<T: Equatable>(trigger: T, _ feedback: @escaping () -> SensoryFeedback?) -> some View { self }
}
