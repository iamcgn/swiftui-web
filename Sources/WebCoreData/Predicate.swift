// Foundation's predicates and sort descriptors, for Core Data (Apple's are Objective-C classes
// in Foundation, evaluated through key-value coding). Here a predicate is a tree the format
// parser builds — comparisons (`==`, `!=`, `<`, `<=`, `>`, `>=`, `BETWEEN`, `IN`, `CONTAINS`,
// `BEGINSWITH`, `ENDSWITH`, `LIKE`, `MATCHES`, with `[cd]`), `ANY`/`ALL`/`NONE`, `AND`/`OR`/`NOT`,
// `%@`/`%K`/`%d`-style arguments, key paths with `@count`/`@sum`/`@avg`/`@min`/`@max` — evaluated
// over objects that answer `value(forKey:)` (managed objects) and over dictionaries.
//
// Not Foundation: no `SUBQUERY`, `FUNCTION` or arithmetic expressions, no selectors. A format
// the parser cannot read evaluates to false and says so on the console (Foundation raises).

/// An object whose properties are read by name (key-value coding, as predicates use it).
public protocol _CDKeyValueCoding: AnyObject {
    func value(forKey key: String) -> Any?
}

// MARK: - NSPredicate

/// A definition of logical conditions for constraining a search for a fetch or for in-memory
/// filtering.
open class NSPredicate: CustomStringConvertible, @unchecked Sendable {
    let _node: _PredicateNode

    init(_node node: _PredicateNode) { _node = node }

    /// A predicate of this kind over the node (`withSubstitutionVariables`).
    func _make(_ node: _PredicateNode) -> NSPredicate { NSPredicate(_node: node) }

    /// Creates a predicate by substituting the arguments into the format string.
    public convenience init(format predicateFormat: String, _ args: Any...) {
        self.init(format: predicateFormat, argumentArray: args)
    }

    /// Creates a predicate by substituting the array's values into the format string.
    public convenience init(format predicateFormat: String, argumentArray arguments: [Any]?) {
        do {
            var parser = _PredicateParser(predicateFormat, arguments: arguments ?? [])
            self.init(_node: try parser.parse())
        } catch {
            print("NSPredicate: cannot parse \"\(predicateFormat)\" (\(error)); it evaluates to false")
            self.init(_node: .constant(false))
        }
    }

    /// A predicate that always evaluates to the value.
    public convenience init(value: Bool) { self.init(_node: .constant(value)) }

    /// A predicate that evaluates the block with the object and the substitution variables.
    public convenience init(block: @escaping (Any?, [String: Any]?) -> Bool) { self.init(_node: .block(block)) }

    /// Whether the object satisfies the predicate.
    open func evaluate(with object: Any?) -> Bool { _node.evaluate(object, variables: [:]) }

    /// Whether the object satisfies the predicate, with `$VARIABLE`s bound.
    open func evaluate(with object: Any?, substitutionVariables bindings: [String: Any]?) -> Bool {
        _node.evaluate(object, variables: bindings ?? [:])
    }

    /// A copy whose `$VARIABLE`s are the values given.
    open func withSubstitutionVariables(_ variables: [String: Any]) -> Self {
        (_make(_node.substituting(variables)) as? Self) ?? self
    }

    /// Accepted: predicates here are always evaluable.
    open func allowEvaluation() {}

    /// The predicate's format string.
    open var predicateFormat: String { _node.format }
    open var description: String { predicateFormat }
}

// MARK: - NSComparisonPredicate

/// A specialized predicate for comparing expressions.
open class NSComparisonPredicate: NSPredicate, @unchecked Sendable {
    public enum Operator: UInt, Sendable {
        case lessThan = 0, lessThanOrEqualTo, greaterThan, greaterThanOrEqualTo, equalTo, notEqualTo
        case matches, like, beginsWith, endsWith
        case `in` = 10, customSelector, contains = 99, between
    }

    public enum Modifier: UInt, Sendable { case direct = 0, all, any }

