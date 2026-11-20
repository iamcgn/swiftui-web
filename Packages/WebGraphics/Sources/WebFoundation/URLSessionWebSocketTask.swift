// URLSessionWebSocketTask over the browser's WebSocket (SwiftUIWebCanvas/NetworkHost.swift):
// ATProtoKit's firehose (IcySky) and other live feeds open one with
// `URLSession.webSocketTask(with:)`, resume it, `receive()` message after message and close it
// with `cancel(with:reason:)`. The semantics an app relies on, as Foundation's:
//
// - sends made before the socket opens wait and go out once it opens, in order;
// - each received message answers one `receive`, oldest first; messages that arrive with no
//   `receive` waiting are kept for the next ones;
// - once the socket has closed, a waiting or later `receive` and a later `send` fail with
//   POSIX error 57 ("Socket is not connected"), or with the URLError that ended it;
// - a message larger than `maximumMessageSize` closes the socket with `.messageTooBig`;
// - the delegate hears `didOpenWithProtocol`, `didCloseWith` (a close the server answered)
//   and `didCompleteWithError`.
//
// The browser's WebSocket sends no headers but the subprotocols, so a request's other header
// fields are not sent; it closes only with code 1000 or 3000...4999, so another code an app
// closes with goes to the server as 1000 (the task's `closeCode` is still the app's); and it
// answers the server's pings itself, so `sendPing` reports a pong at once while the socket is
// open.

// MARK: - The host

/// A message as the host sends or reads it.
public enum _WebSocketFrame: Sendable, Equatable {
    case text(String)
    case binary([UInt8])
}

/// What the host reports about one socket.
public struct _WebSocketEvents: Sendable {
    /// The socket opened; the subprotocol the server picked ("" for none).
    public var opened: @Sendable (String) -> Void
    public var received: @Sendable (_WebSocketFrame) -> Void
    /// The socket closed: the code, the reason, and whether the close handshake completed.
    public var closed: @Sendable (Int, String, Bool) -> Void
    /// The socket failed (before `closed`), with the browser's reason.
    public var failed: @Sendable (String) -> Void
    public init(opened: @escaping @Sendable (String) -> Void, received: @escaping @Sendable (_WebSocketFrame) -> Void,
                closed: @escaping @Sendable (Int, String, Bool) -> Void, failed: @escaping @Sendable (String) -> Void) {
        self.opened = opened; self.received = received; self.closed = closed; self.failed = failed
    }
}

/// An open socket at the host.
public protocol _WebSocketConnection: AnyObject {
    /// Sends a frame; false when the socket is not open.
    func send(_ frame: _WebSocketFrame) -> Bool
    func close(code: Int, reason: String)
}

/// The host hook: opens a socket to `url` asking for `protocols`, reporting to `events`; nil
/// when the host cannot open one (the address is not one it takes).
public enum _WebSocketHost {
    nonisolated(unsafe) public static var open: ((_ url: String, _ protocols: [String], _ events: _WebSocketEvents) -> (any _WebSocketConnection)?)?
}

#if os(WASI)
/// A task that exchanges messages with a server over a WebSocket.
open class URLSessionWebSocketTask: URLSessionTask, @unchecked Sendable {
    public enum Message: Sendable {
        case data(Data)
        case string(String)
    }

    // `@objc` with the runtime, as the delegate method that takes it is.
    #if canImport(ObjectiveC)
    @objc public enum CloseCode: Int, Sendable {
        case invalid = 0
        case normalClosure = 1000
        case goingAway = 1001
        case protocolError = 1002
        case unsupportedData = 1003
        case noStatusReceived = 1005
        case abnormalClosure = 1006
        case invalidFramePayloadData = 1007
        case policyViolation = 1008
        case messageTooBig = 1009
        case mandatoryExtensionMissing = 1010
        case internalServerError = 1011
        case tlsHandshakeFailure = 1015
    }
    #else
    public enum CloseCode: Int, Sendable {
        case invalid = 0
        case normalClosure = 1000
        case goingAway = 1001
        case protocolError = 1002
        case unsupportedData = 1003
        case noStatusReceived = 1005
        case abnormalClosure = 1006
        case invalidFramePayloadData = 1007
        case policyViolation = 1008
        case messageTooBig = 1009
        case mandatoryExtensionMissing = 1010
        case internalServerError = 1011
        case tlsHandshakeFailure = 1015
    }
    #endif

    /// The largest message `receive` takes (1 MiB, Foundation's default).
    open var maximumMessageSize = 1_048_576
    /// The code the socket closed with: the app's, or the server's (`.invalid` while open).
    public private(set) var closeCode: CloseCode = .invalid
    /// The reason the socket closed with, nil when none was given.
    public private(set) var closeReason: Data?

