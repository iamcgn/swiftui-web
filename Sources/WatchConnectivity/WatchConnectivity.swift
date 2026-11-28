// Watch Connectivity on the web (OscarWeather's unit sync with its watch app): a page has no
// paired Apple Watch, so `WCSession.isSupported()` answers false, as on an iPad. An app that asks
// for the default session anyway gets one that is never activated: activating it tells the
// delegate it finished in the not-activated state with a not-supported error, messages fail as
// unreachable, and the application context can't be updated.
#if os(WASI)
@_exported import WebFoundation
#else
import Foundation
#endif

/// Watch Connectivity's errors (`WCErrorDomain`), with the codes Apple's have.
public struct WCError: Error, Hashable, Sendable, CustomStringConvertible {
    public enum Code: Int, Sendable {
        case genericError = 7001
        case sessionNotSupported = 7002
        case sessionMissingDelegate = 7003
        case sessionNotActivated = 7004
        case deviceNotPaired = 7005
        case watchAppNotInstalled = 7006
        case notReachable = 7007
        case invalidParameter = 7008
        case payloadTooLarge = 7009
        case payloadUnsupportedTypes = 7010
        case messageReplyFailed = 7011
        case messageReplyTimedOut = 7012
        case fileAccessDenied = 7013
        case deliveryFailed = 7014
        case insufficientSpace = 7015
        case sessionInactive = 7016
        case transferTimedOut = 7017
        case companionAppNotInstalled = 7018
        case watchOnlyApp = 7019
    }
    public static let errorDomain = "WCErrorDomain"
    public let code: Code
    public init(_ code: Code) { self.code = code }

    public static var genericError: Code { .genericError }
    public static var sessionNotSupported: Code { .sessionNotSupported }
    public static var sessionNotActivated: Code { .sessionNotActivated }
    public static var deviceNotPaired: Code { .deviceNotPaired }
    public static var watchAppNotInstalled: Code { .watchAppNotInstalled }
    public static var notReachable: Code { .notReachable }

    public var errorCode: Int { code.rawValue }
    public var description: String {
        switch code {
        case .sessionNotSupported: return "Watch Connectivity isn't supported on the web: there is no paired Apple Watch."
        case .notReachable: return "The paired Apple Watch isn't reachable."
        case .sessionNotActivated: return "The Watch Connectivity session isn't activated."
        default: return "Watch Connectivity error \(code.rawValue)."
        }
    }
    public var localizedDescription: String { description }
}

public let WCErrorDomain = WCError.errorDomain

/// Where a session's activation stands.
public enum WCSessionActivationState: Int, Sendable {
    case notActivated = 0
    case inactive = 1
    case activated = 2
}

/// Hears a session's activation and what the watch sends. The activation and deactivation
/// methods are required, as on iOS; the rest have empty defaults, as Apple's are optional.
public protocol WCSessionDelegate: NSObjectProtocol {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?)
    func sessionDidBecomeInactive(_ session: WCSession)
    func sessionDidDeactivate(_ session: WCSession)
    func sessionWatchStateDidChange(_ session: WCSession)
    func sessionReachabilityDidChange(_ session: WCSession)
    func session(_ session: WCSession, didReceiveMessage message: [String: Any])
    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void)
    func session(_ session: WCSession, didReceiveMessageData messageData: Data)
    func session(_ session: WCSession, didReceiveMessageData messageData: Data, replyHandler: @escaping (Data) -> Void)
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any])
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any])
    func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: (any Error)?)
    func session(_ session: WCSession, didReceive file: WCSessionFile)
    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: (any Error)?)
}

extension WCSessionDelegate {
    public func sessionWatchStateDidChange(_ session: WCSession) {}
    public func sessionReachabilityDidChange(_ session: WCSession) {}
    public func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {}
    public func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {}
    public func session(_ session: WCSession, didReceiveMessageData messageData: Data) {}
    public func session(_ session: WCSession, didReceiveMessageData messageData: Data, replyHandler: @escaping (Data) -> Void) {}
    public func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {}
    public func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {}
    public func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: (any Error)?) {}
    public func session(_ session: WCSession, didReceive file: WCSessionFile) {}
    public func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: (any Error)?) {}
}