    public struct Options: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let caseInsensitive = Options(rawValue: 1)
        public static let diacriticInsensitive = Options(rawValue: 2)
        public static let normalized = Options(rawValue: 4)
    }

    public let leftExpression: NSExpression
    public let rightExpression: NSExpression
    public let predicateOperatorType: Operator
    public let comparisonPredicateModifier: Modifier
    public let options: Options

    public init(leftExpression lhs: NSExpression, rightExpression rhs: NSExpression, modifier: Modifier, type: Operator, options: Options = []) {
        leftExpression = lhs
        rightExpression = rhs
        predicateOperatorType = type
        comparisonPredicateModifier = modifier
        self.options = options
        super.init(_node: .comparison(lhs, type, rhs, modifier, options, negateAll: false))
    }

    override func _make(_ node: _PredicateNode) -> NSPredicate { NSComparisonPredicate(_node: node) }

    override init(_node node: _PredicateNode) {
        if case .comparison(let l, let op, let r, let m, let o, _) = node {
            leftExpression = l; rightExpression = r; predicateOperatorType = op; comparisonPredicateModifier = m; options = o
        } else {
            leftExpression = NSExpression(forConstantValue: nil); rightExpression = leftExpression
            predicateOperatorType = .equalTo; comparisonPredicateModifier = .direct; options = []
        }
        super.init(_node: node)
    }
}

// MARK: - NSCompoundPredicate

/// A specialized predicate that evaluates logical combinations of other predicates.
open class NSCompoundPredicate: NSPredicate, @unchecked Sendable {
    public enum LogicalType: UInt, Sendable { case not = 0, and, or }

    public let compoundPredicateType: LogicalType
    public let subpredicates: [Any]

    public init(type: LogicalType, subpredicates: [NSPredicate]) {
        compoundPredicateType = type
        self.subpredicates = subpredicates
        let nodes = subpredicates.map(\._node)
        switch type {
        case .and: super.init(_node: .and(nodes))
        case .or: super.init(_node: .or(nodes))
        case .not: super.init(_node: .not(nodes.count == 1 ? nodes[0] : .and(nodes)))
        }
    }

    public convenience init(andPredicateWithSubpredicates subpredicates: [NSPredicate]) { self.init(type: .and, subpredicates: subpredicates) }
    public convenience init(orPredicateWithSubpredicates subpredicates: [NSPredicate]) { self.init(type: .or, subpredicates: subpredicates) }
    public convenience init(notPredicateWithSubpredicate predicate: NSPredicate) { self.init(type: .not, subpredicates: [predicate]) }

    override func _make(_ node: _PredicateNode) -> NSPredicate { NSCompoundPredicate(_node: node) }

    override init(_node node: _PredicateNode) {
        switch node {
        case .and(let nodes): compoundPredicateType = .and; subpredicates = nodes.map { NSPredicate(_node: $0) }
        case .or(let nodes): compoundPredicateType = .or; subpredicates = nodes.map { NSPredicate(_node: $0) }
        case .not(let inner): compoundPredicateType = .not; subpredicates = [NSPredicate(_node: inner)]
        default: compoundPredicateType = .and; subpredicates = [NSPredicate(_node: node)]
        }
        super.init(_node: node)
    }
}

// MARK: - NSExpression

/// An expression for use in a comparison predicate: a constant, a key path, the evaluated
/// object, a variable, or a collection of expressions.
open class NSExpression: CustomStringConvertible, @unchecked Sendable {
    public enum ExpressionType: UInt, Sendable {
        case constantValue = 0, evaluatedObject, variable, keyPath, function
        case unionSet, intersectSet, minusSet
        case subquery = 13, aggregate, anyKey = 15, block = 19, conditional = 20
    }

    enum Kind {
        case constant(Any?)
        case evaluatedObject
        case keyPath(String)
        case variable(String)
        case aggregate([NSExpression])
        case function(String, [NSExpression])
        case block(([String: Any]) -> Any?)
    }

    let kind: Kind
    init(kind: Kind) { self.kind = kind }

    public convenience init(forConstantValue obj: Any?) { self.init(kind: .constant(obj)) }
    public convenience init(forKeyPath keyPath: String) { self.init(kind: .keyPath(keyPath)) }
    /// A key path expression from a Swift key path into a managed object's entity.
    public convenience init<Root, Value>(forKeyPath keyPath: KeyPath<Root, Value>) {
        self.init(kind: .keyPath(NSManagedObject._key(for: keyPath, in: Root.self) ?? "\(keyPath)"))
    }
    public convenience init(forVariable string: String) { self.init(kind: .variable(string)) }
    public convenience init(forAggregate subexpressions: [NSExpression]) { self.init(kind: .aggregate(subexpressions)) }
    public convenience init(forFunction name: String, arguments parameters: [Any]) {
        self.init(kind: .function(name, parameters.compactMap { $0 as? NSExpression }))
    }
    public class func expressionForEvaluatedObject() -> NSExpression { NSExpression(kind: .evaluatedObject) }