    private weak var session: URLSession?
    private let protocols: [String]
    private var connection: (any _WebSocketConnection)?
    private var isOpen = false
    /// Sends and pings made before the socket opened.
    private var waiting: [() -> Void] = []
    private var inbox: [Message] = []
    private var receivers: [@Sendable (Result<Message, Error>) -> Void] = []
    /// Set once the socket has ended: what a later send or receive fails with.
    private var ending: Error?

    init(identifier: Int, request: URLRequest, protocols: [String], session: URLSession) {
        self.protocols = protocols
        self.session = session
        nonisolated(unsafe) var made: URLSessionWebSocketTask?
        super.init(identifier: identifier, request: request) {
            made?.open()
            return _WebURLSession.Task(identifier: identifier) { outcome in
                if case .failure(.cancelled) = outcome { made?.end(error: URLError(.cancelled), closing: 1000, reason: "") }
            }
        }
        made = self
    }

    // MARK: Sending and receiving

    public func send(_ message: Message, completionHandler: @escaping @Sendable (Error?) -> Void) {
        if let ending { completionHandler(ending); return }
        guard isOpen, let connection else {
            waiting.append { [weak self] in self?.send(message, completionHandler: completionHandler) }
            return
        }
        let frame: _WebSocketFrame
        switch message {
        case .data(let data): frame = .binary(Array(data))
        case .string(let string): frame = .text(string)
        }
        completionHandler(connection.send(frame) ? nil : Self.notConnected)
    }

    public func send(_ message: Message) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            send(message) { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }

    public func receive(completionHandler: @escaping @Sendable (Result<Message, Error>) -> Void) {
        if !inbox.isEmpty { completionHandler(.success(inbox.removeFirst())); return }
        if let ending { completionHandler(.failure(ending)); return }
        receivers.append(completionHandler)
    }

