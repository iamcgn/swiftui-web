public struct Logger { public init() {} public func info(_ s: String) { print(s) } }
public func os_log(_ s: StaticString) { print(s) }