    public var expressionType: ExpressionType {
        switch kind {
        case .constant: return .constantValue
        case .evaluatedObject: return .evaluatedObject
        case .keyPath: return .keyPath
        case .variable: return .variable
        case .aggregate: return .aggregate
        case .function: return .function
        case .block: return .block
        }
    }
    public var constantValue: Any? { if case .constant(let v) = kind { return v }; return nil }
    public var keyPath: String { if case .keyPath(let k) = kind { return k }; return "" }
    public var variable: String { if case .variable(let v) = kind { return v }; return "" }
    public var function: String { if case .function(let f, _) = kind { return f }; return "" }
    public var arguments: [NSExpression]? { if case .function(_, let a) = kind { return a }; return nil }
    public var collection: Any { if case .aggregate(let items) = kind { return items }; return [] }

    /// The expression's value for the object.
    open func expressionValue(with object: Any?, context: [String: Any]?) -> Any? {
        _value(object, variables: context ?? [:])
    }

    func _value(_ object: Any?, variables: [String: Any]) -> Any? {
        switch kind {
        case .constant(let v): return v
        case .evaluatedObject: return object
        case .keyPath(let path): return _cdValue(of: object, keyPath: path)
        case .variable(let name): return variables[name]
        case .aggregate(let items): return items.map { $0._value(object, variables: variables) as Any }
        case .function(let name, let args):
            let values = args.map { $0._value(object, variables: variables) }
            return _cdFunction(name, values)
        case .block(let block): return block(variables)
        }
    }

    func substituting(_ variables: [String: Any]) -> NSExpression {
        switch kind {
        case .variable(let name): if let value = variables[name] { return NSExpression(forConstantValue: value) }; return self
        case .aggregate(let items): return NSExpression(forAggregate: items.map { $0.substituting(variables) })
        default: return self
        }
    }

    open var description: String {
        switch kind {
        case .constant(let v): return _cdFormatConstant(v)
        case .evaluatedObject: return "SELF"
        case .keyPath(let k): return k
        case .variable(let v): return "$" + v
        case .aggregate(let items): return "{" + items.map(\.description).joined(separator: ", ") + "}"
        case .function(let name, let args): return name + "(" + args.map(\.description).joined(separator: ", ") + ")"
        case .block: return "BLOCK"
        }
    }
}

func _cdFormatConstant(_ value: Any?) -> String {
    guard let value = _cdUnwrap(value) else { return "nil" }
    if let s = _cdString(value) { return "\"" + s.replacing("\"", with: "\\\"") + "\"" }
    if let b = value as? Bool { return b ? "1" : "0" }
    if let items = _cdElements(value) { return "{" + items.map { _cdFormatConstant($0) }.joined(separator: ", ") + "}" }
    if let date = value as? Date { return "CAST(\(date.timeIntervalSinceReferenceDate), \"NSDate\")" }
    return "\(value)"
}

func _cdFunction(_ name: String, _ values: [Any?]) -> Any? {
    let numbers = values.flatMap { _cdElements($0) ?? [$0 as Any] }.compactMap { _cdDouble($0) }
    switch name.lowercased() {
    case "sum:": return numbers.reduce(0, +)
    case "count:": return values.flatMap { _cdElements($0) ?? [] }.count
    case "min:": return numbers.min()
    case "max:": return numbers.max()
    case "average:": return numbers.isEmpty ? nil : numbers.reduce(0, +) / Double(numbers.count)
    case "now", "now()": return Date()
    case "lowercase:": return _cdString(values.first ?? nil)?.lowercased()
    case "uppercase:": return _cdString(values.first ?? nil)?.uppercased()
    default: return nil
    }
}

