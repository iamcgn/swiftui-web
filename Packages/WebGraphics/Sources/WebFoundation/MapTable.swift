// Foundation's `NSMapTable` on wasm, where FoundationEssentials has none: a dictionary of objects
// whose keys and values it may hold weakly, so an entry goes once either object is freed (Mlem
// keeps each value's sibling synthesizers in a weak-to-weak table). Keys compare as Foundation's
// object personality does, by `isEqual` and `hash`, or by identity with the pointer personality.
#if os(WASI)

/// How a map table holds and compares what it stores. A table here tells apart the strong and
/// weak memory options and the object and object-pointer personalities.
open class NSPointerFunctions: NSObject, @unchecked Sendable {
    public struct Options: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let strongMemory = Options([])
        public static let opaqueMemory = Options(rawValue: 2)
        public static let mallocMemory = Options(rawValue: 3)
        public static let machVirtualMemory = Options(rawValue: 4)
        public static let weakMemory = Options(rawValue: 5)
        public static let objectPersonality = Options([])
        public static let opaquePersonality = Options(rawValue: 1 << 8)
        public static let objectPointerPersonality = Options(rawValue: 2 << 8)
        public static let cStringPersonality = Options(rawValue: 3 << 8)
        public static let structPersonality = Options(rawValue: 4 << 8)
        public static let integerPersonality = Options(rawValue: 5 << 8)
        public static let copyIn = Options(rawValue: 1 << 16)

        var memory: UInt { rawValue & 0xFF }
        var personality: UInt { rawValue & 0xFF00 }
    }

    public let options: Options
    public init(options: Options) {
        self.options = options
        super.init()
    }
}

open class NSMapTable<KeyType: AnyObject, ObjectType: AnyObject>: NSObject, @unchecked Sendable {
    private struct Slot {
        var strongKey: KeyType?
        weak var weakKey: KeyType?
        var strongValue: ObjectType?
        weak var weakValue: ObjectType?
        var key: KeyType? { strongKey ?? weakKey }
        var value: ObjectType? { strongValue ?? weakValue }
    }

    private let weakKeys: Bool
    private let weakValues: Bool
    private let keysByPointer: Bool
    /// Slots by their key's hash, in the order they were added.
    private var buckets: [Int: [Slot]] = [:]

    public init(keyOptions: NSPointerFunctions.Options = [], valueOptions: NSPointerFunctions.Options = [], capacity initialCapacity: Int = 0) {
        weakKeys = keyOptions.memory == NSPointerFunctions.Options.weakMemory.rawValue
        weakValues = valueOptions.memory == NSPointerFunctions.Options.weakMemory.rawValue
        keysByPointer = keyOptions.personality == NSPointerFunctions.Options.objectPointerPersonality.rawValue
        super.init()
    }

    public convenience override init() { self.init(keyOptions: [], valueOptions: []) }

    open class func strongToStrongObjects() -> NSMapTable<KeyType, ObjectType> { NSMapTable(keyOptions: .strongMemory, valueOptions: .strongMemory) }
    open class func weakToStrongObjects() -> NSMapTable<KeyType, ObjectType> { NSMapTable(keyOptions: .weakMemory, valueOptions: .strongMemory) }
    open class func strongToWeakObjects() -> NSMapTable<KeyType, ObjectType> { NSMapTable(keyOptions: .strongMemory, valueOptions: .weakMemory) }
    open class func weakToWeakObjects() -> NSMapTable<KeyType, ObjectType> { NSMapTable(keyOptions: .weakMemory, valueOptions: .weakMemory) }

    private func hash(of key: KeyType) -> Int {
        if !keysByPointer, let object = key as? NSObject { return object.hash }
        return ObjectIdentifier(key).hashValue
    }

    private func matches(_ key: KeyType, _ other: KeyType) -> Bool {
        if key === other { return true }
        guard !keysByPointer, let object = key as? NSObject else { return false }
        return object.isEqual(other)
    }

    /// Drops the entries whose key or value has been freed.
    private func prune() {
        for (bucket, slots) in buckets {
            let live = slots.filter { $0.key != nil && $0.value != nil }
            if live.count != slots.count { buckets[bucket] = live.isEmpty ? nil : live }
        }
    }

    open var count: Int {
        prune()
        return buckets.values.reduce(0) { $0 + $1.count }
    }

    open func object(forKey aKey: KeyType?) -> ObjectType? {
        guard let aKey else { return nil }
        for slot in buckets[hash(of: aKey)] ?? [] {
            if let key = slot.key, let value = slot.value, matches(key, aKey) { return value }
        }
        return nil
    }

    open func setObject(_ anObject: ObjectType?, forKey aKey: KeyType?) {
        guard let aKey else { return }
        guard let anObject else { return removeObject(forKey: aKey) }
        var slot = Slot()
        if weakKeys { slot.weakKey = aKey } else { slot.strongKey = aKey }
        if weakValues { slot.weakValue = anObject } else { slot.strongValue = anObject }
        let bucket = hash(of: aKey)
        var slots = (buckets[bucket] ?? []).filter { $0.key != nil && $0.value != nil }
        if let index = slots.firstIndex(where: { matches($0.key!, aKey) }) {
            // Foundation keeps the key already in the table and replaces only the value.
            if weakKeys { slot.weakKey = slots[index].key } else { slot.strongKey = slots[index].key }
            slots[index] = slot
        } else {
            slots.append(slot)
        }
        buckets[bucket] = slots
    }

    open func removeObject(forKey aKey: KeyType?) {
        guard let aKey else { return }
        let bucket = hash(of: aKey)
        guard let slots = buckets[bucket] else { return }
        let rest = slots.filter { slot in
            guard let key = slot.key, slot.value != nil else { return false }
            return !matches(key, aKey)
        }
        buckets[bucket] = rest.isEmpty ? nil : rest
    }

    open func removeAllObjects() { buckets = [:] }

    /// The live entries as a dictionary, keyed as `NSCache` keys its entries: by the key's
    /// hashable value, else by its identity.
    open func dictionaryRepresentation() -> [AnyHashable: ObjectType] {
        var result: [AnyHashable: ObjectType] = [:]
        for slots in buckets.values {
            for slot in slots {
                guard let key = slot.key, let value = slot.value else { continue }
                result[(key as? AnyHashable) ?? AnyHashable(ObjectIdentifier(key))] = value
            }
        }
        return result
    }
}
#endif
