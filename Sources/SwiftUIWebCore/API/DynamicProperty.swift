/// An interface for a stored variable that updates an external property of a view.
///
/// Step 1 declares only the public surface; storage installation by key path (decision 0004)
/// arrives with `State` in Phase 1 step 3.
public protocol DynamicProperty {
    /// Updates the underlying value of the stored value.
    @MainActor @preconcurrency mutating func update()
}

extension DynamicProperty {
    public mutating func update() {}
}