/// A value at a key path: `name`, `owner.name`, `items.@count`, `items.@sum.amount`, `SELF`.
/// A path that runs through a to-many relationship gives the collection of values.
func _cdValue(of object: Any?, keyPath: String) -> Any? {
    var components = keyPath.split(separator: ".").map(String.init)
    var current: Any? = object
    while !components.isEmpty {
        let key = components.removeFirst()
        if key == "SELF" || key == "self" { continue }
        if key.hasPrefix("@") {
            let elements = _cdElements(current) ?? (current.map { [$0] } ?? [])
            if key == "@count" { return elements.count }
            let rest = components.joined(separator: ".")
            let values = rest.isEmpty ? elements : elements.map { _cdValue(of: $0, keyPath: rest) as Any }
            components.removeAll()
            let numbers = values.compactMap { _cdDouble($0) }
            switch key {
            case "@sum": return numbers.reduce(0, +)
            case "@avg": return numbers.isEmpty ? nil : numbers.reduce(0, +) / Double(numbers.count)
            case "@min": return values.compactMap(_cdUnwrap).min { _cdCompare($0, $1) == .orderedAscending }
            case "@max": return values.compactMap(_cdUnwrap).max { _cdCompare($0, $1) == .orderedAscending }
            case "@distinctUnionOfObjects": return Array(Set(values.compactMap { _cdUnwrap($0) as? AnyHashable })).map(\.base)
            case "@unionOfObjects": return values
            default: return nil
            }
        }
        if let elements = _cdElements(current) {
            current = elements.flatMap { element -> [Any] in
                let value = _cdValue(of: element, keyPath: key)
                return _cdElements(value) ?? (_cdUnwrap(value).map { [$0] } ?? [])
            }
            continue
        }
        current = _cdValueForKey(current, key)
    }
    return current
}

func _cdValueForKey(_ object: Any?, _ key: String) -> Any? {
    switch _cdUnwrap(object) {
    case let coded as _CDKeyValueCoding: return coded.value(forKey: key)
    case let dictionary as [String: Any]: return dictionary[key]
    case let dictionary as [AnyHashable: Any]: return dictionary[key]
    default: return nil
    }
}

// MARK: - The predicate tree

indirect enum _PredicateNode {
    case constant(Bool)
    case and([_PredicateNode])
    case or([_PredicateNode])
    case not(_PredicateNode)
    case comparison(NSExpression, NSComparisonPredicate.Operator, NSExpression, NSComparisonPredicate.Modifier, NSComparisonPredicate.Options, negateAll: Bool)
    case block((Any?, [String: Any]?) -> Bool)

    func evaluate(_ object: Any?, variables: [String: Any]) -> Bool {
        switch self {
        case .constant(let value): return value
        case .and(let nodes): return nodes.allSatisfy { $0.evaluate(object, variables: variables) }
        case .or(let nodes): return nodes.contains { $0.evaluate(object, variables: variables) }
        case .not(let node): return !node.evaluate(object, variables: variables)
        case .block(let block): return block(object, variables)
        case .comparison(let lhs, let op, let rhs, let modifier, let options, let none):
            let left = lhs._value(object, variables: variables)
            let right = rhs._value(object, variables: variables)
            switch modifier {
            case .direct:
                // A key path through a to-many relationship compares any of its values, as
                // Foundation does for `IN`-less paths in Core Data fetches.
                if op != .in, op != .contains, op != .between, case .keyPath = lhs.kind, let elements = _cdElements(left) {
                    return elements.contains { _cdTest($0, op, right, options) }
                }
                return _cdTest(left, op, right, options)
            case .any:
                let elements = _cdElements(left) ?? [left as Any]
                let result = elements.contains { _cdTest($0, op, right, options) }
                return none ? !result : result
            case .all:
                let elements = _cdElements(left) ?? [left as Any]
                return elements.allSatisfy { _cdTest($0, op, right, options) }
            }
        }
    }

    func substituting(_ variables: [String: Any]) -> _PredicateNode {
        switch self {
        case .and(let nodes): return .and(nodes.map { $0.substituting(variables) })
        case .or(let nodes): return .or(nodes.map { $0.substituting(variables) })
        case .not(let node): return .not(node.substituting(variables))
        case .comparison(let l, let op, let r, let m, let o, let n): return .comparison(l.substituting(variables), op, r.substituting(variables), m, o, negateAll: n)
        default: return self
        }
    }

    var format: String {
        switch self {
        case .constant(let value): return value ? "TRUEPREDICATE" : "FALSEPREDICATE"
        case .and(let nodes): return nodes.map { $0.nested }.joined(separator: " AND ")
        case .or(let nodes): return nodes.map { $0.nested }.joined(separator: " OR ")
        case .not(let node): return "NOT " + node.nested
        case .block: return "BLOCKPREDICATE"
        case .comparison(let l, let op, let r, let m, let o, let none):
            let prefix = none ? "NONE " : m == .any ? "ANY " : m == .all ? "ALL " : ""
            var flags = ""
            if o.contains(.caseInsensitive) { flags += "c" }
            if o.contains(.diacriticInsensitive) { flags += "d" }
            return prefix + l.description + " " + op.symbol + (flags.isEmpty ? "" : "[\(flags)]") + " " + r.description
        }
    }

    private var nested: String {
        switch self {
        case .and, .or: return "(" + format + ")"
        default: return format
        }
    }
}

