/// An interface for a stored variable that updates an external property of a view.
///
/// The runtime discovers stored properties of this type in every composite view by key path
/// (decision 0004), installs their storage before each body evaluation, and calls `update()`.
public protocol DynamicProperty {
    /// Updates the underlying value of the stored value.
    @MainActor @preconcurrency mutating func update()

    /// Hidden runtime hook: attaches this property to `node`, using `slot` as its persistent
    /// storage across body evaluations. The default installs nested dynamic properties.
    @MainActor mutating func _install(in node: ViewNode, slot: inout AnyObject?)
}

extension DynamicProperty {
    @MainActor
    public mutating func update() {}

    @MainActor
    public mutating func _install(in node: ViewNode, slot: inout AnyObject?) {
        _DynamicPropertyFields<Self>.installAll(into: &self, node: node, slot: &slot)
    }
}