/// A file the watch sent.
open class WCSessionFile: NSObject, @unchecked Sendable {
    open var fileURL: URL
    open var metadata: [String: Any]?
    init(fileURL: URL, metadata: [String: Any]?) {
        self.fileURL = fileURL
        self.metadata = metadata
    }
}

/// A file on its way to the watch. With no watch it never leaves.
open class WCSessionFileTransfer: NSObject, @unchecked Sendable {
    open var file: WCSessionFile
    open var progress: Progress
    open var isTransferring: Bool { false }
    init(file: WCSessionFile) {
        self.file = file
        progress = Progress(totalUnitCount: 1)
    }
    open func cancel() {}
}

/// User info on its way to the watch. With no watch it never leaves.
open class WCSessionUserInfoTransfer: NSObject, @unchecked Sendable {
    open var isCurrentComplicationInfo: Bool
    open var userInfo: [String: Any]
    open var isTransferring: Bool { false }
    init(userInfo: [String: Any], isCurrentComplicationInfo: Bool) {
        self.userInfo = userInfo
        self.isCurrentComplicationInfo = isCurrentComplicationInfo
    }
    open func cancel() {}
}

/// The app's link to its watch app. A page has no paired watch, so the session is never activated.
open class WCSession: NSObject, @unchecked Sendable {
    private static let shared = WCSession()

    /// Whether this device can talk to a watch: never on the web.
    open class func isSupported() -> Bool { false }

    /// The app's one session.
    open class var `default`: WCSession { shared }

    open weak var delegate: (any WCSessionDelegate)?

    open var activationState: WCSessionActivationState { .notActivated }
    open var isPaired: Bool { false }
    open var isWatchAppInstalled: Bool { false }
    open var isComplicationEnabled: Bool { false }
    open var remainingComplicationUserInfoTransfers: Int { 0 }
    open var watchDirectoryURL: URL? { nil }
    open var isReachable: Bool { false }
    open var iOSDeviceNeedsUnlockAfterRebootForReachability: Bool { false }
    open var hasContentPending: Bool { false }
    open private(set) var applicationContext: [String: Any] = [:]
    open var receivedApplicationContext: [String: Any] { [:] }
    open var outstandingUserInfoTransfers: [WCSessionUserInfoTransfer] { [] }
    open var outstandingFileTransfers: [WCSessionFileTransfer] { [] }

    /// Starts activating. The delegate hears, on the main queue, that activation finished in the
    /// not-activated state, with a not-supported error.
    open func activate() {
        DispatchQueue.main.async { [self] in
            delegate?.session(self, activationDidCompleteWith: .notActivated, error: WCError(.sessionNotSupported))
        }
    }

    /// Sends a message to the watch: it is never reachable, so the error handler hears that.
    open func sendMessage(_ message: [String: Any], replyHandler: (([String: Any]) -> Void)?, errorHandler: ((any Error) -> Void)? = nil) {
        errorHandler?(WCError(.notReachable))
    }

    open func sendMessageData(_ data: Data, replyHandler: ((Data) -> Void)?, errorHandler: ((any Error) -> Void)? = nil) {
        errorHandler?(WCError(.notReachable))
    }

    /// Replaces the context the watch reads: throws, as the session is never activated.
    open func updateApplicationContext(_ applicationContext: [String: Any]) throws {
        throw WCError(.sessionNotActivated)
    }

    /// Queues user info for the watch; with no watch it stays queued and is never delivered.
    @discardableResult
    open func transferUserInfo(_ userInfo: [String: Any] = [:]) -> WCSessionUserInfoTransfer {
        WCSessionUserInfoTransfer(userInfo: userInfo, isCurrentComplicationInfo: false)
    }

    @discardableResult
    open func transferCurrentComplicationUserInfo(_ userInfo: [String: Any] = [:]) -> WCSessionUserInfoTransfer {
        WCSessionUserInfoTransfer(userInfo: userInfo, isCurrentComplicationInfo: true)
    }

    /// Queues a file for the watch; with no watch it is never delivered.
    @discardableResult
    open func transferFile(_ file: URL, metadata: [String: Any]?) -> WCSessionFileTransfer {
        WCSessionFileTransfer(file: WCSessionFile(fileURL: file, metadata: metadata))
    }
}