extension NSComparisonPredicate.Operator {
    var symbol: String {
        switch self {
        case .lessThan: return "<"
        case .lessThanOrEqualTo: return "<="
        case .greaterThan: return ">"
        case .greaterThanOrEqualTo: return ">="
        case .equalTo: return "=="
        case .notEqualTo: return "!="
        case .matches: return "MATCHES"
        case .like: return "LIKE"
        case .beginsWith: return "BEGINSWITH"
        case .endsWith: return "ENDSWITH"
        case .in: return "IN"
        case .customSelector: return "SELECTOR"
        case .contains: return "CONTAINS"
        case .between: return "BETWEEN"
        }
    }
}

/// One comparison of two values.
func _cdTest(_ left: Any?, _ op: NSComparisonPredicate.Operator, _ right: Any?, _ options: NSComparisonPredicate.Options) -> Bool {
    switch op {
    case .equalTo: return _cdEqual(left, right, options)
    case .notEqualTo: return !_cdEqual(left, right, options)
    case .lessThan: return _cdCompare(left, right, options) == .orderedAscending
    case .lessThanOrEqualTo: return [.orderedAscending, .orderedSame].contains(_cdCompare(left, right, options))
    case .greaterThan: return _cdCompare(left, right, options) == .orderedDescending
    case .greaterThanOrEqualTo: return [.orderedDescending, .orderedSame].contains(_cdCompare(left, right, options))
    case .between:
        guard let bounds = _cdElements(right), bounds.count == 2 else { return false }
        return [.orderedDescending, .orderedSame].contains(_cdCompare(left, bounds[0], options))
            && [.orderedAscending, .orderedSame].contains(_cdCompare(left, bounds[1], options))
    case .in:
        if let elements = _cdElements(right) { return elements.contains { _cdEqual(left, $0, options) } }
        if let haystack = _cdString(right), let needle = _cdString(left) { return _cdFold(haystack, options).contains(_cdFold(needle, options)) }
        return false
    case .contains:
        if let elements = _cdElements(left) { return elements.contains { _cdEqual($0, right, options) } }
        guard let haystack = _cdString(left), let needle = _cdString(right) else { return false }
        let n = _cdFold(needle, options)
        return n.isEmpty ? true : _cdFold(haystack, options).contains(n)
    case .beginsWith:
        guard let s = _cdString(left), let p = _cdString(right) else { return false }
        return _cdFold(s, options).hasPrefix(_cdFold(p, options))
    case .endsWith:
        guard let s = _cdString(left), let p = _cdString(right) else { return false }
        return _cdFold(s, options).hasSuffix(_cdFold(p, options))
    case .like:
        guard let s = _cdString(left), let p = _cdString(right) else { return false }
        return _cdLike(_cdFold(s, options), _cdFold(p, options))
    case .matches:
        guard let s = _cdString(left), let p = _cdString(right) else { return false }
        return _cdMatches(_cdFold(s, options), p)
    case .customSelector: return false
    }
}

// MARK: - The format parser

struct _PredicateParseError: Error, CustomStringConvertible {
    let description: String
}

struct _PredicateParser {
    enum Token: Equatable {
        case word(String)       // identifiers, key paths and keywords
        case string(String)
        case number(String)
        case argument(Character) // %@, %K, %d …: the conversion character ('@', 'K', 'd', 'f', 's')
        case variable(String)
        case symbol(String)     // ( ) { } , and the comparison operators
        case flags(String)      // [cd]
    }

    private var tokens: [Token] = []
    private var position = 0
    private var arguments: [Any]
    private var argumentIndex = 0

    init(_ format: String, arguments: [Any]) {
        self.arguments = arguments
        tokens = Self.tokenize(format)
    }

    mutating func parse() throws -> _PredicateNode {
        let node = try parseOr()
        guard position == tokens.count else { throw _PredicateParseError(description: "unexpected \(tokens[position])") }
        return node
    }

    // MARK: Tokens