    public func receive() async throws -> Message {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Message, Error>) in
            receive { continuation.resume(with: $0) }
        }
    }

    /// Reports the server's pong: at once while the socket is open (the browser answers pings
    /// and sends none of its own), once it opens before then, and the error once it has ended.
    public func sendPing(pongReceiveHandler: @escaping @Sendable (Error?) -> Void) {
        if let ending { pongReceiveHandler(ending); return }
        guard isOpen else {
            waiting.append { [weak self] in self?.sendPing(pongReceiveHandler: pongReceiveHandler) }
            return
        }
        pongReceiveHandler(nil)
    }

    /// Closes the socket with `closeCode` and `reason`; the task completes.
    public func cancel(with closeCode: CloseCode, reason: Data?) {
        guard ending == nil else { return }
        self.closeCode = closeCode
        closeReason = reason
        let code = closeCode.rawValue
        let sent = code == 1000 || (3000...4999).contains(code) ? code : 1000
        // The browser takes a reason of at most 123 UTF-8 bytes; it is cut at a whole scalar, so a
        // character split at the limit isn't turned into a three-byte replacement that overruns it.
        var text = ""
        var bytes = 0
        for scalar in reason.map({ String(decoding: $0, as: UTF8.self) })?.unicodeScalars ?? "".unicodeScalars {
            let width = UTF8.width(scalar)
            if bytes + width > 123 { break }
            bytes += width
            text.unicodeScalars.append(scalar)
        }
        end(error: nil, closing: sent, reason: text)
    }

    /// Cancels the task. One cancelled before it was resumed never opens, so it ends at once, and
    /// a send, receive or ping made on it fails as cancelled, as Foundation's does.
    public override func cancel() {
        let unstarted = core == nil
        super.cancel()
        if unstarted, ending == nil, state == .completed { end(error: URLError(.cancelled), closing: nil, reason: "") }
    }

    // MARK: The socket

    private static let notConnected = NSError(domain: NSPOSIXErrorDomain, code: 57,
                                              userInfo: [NSLocalizedDescriptionKey: "Socket is not connected"])

    private func open() {
        guard let url = currentRequest?.url, let address = Self.socketAddress(url) else {
            end(error: URLError(.badURL), closing: nil, reason: "")
            return
        }
        guard let host = _WebSocketHost.open else {
            end(error: URLError(.cannotConnectToHost, reason: "no network host"), closing: nil, reason: "")
            return
        }
        let events = _WebSocketEvents(
            opened: { [weak self] chosen in self?.opened(chosen) },
            received: { [weak self] frame in self?.received(frame) },
            closed: { [weak self] code, reason, clean in self?.closed(code: code, reason: reason, clean: clean) },
            failed: { [weak self] reason in self?.failed(reason) })
        connection = host(address, protocols, events)
        if connection == nil { end(error: URLError(.badURL), closing: nil, reason: "") }
    }

    /// The ws or wss address of `url` (http and https are taken as ws and wss).
    static func socketAddress(_ url: URL) -> String? {
        let address = url.absoluteString
        switch url.scheme?.lowercased() {
        case "ws", "wss": return address
        case "http": return "ws" + address.dropFirst(4)
        case "https": return "wss" + address.dropFirst(5)
        default: return nil
        }
    }

    private var failure: String?

    private func opened(_ chosen: String) {
        guard ending == nil else { return }
        isOpen = true
        if let url = currentRequest?.url {
            response = HTTPURLResponse(url: url, statusCode: 101, httpVersion: "HTTP/1.1",
                                       headerFields: chosen.isEmpty ? [:] : ["Sec-WebSocket-Protocol": chosen])
        }
        if let session, let delegate = session._asWebSocket(session._delegate) {
            session._tellOpened(delegate, self, chosen.isEmpty ? nil : chosen)
        }
        let queued = waiting
        waiting = []
        for each in queued { each() }
    }

    private func received(_ frame: _WebSocketFrame) {
        guard ending == nil else { return }
        let message: Message
        let size: Int
        switch frame {
        case .text(let text): message = .string(text); size = text.utf8.count
        case .binary(let bytes): message = .data(Data(bytes)); size = bytes.count
        }
        guard size <= maximumMessageSize else {
            closeCode = .messageTooBig
            end(error: NSError(domain: NSPOSIXErrorDomain, code: 40, userInfo: [NSLocalizedDescriptionKey: "Message too long"]),
                closing: 1000, reason: "")
            return
        }
        if receivers.isEmpty { inbox.append(message) } else { receivers.removeFirst()(.success(message)) }
    }

    private func failed(_ reason: String) { failure = reason }

    private func closed(code: Int, reason: String, clean: Bool) {
        guard ending == nil else { return }
        closeCode = CloseCode(rawValue: code) ?? .invalid
        closeReason = reason.isEmpty ? nil : Data(reason.utf8)
        if clean, let session, let delegate = session._asWebSocket(session._delegate) {
            session._tellClosed(delegate, self, closeCode, closeReason)
        }
        let error: Error?
        if clean {
            error = nil
        } else if !isOpen {
            error = URLError(.cannotConnectToHost, reason: failure ?? "the WebSocket could not be opened")
        } else {
            error = URLError(.networkConnectionLost, reason: failure ?? "the WebSocket closed with code \(code)")
        }
        end(error: error, closing: nil, reason: "")
    }

    /// Ends the task: closes the socket (when `closing` gives the code), fails what waits, and
    /// tells the delegate the task completed with `error`.
    private func end(error: Error?, closing code: Int?, reason: String) {
        guard ending == nil else { return }
        ending = error ?? Self.notConnected
        isOpen = false
        if let code { connection?.close(code: code, reason: reason) }
        connection = nil
        finished(response: response, error: error)
        let failing = ending!
        let waiters = receivers
        receivers = []
        let queued = waiting
        waiting = []
        for each in queued { each() }   // each fails with `ending`
        for receiver in waiters { receiver(.failure(failing)) }
        if let session, let delegate = session._asTask(session._delegate) {
            session._tellComplete(delegate, self, error)
        }
    }
}

extension URLSession {
    public func webSocketTask(with url: URL) -> URLSessionWebSocketTask {
        webSocketTask(with: URLRequest(url: url), protocols: [])
    }

    public func webSocketTask(with url: URL, protocols: [String]) -> URLSessionWebSocketTask {
        webSocketTask(with: URLRequest(url: url), protocols: protocols)
    }

    /// A task for `request`: its URL, and the subprotocols its Sec-WebSocket-Protocol field
    /// lists (the browser sends no other header).
    public func webSocketTask(with request: URLRequest) -> URLSessionWebSocketTask {
        let field = request.value(forHTTPHeaderField: "Sec-WebSocket-Protocol") ?? ""
        let protocols = field.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return webSocketTask(with: request, protocols: protocols)
    }

    private func webSocketTask(with request: URLRequest, protocols: [String]) -> URLSessionWebSocketTask {
        let identifier = nextTaskIdentifier
        nextTaskIdentifier += 1
        let task = URLSessionWebSocketTask(identifier: identifier, request: request, protocols: protocols, session: self)
        _tellCreated(task)
        return task
    }
}
#endif
