@_spi(Reflection) import Swift

/// The dynamic-property fields of a type, discovered once by stdlib field reflection and cached.
///
/// `_forEachField` (name, byte offset, type) is used rather than `_forEachFieldWithKeyPath`:
/// the key-path variant refuses any struct that has a plain closure stored property
/// (`() -> Void`), which view structs with action callbacks routinely have (verified 2026-09-02,
/// Swift 6.3.3). Installation writes through the field's offset with the opened property type.
@MainActor
package struct _DynamicPropertyFields<Root> {
    package struct Field {
        package let name: String
        package let propertyType: Any.Type
        package let install: @MainActor (inout Root, ViewNode, inout AnyObject?) -> Void
    }

    package let fields: [Field]

    package static var shared: _DynamicPropertyFields<Root> {
        let key = ObjectIdentifier(Root.self)
        if let cached = dynamicPropertyFieldCache[key] as? _DynamicPropertyFields<Root> { return cached }
        var fields: [Field] = []
        _ = _forEachField(of: Root.self, options: []) { name, offset, type, _ in
            guard let propertyType = type as? any DynamicProperty.Type else { return true }
            @MainActor func open<P: DynamicProperty>(_: P.Type) {
                fields.append(Field(name: String(cString: name), propertyType: P.self) { root, node, slot in
                    withUnsafeMutablePointer(to: &root) { base in
                        let property = UnsafeMutableRawPointer(base).advanced(by: offset).assumingMemoryBound(to: P.self)
                        property.pointee._install(in: node, slot: &slot)
                        property.pointee.update()
                    }
                })
            }
            open(propertyType)
            return true
        }
        let result = _DynamicPropertyFields(fields: fields)
        dynamicPropertyFieldCache[key] = result
        return result
    }

    /// Installs every dynamic property of `root`, keeping per-field storage in `slot`.
    package static func installAll(into root: inout Root, node: ViewNode, slot: inout AnyObject?) {
        let fields = shared.fields
        guard !fields.isEmpty else { return }
        let storage = (slot as? DynamicPropertyStorage) ?? DynamicPropertyStorage(count: fields.count)
        slot = storage
        storage.install(fields, into: &root, node: node)
    }
}

/// Per-node storage slots for a value's dynamic properties, one per discovered field.
@MainActor
package final class DynamicPropertyStorage {
    package var slots: [AnyObject?]

    package init(count: Int) {
        slots = Array(repeating: nil, count: count)
    }

    package func install<Root>(_ fields: [_DynamicPropertyFields<Root>.Field], into root: inout Root, node: ViewNode) {
        for (index, field) in fields.enumerated() {
            field.install(&root, node, &slots[index])
        }
    }
}

@MainActor
private var dynamicPropertyFieldCache: [ObjectIdentifier: Any] = [:]