    static func tokenize(_ format: String) -> [Token] {
        var tokens: [Token] = []
        let chars = Array(format)
        var i = 0
        func isWordStart(_ c: Character) -> Bool { c.isLetter || c == "_" || c == "@" || c == "#" }
        func isWord(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "_" || c == "@" || c == "." || c == "#" }
        while i < chars.count {
            let c = chars[i]
            if c.isWhitespace { i += 1; continue }
            if c == "%" {
                var j = i + 1
                while j < chars.count, "lqhLz".contains(chars[j]) { j += 1 }
                if j < chars.count { tokens.append(.argument(chars[j])); i = j + 1 } else { i = j }
                continue
            }
            if c == "\"" || c == "'" {
                var j = i + 1, text = ""
                while j < chars.count, chars[j] != c {
                    if chars[j] == "\\", j + 1 < chars.count { j += 1 }
                    text.append(chars[j]); j += 1
                }
                tokens.append(.string(text)); i = j + 1
                continue
            }
            if c == "$" {
                var j = i + 1, name = ""
                while j < chars.count, isWord(chars[j]) { name.append(chars[j]); j += 1 }
                tokens.append(.variable(name)); i = j
                continue
            }
            if c.isNumber || (c == "-" && i + 1 < chars.count && chars[i + 1].isNumber && !(tokens.last.map(Self.endsOperand) ?? false)) {
                var j = i + 1, text = String(c)
                while j < chars.count, chars[j].isNumber || chars[j] == "." || chars[j] == "e" || chars[j] == "E" { text.append(chars[j]); j += 1 }
                tokens.append(.number(text)); i = j
                continue
            }
            if isWordStart(c) {
                var j = i, text = ""
                while j < chars.count, isWord(chars[j]) { text.append(chars[j]); j += 1 }
                tokens.append(.word(text)); i = j
                continue
            }
            if c == "[" {
                var j = i + 1, text = ""
                while j < chars.count, chars[j] != "]" { text.append(chars[j]); j += 1 }
                tokens.append(.flags(text.lowercased())); i = j + 1
                continue
            }
            let two = i + 1 < chars.count ? String(chars[i...i + 1]) : ""
            if ["==", "!=", "<>", "<=", ">=", "=<", "=>", "&&", "||"].contains(two) {
                tokens.append(.symbol(two)); i += 2
                continue
            }
            tokens.append(.symbol(String(c))); i += 1
        }
        return tokens
    }

    private static func endsOperand(_ token: Token) -> Bool {
        switch token {
        case .word, .string, .number, .argument, .variable: return true
        case .symbol(let s): return s == ")" || s == "}"
        case .flags: return false
        }
    }

    private var current: Token? { position < tokens.count ? tokens[position] : nil }

    private func isKeyword(_ token: Token?, _ keywords: String...) -> Bool {
        guard case .word(let word)? = token else { return false }
        return keywords.contains(word.uppercased())
    }

    private mutating func expect(_ symbol: String) throws {
        guard current == .symbol(symbol) else { throw _PredicateParseError(description: "expected \(symbol)") }
        position += 1
    }

    // MARK: Predicates

    private mutating func parseOr() throws -> _PredicateNode {
        var nodes = [try parseAnd()]
        while isKeyword(current, "OR") || current == .symbol("||") {
            position += 1
            nodes.append(try parseAnd())
        }
        return nodes.count == 1 ? nodes[0] : .or(nodes)
    }

    private mutating func parseAnd() throws -> _PredicateNode {
        var nodes = [try parseNot()]
        while isKeyword(current, "AND") || current == .symbol("&&") {
            position += 1
            nodes.append(try parseNot())
        }
        return nodes.count == 1 ? nodes[0] : .and(nodes)
    }

    private mutating func parseNot() throws -> _PredicateNode {
        if isKeyword(current, "NOT") || current == .symbol("!") {
            position += 1
            return .not(try parseNot())
        }
        return try parsePrimary()
    }

    private mutating func parsePrimary() throws -> _PredicateNode {
        if current == .symbol("(") {
            // A parenthesized predicate (expressions in parentheses are not supported).
            position += 1
            let node = try parseOr()
            try expect(")")
            return node
        }
        if isKeyword(current, "TRUEPREDICATE") { position += 1; return .constant(true) }
        if isKeyword(current, "FALSEPREDICATE") { position += 1; return .constant(false) }
        return try parseComparison()
    }

