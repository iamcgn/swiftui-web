@_spi(Reflection) import Swift

/// The dynamic-property fields of a type, discovered once by key-path reflection and cached.
/// Each installer opens the field's concrete `DynamicProperty` type so installation is a plain
/// generic call per body evaluation.
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
        _ = _forEachFieldWithKeyPath(of: Root.self, options: []) { name, keyPath in
            guard let propertyType = type(of: keyPath).valueType as? any DynamicProperty.Type else {
                return true
            }
            @MainActor func open<P: DynamicProperty>(_: P.Type) {
                guard let typed = keyPath as? WritableKeyPath<Root, P> else {
                    // `let` properties cannot be installed; SwiftUI requires `var` too.
                    return
                }
                fields.append(Field(name: String(cString: name), propertyType: P.self) { root, node, slot in
                    root[keyPath: typed]._install(in: node, slot: &slot)
                    root[keyPath: typed].update()
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
