public struct URL { public init() {} }
public struct Date { public init() {}; public static var now: Date { Date() } }
public protocol EProto {}
public func eFunc() -> Int { 1 }
extension Int { public var eMember: Int { self + 1 } }
infix operator <~>: AdditionPrecedence
public func <~> (a: Int, b: Int) -> Int { a + b }
public struct EOp { public init() {}; public static func <~> (a: EOp, b: EOp) -> EOp { a } }