    private mutating func parseComparison() throws -> _PredicateNode {
        var modifier = NSComparisonPredicate.Modifier.direct
        var none = false
        if isKeyword(current, "ANY", "SOME") { modifier = .any; position += 1 }
        else if isKeyword(current, "ALL") { modifier = .all; position += 1 }
        else if isKeyword(current, "NONE") { modifier = .any; none = true; position += 1 }
        let lhs = try parseExpression()
        var negate = false
        if isKeyword(current, "NOT") { negate = true; position += 1 }
        guard let token = current else { throw _PredicateParseError(description: "expected an operator") }
        position += 1
        let op: NSComparisonPredicate.Operator
        switch token {
        case .symbol("="), .symbol("=="): op = .equalTo
        case .symbol("!="), .symbol("<>"): op = .notEqualTo
        case .symbol("<"): op = .lessThan
        case .symbol("<="), .symbol("=<"): op = .lessThanOrEqualTo
        case .symbol(">"): op = .greaterThan
        case .symbol(">="), .symbol("=>"): op = .greaterThanOrEqualTo
        case .word(let word):
            switch word.uppercased() {
            case "CONTAINS": op = .contains
            case "BEGINSWITH": op = .beginsWith
            case "ENDSWITH": op = .endsWith
            case "LIKE": op = .like
            case "MATCHES": op = .matches
            case "IN": op = .in
            case "BETWEEN": op = .between
            default: throw _PredicateParseError(description: "unknown operator \(word)")
            }
        default: throw _PredicateParseError(description: "unexpected \(token)")
        }
        var options: NSComparisonPredicate.Options = []
        if case .flags(let flags)? = current {
            position += 1
            if flags.contains("c") { options.insert(.caseInsensitive) }
            if flags.contains("d") { options.insert(.diacriticInsensitive) }
            if flags.contains("n") { options.insert(.normalized) }
        }
        let rhs = try parseExpression()
        let node = _PredicateNode.comparison(lhs, op, rhs, modifier, options, negateAll: none)
        return negate ? .not(node) : node
    }

    // MARK: Expressions

    private mutating func nextArgument() throws -> Any? {
        guard argumentIndex < arguments.count else { throw _PredicateParseError(description: "too few arguments") }
        defer { argumentIndex += 1 }
        return _cdUnwrap(arguments[argumentIndex])
    }

    private mutating func parseExpression() throws -> NSExpression {
        guard let token = current else { throw _PredicateParseError(description: "expected an expression") }
        position += 1
        switch token {
        case .string(let s): return NSExpression(forConstantValue: s)
        case .number(let n):
            if let i = Int(n) { return NSExpression(forConstantValue: i) }
            return NSExpression(forConstantValue: Double(n) ?? 0)
        case .variable(let name): return NSExpression(forVariable: name)
        case .argument(let conversion):
            let value = try nextArgument()
            switch conversion {
            case "K": return NSExpression(forKeyPath: _cdString(value) ?? "\(value ?? "")")
            case "@": return NSExpression(forConstantValue: value)
            case "d", "i", "u", "D", "U", "o", "x", "X", "c", "C": return NSExpression(forConstantValue: _cdInt64(value).map { Int($0) } ?? value)
            case "f", "g", "e", "F", "G", "E", "a", "A": return NSExpression(forConstantValue: _cdDouble(value) ?? value)
            default: return NSExpression(forConstantValue: value)
            }
        case .symbol("{"):
            var items: [NSExpression] = []
            while current != .symbol("}") {
                items.append(try parseExpression())
                if current == .symbol(",") { position += 1 } else { break }
            }
            try expect("}")
            return NSExpression(forAggregate: items)
        case .word(let word):
            switch word.uppercased() {
            case "NIL", "NULL": return NSExpression(forConstantValue: nil)
            case "YES", "TRUE": return NSExpression(forConstantValue: true)
            case "NO", "FALSE": return NSExpression(forConstantValue: false)
            case "SELF": return .expressionForEvaluatedObject()
            default:
                if current == .symbol("(") {
                    // A function: `now()`, `lowercase(name)`.
                    position += 1
                    var args: [NSExpression] = []
                    while current != .symbol(")") {
                        args.append(try parseExpression())
                        if current == .symbol(",") { position += 1 } else { break }
                    }
                    try expect(")")
                    return NSExpression(forFunction: word + (args.isEmpty ? "" : ":"), arguments: args)
                }
                let path = word.hasPrefix("SELF.") ? String(word.dropFirst(5)) : word
                return NSExpression(forKeyPath: path)
            }
        default:
            throw _PredicateParseError(description: "unexpected \(token)")
        }
    }
}

// MARK: - NSSortDescriptor

