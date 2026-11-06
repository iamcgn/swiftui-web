// Apple's `SystemConfiguration` module for wasm: network reachability (Alamofire's
// `NetworkReachabilityManager`). The browser knows one thing, whether it is online
// (`navigator.onLine`), so every target, a host name or an address, is reachable exactly when the
// page is online, and a target with a callback and a queue hears each change of that state.
#if os(WASI)
@_exported import CoreFoundation
import WebFoundation
import WASILibc

public struct SCNetworkReachabilityFlags: OptionSet, Hashable, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let transientConnection = SCNetworkReachabilityFlags(rawValue: 1 << 0)
    public static let reachable = SCNetworkReachabilityFlags(rawValue: 1 << 1)
    public static let connectionRequired = SCNetworkReachabilityFlags(rawValue: 1 << 2)
    public static let connectionOnTraffic = SCNetworkReachabilityFlags(rawValue: 1 << 3)
    public static let interventionRequired = SCNetworkReachabilityFlags(rawValue: 1 << 4)
    public static let connectionOnDemand = SCNetworkReachabilityFlags(rawValue: 1 << 5)
    public static let isLocalAddress = SCNetworkReachabilityFlags(rawValue: 1 << 16)
    public static let isDirect = SCNetworkReachabilityFlags(rawValue: 1 << 17)
    public static let isWWAN = SCNetworkReachabilityFlags(rawValue: 1 << 18)
    public static let connectionAutomatic = connectionOnTraffic
}

/// Called with the target, its new flags and the context's `info`.
public typealias SCNetworkReachabilityCallBack = (SCNetworkReachability, SCNetworkReachabilityFlags, UnsafeMutableRawPointer?) -> Void

/// What a callback is handed, and how its `info` is retained and released.
public struct SCNetworkReachabilityContext {
    public var version: CFIndex
    public var info: UnsafeMutableRawPointer?
    public var retain: ((UnsafeRawPointer) -> UnsafeRawPointer)?
    public var release: ((UnsafeRawPointer) -> Void)?
    public var copyDescription: ((UnsafeRawPointer) -> Unmanaged<AnyObject>)?

    public init() { version = 0 }
    public init(version: CFIndex, info: UnsafeMutableRawPointer?, retain: ((UnsafeRawPointer) -> UnsafeRawPointer)?,
                release: ((UnsafeRawPointer) -> Void)?, copyDescription: ((UnsafeRawPointer) -> Unmanaged<AnyObject>)?) {
        self.version = version
        self.info = info
        self.retain = retain
        self.release = release
        self.copyDescription = copyDescription
    }
}

/// A host name or address whose reachability is watched.
public final class SCNetworkReachability: Hashable, @unchecked Sendable {
    let name: String?
    var callback: SCNetworkReachabilityCallBack?
    var context = SCNetworkReachabilityContext()
    var queue: DispatchQueue?
    var observer: Int?

    init(name: String?) { self.name = name }
    deinit { stop() }

    var flags: SCNetworkReachabilityFlags { _WebNetworkStatus.online ? .reachable : [] }

    /// Listens while there is both a callback and a queue.
    func update() {
        if callback != nil, queue != nil {
            guard observer == nil else { return }
            observer = _WebNetworkStatus.addObserver { [weak self] in self?.notify() }
        } else {
            stop()
        }
    }

    private func stop() {
        if let observer { _WebNetworkStatus.removeObserver(observer) }
        observer = nil
    }

    private func notify() {
        guard let callback, let queue else { return }
        let info = context.info
        nonisolated(unsafe) let call = { callback(self, self.flags, info) }
        queue.async { call() }
    }

    public static func == (lhs: SCNetworkReachability, rhs: SCNetworkReachability) -> Bool { lhs === rhs }
    public func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}

public func SCNetworkReachabilityCreateWithName(_ allocator: CFAllocator?, _ nodename: UnsafePointer<CChar>) -> SCNetworkReachability? {
    SCNetworkReachability(name: String(cString: nodename))
}

public func SCNetworkReachabilityCreateWithAddress(_ allocator: CFAllocator?, _ address: UnsafePointer<sockaddr>) -> SCNetworkReachability? {
    SCNetworkReachability(name: nil)
}

public func SCNetworkReachabilityCreateWithAddressPair(_ allocator: CFAllocator?, _ localAddress: UnsafePointer<sockaddr>?,
                                                       _ remoteAddress: UnsafePointer<sockaddr>?) -> SCNetworkReachability? {
    SCNetworkReachability(name: nil)
}

/// Reachable when the browser is online.
public func SCNetworkReachabilityGetFlags(_ target: SCNetworkReachability, _ flags: UnsafeMutablePointer<SCNetworkReachabilityFlags>) -> Bool {
    flags.pointee = target.flags
    return true
}

/// Sets or clears the callback; the context's `info` is retained while it is set.
public func SCNetworkReachabilitySetCallback(_ target: SCNetworkReachability, _ callout: SCNetworkReachabilityCallBack?,
                                             _ context: UnsafeMutablePointer<SCNetworkReachabilityContext>?) -> Bool {
    if let info = target.context.info { target.context.release?(UnsafeRawPointer(info)) }
    target.context = SCNetworkReachabilityContext()
    target.callback = callout
    if callout != nil, var given = context?.pointee {
        if let info = given.info, let retain = given.retain { given.info = UnsafeMutableRawPointer(mutating: retain(UnsafeRawPointer(info))) }
        target.context = given
    }
    target.update()
    return true
}

/// The queue callbacks run on; nil stops them.
public func SCNetworkReachabilitySetDispatchQueue(_ target: SCNetworkReachability, _ queue: DispatchQueue?) -> Bool {
    target.queue = queue
    target.update()
    return true
}
#endif
