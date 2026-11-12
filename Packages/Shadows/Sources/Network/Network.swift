// Apple's `Network` module for wasm: the path monitor apps watch connectivity with
// (`NWPathMonitor`, CriticalMaps, Gem, CloudKitSyncMonitor). The browser knows one thing, whether
// it is online (`navigator.onLine`, WebFoundation's `_WebNetworkStatus`), so a path is satisfied
// exactly when the page is online, over an unnamed wired interface (a page cannot tell Wi-Fi from
// cellular), neither expensive nor constrained. A started monitor hears each online or offline
// change on its queue, and the current path once at start, as Apple's does.
// Connections and listeners (`NWConnection`, `NWListener`) need sockets a page does not have; they
// are not here.
#if os(WASI)
import WebFoundation

/// A network interface a path can use.
public struct NWInterface: Hashable, Sendable, CustomDebugStringConvertible {
    /// The kinds of interface.
    public enum InterfaceType: Hashable, Sendable {
        case other, wifi, cellular, wiredEthernet, loopback
    }

    public let type: InterfaceType
    public let name: String
    public let index: Int

    public var debugDescription: String { name }
}

/// The state of the network, as a path monitor reports it.
public struct NWPath: Equatable, Sendable, CustomDebugStringConvertible {
    /// Whether a path can be used.
    public enum Status: Equatable, Sendable {
        case satisfied, unsatisfied, requiresConnection
    }

    /// Why a path is unsatisfied.
    public enum UnsatisfiedReason: Equatable, Sendable {
        case notAvailable, cellularDenied, wifiDenied, localNetworkDenied, vpnInactive
    }

    public let status: Status
    public let availableInterfaces: [NWInterface]
    /// A page's traffic is neither metered nor limited as far as it can tell.
    public let isExpensive: Bool
    public let isConstrained: Bool
    public let supportsIPv4: Bool
    public let supportsIPv6: Bool
    public let supportsDNS: Bool

    /// A page offline has no network: the one reason it can give.
    public var unsatisfiedReason: UnsatisfiedReason { .notAvailable }

    init(online: Bool, requiredType: NWInterface.InterfaceType?) {
        let interface = NWInterface(type: requiredType ?? .wiredEthernet, name: "web0", index: 1)
        status = online ? .satisfied : .unsatisfied
        availableInterfaces = online ? [interface] : []
        isExpensive = false
        isConstrained = false
        supportsIPv4 = online
        supportsIPv6 = online
        supportsDNS = online
    }

    /// Whether the path uses an interface of `type`.
    public func usesInterfaceType(_ type: NWInterface.InterfaceType) -> Bool {
        availableInterfaces.contains { $0.type == type }
    }

    public var debugDescription: String { status == .satisfied ? "satisfied (web0)" : "unsatisfied (offline)" }
}

/// Watches the network's state and reports each change of path.
public final class NWPathMonitor: @unchecked Sendable {
    private let requiredType: NWInterface.InterfaceType?
    private var observer: Int?
    public private(set) var queue: DispatchQueue?

    /// Called on the monitor's queue with each new path.
    public var pathUpdateHandler: (@Sendable (NWPath) -> Void)?

    public init() { requiredType = nil }

    public init(requiredInterfaceType: NWInterface.InterfaceType) { requiredType = requiredInterfaceType }

    public init(prohibitedInterfaceTypes: [NWInterface.InterfaceType]) { requiredType = nil }

    deinit { if let observer { _WebNetworkStatus.removeObserver(observer) } }

    /// The current path.
    public var currentPath: NWPath { NWPath(online: _WebNetworkStatus.online, requiredType: requiredType) }

    /// Starts reporting on `queue`: the current path first, then each change.
    public func start(queue: DispatchQueue) {
        guard observer == nil else { return }
        self.queue = queue
        observer = _WebNetworkStatus.addObserver { [weak self] in self?.notify() }
        notify()
    }

    /// Stops reporting; a cancelled monitor is not started again, as Apple's is not.
    public func cancel() {
        if let observer { _WebNetworkStatus.removeObserver(observer) }
        observer = nil
        queue = nil
    }

    private func notify() {
        guard let queue, let handler = pathUpdateHandler else { return }
        let path = currentPath
        queue.async { handler(path) }
    }
}

extension NWPathMonitor: AsyncSequence {
    public typealias Element = NWPath

    /// The paths as they change, starting with the current one.
    public struct AsyncIterator: AsyncIteratorProtocol {
        var stream: AsyncStream<NWPath>.Iterator
        public mutating func next() async -> NWPath? { await stream.next() }
    }

    public func makeAsyncIterator() -> AsyncIterator {
        let required = requiredType
        let stream = AsyncStream<NWPath> { continuation in
            continuation.yield(NWPath(online: _WebNetworkStatus.online, requiredType: required))
            let token = _WebNetworkStatus.addObserver {
                continuation.yield(NWPath(online: _WebNetworkStatus.online, requiredType: required))
            }
            continuation.onTermination = { _ in _WebNetworkStatus.removeObserver(token) }
        }
        return AsyncIterator(stream: stream.makeAsyncIterator())
    }
}
#endif