/// An immutable description of how to order a collection of objects by a property they share.
open class NSSortDescriptor: CustomStringConvertible, Hashable, @unchecked Sendable {
    private let _key: String?
    /// The Swift key path the descriptor was made with, when it was.
    public let keyPath: AnyKeyPath?
    private let rootType: Any.Type?
    public let ascending: Bool
    private let comparator: ((Any, Any) -> ComparisonResult)?
    private let read: ((Any) -> Any?)?

    public init(key: String?, ascending: Bool) {
        _key = key; keyPath = nil; rootType = nil; self.ascending = ascending; comparator = nil; read = nil
    }

    public init(key: String?, ascending: Bool, comparator cmptr: @escaping (Any, Any) -> ComparisonResult) {
        _key = key; keyPath = nil; rootType = nil; self.ascending = ascending; comparator = cmptr; read = nil
    }

    public init<Root, Value>(keyPath: KeyPath<Root, Value>, ascending: Bool) {
        _key = nil; self.keyPath = keyPath; rootType = Root.self; self.ascending = ascending; comparator = nil
        read = { ($0 as? Root)?[keyPath: keyPath] }
    }

    public init<Root, Value>(keyPath: KeyPath<Root, Value>, ascending: Bool, comparator cmptr: @escaping (Any, Any) -> ComparisonResult) {
        _key = nil; self.keyPath = keyPath; rootType = Root.self; self.ascending = ascending; comparator = cmptr
        read = { ($0 as? Root)?[keyPath: keyPath] }
    }

    private init(copying other: NSSortDescriptor, ascending: Bool) {
        _key = other._key; keyPath = other.keyPath; rootType = other.rootType; self.ascending = ascending
        comparator = other.comparator; read = other.read
    }

    /// The property key the descriptor sorts by (for a key path into a generated entity class,
    /// the attribute's name).
    public var key: String? {
        if let _key { return _key }
        guard let keyPath, let rootType else { return nil }
        return NSManagedObject._key(for: keyPath, in: rootType)
    }

    /// The descriptor with the opposite order.
    public var reversedSortDescriptor: Any { NSSortDescriptor(copying: self, ascending: !ascending) }

    /// How the two objects order under this descriptor.
    open func compare(_ object1: Any, to object2: Any) -> ComparisonResult {
        let a = value(of: object1), b = value(of: object2)
        let result: ComparisonResult
        if let comparator, let x = _cdUnwrap(a), let y = _cdUnwrap(b) {
            result = comparator(x, y)
        } else {
            switch (_cdUnwrap(a), _cdUnwrap(b)) {
            case (nil, nil): result = .orderedSame
            case (nil, _): result = .orderedAscending
            case (_, nil): result = .orderedDescending
            default: result = _cdCompare(a, b) ?? .orderedSame
            }
        }
        guard !ascending else { return result }
        switch result {
        case .orderedAscending: return .orderedDescending
        case .orderedDescending: return .orderedAscending
        case .orderedSame: return .orderedSame
        }
    }

    private func value(of object: Any) -> Any? {
        if let read { return read(object) }
        guard let key = _key else { return object }
        return _cdValue(of: object, keyPath: key)
    }

    /// Sorts the objects by the descriptors, the first deciding first.
    static func _sort(_ objects: [Any], by descriptors: [NSSortDescriptor]) -> [Any] {
        guard !descriptors.isEmpty else { return objects }
        // A stable sort: equal objects keep their order.
        return objects.enumerated().sorted { lhs, rhs in
            for descriptor in descriptors {
                switch descriptor.compare(lhs.element, to: rhs.element) {
                case .orderedAscending: return true
                case .orderedDescending: return false
                case .orderedSame: continue
                }
            }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    public static func == (lhs: NSSortDescriptor, rhs: NSSortDescriptor) -> Bool {
        lhs.key == rhs.key && lhs.ascending == rhs.ascending && lhs.keyPath == rhs.keyPath
    }
    public func hash(into hasher: inout Hasher) { hasher.combine(key); hasher.combine(ascending) }
    open var description: String { "(\(key ?? "self"), \(ascending ? "ascending" : "descending"))" }
}

extension Array {
    /// The elements sorted by the descriptors (`NSArray.sortedArray(using:)`).
    public func sortedArray(using sortDescriptors: [NSSortDescriptor]) -> [Any] { NSSortDescriptor._sort(self, by: sortDescriptors) }
    /// The elements the predicate accepts (`NSArray.filtered(using:)`).
    public func filtered(using predicate: NSPredicate) -> [Any] { filter { predicate.evaluate(with: $0) } }
}
