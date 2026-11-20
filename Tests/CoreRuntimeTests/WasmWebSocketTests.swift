// URLSessionWebSocketTask (WebFoundation/URLSessionWebSocketTask.swift) over a host that opens,
// sends and closes when told: sends made before the socket opens go out once it does, messages
// answer `receive` oldest first, a close by the app or by the server ends the task, and the
// delegate hears each step, as ATProtoKit's firehose (IcySky) and other live feeds rely on.
#if os(WASI)
import Testing
import WebFoundation

@Suite(.serialized) struct WasmWebSocketTests {
    /// One socket at the fake host: what was sent, how it was closed, and its events to fire.
    final class Socket: _WebSocketConnection, @unchecked Sendable {
        let url: String
        let protocols: [String]
        let events: _WebSocketEvents
        var isOpen = false
        var sent: [_WebSocketFrame] = []
        var closedWith: (code: Int, reason: String)?
        init(url: String, protocols: [String], events: _WebSocketEvents) {
            self.url = url; self.protocols = protocols; self.events = events
        }
        func send(_ frame: _WebSocketFrame) -> Bool {
            guard isOpen else { return false }
            sent.append(frame)
            return true
        }
        func close(code: Int, reason: String) { closedWith = (code, reason); isOpen = false }
        func open(_ chosen: String = "") { isOpen = true; events.opened(chosen) }
    }

    final class Host: @unchecked Sendable {
        var sockets: [Socket] = []
        func install() {
            _WebSocketHost.open = { [self] url, protocols, events in
                let socket = Socket(url: url, protocols: protocols, events: events)
                sockets.append(socket)
                return socket
            }
        }
    }

    final class Listener: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {
        var heard: [String] = []
        func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
            heard.append("open \(`protocol` ?? "none")")
        }
        func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
                        reason: Data?) {
            heard.append("close \(closeCode.rawValue) \(reason.map { String(decoding: $0, as: UTF8.self) } ?? "none")")
        }
        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
            heard.append("complete \(error.map { "\(WasmWebSocketTests.code(of: $0) ?? 0)" } ?? "nil")")
        }
    }

    /// A URLError's code, or a POSIX error's.
    static func code(of error: any Error) -> Int? { (error as? URLError)?.errorCode ?? (error as? NSError)?.code }

    final class Box<Value>: @unchecked Sendable { var value: Value; init(_ value: Value) { self.value = value } }

    @Test func sendsWaitForTheSocketAndGoOutInOrder() {
        let host = Host(); host.install(); defer { _WebSocketHost.open = nil }
        let task = URLSession.shared.webSocketTask(with: URL(string: "wss://relay.example/xrpc/com.atproto.sync.subscribeRepos")!)
        let results = Box<[String]>([])
        task.send(.string("first")) { error in results.value.append(error == nil ? "sent" : "failed") }
        #expect(host.sockets.isEmpty && results.value.isEmpty && task.state == .suspended)

        task.resume()
        let socket = try! #require(host.sockets.first)
        #expect(socket.url == "wss://relay.example/xrpc/com.atproto.sync.subscribeRepos" && socket.protocols.isEmpty)
        #expect(results.value.isEmpty)
        socket.open()
        #expect(results.value == ["sent"] && socket.sent == [.text("first")] && task.state == .running)
        task.send(.data(Data([1, 2, 3]))) { error in results.value.append(error == nil ? "sent" : "failed") }
        #expect(socket.sent == [.text("first"), .binary([1, 2, 3])])
        #expect((task.response as? HTTPURLResponse)?.statusCode == 101)

        let pongs = Box(0)
        task.sendPing { error in if error == nil { pongs.value += 1 } }
        #expect(pongs.value == 1)
    }

    @Test func messagesAnswerReceivesOldestFirst() async throws {
        let host = Host(); host.install(); defer { _WebSocketHost.open = nil }
        let task = URLSession.shared.webSocketTask(with: URL(string: "wss://feed.example/live")!)
        task.resume()
        let socket = try #require(host.sockets.first)
        socket.open()
        socket.events.received(.text("one"))
        socket.events.received(.binary([7]))

        let got = Box<[String]>([])
        let record: @Sendable (Result<URLSessionWebSocketTask.Message, Error>) -> Void = { result in
            switch result {
            case .success(.string(let text)): got.value.append(text)
            case .success(.data(let data)): got.value.append("data \(Array(data))")
            case .failure: got.value.append("error")
            }
        }
        task.receive(completionHandler: record)
        task.receive(completionHandler: record)
        task.receive(completionHandler: record)
        #expect(got.value == ["one", "data [7]"])
        socket.events.received(.text("three"))
        #expect(got.value == ["one", "data [7]", "three"])

        socket.events.received(.text("four"))
        guard case .string(let text) = try await task.receive() else { Issue.record("not a string"); return }
        #expect(text == "four")
    }

    /// Hears only that a task was made.
    final class Creations: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {
        var made: [Int] = []
        func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) { made.append(task.taskIdentifier) }
    }

    @Test func everyFactoryTellsTheDelegateItMadeATask() {
        let creations = Creations()
        let session = URLSession(configuration: .default, delegate: creations, delegateQueue: nil)
        let url = URL(string: "wss://relay.example/stream")!
        let tasks = [session.webSocketTask(with: url), session.webSocketTask(with: url, protocols: ["chat"]),
                     session.webSocketTask(with: URLRequest(url: url))]
        #expect(creations.made == tasks.map(\.taskIdentifier))
    }

    @Test func anAppCloseEndsTheTask() {
        let host = Host(); host.install(); defer { _WebSocketHost.open = nil }
        let listener = Listener()
        let session = URLSession(configuration: .default, delegate: listener, delegateQueue: nil)
        let task = session.webSocketTask(with: URL(string: "https://relay.example/stream")!, protocols: ["chat", "v2"])
        task.resume()
        let socket = try! #require(host.sockets.first)
        #expect(socket.url == "wss://relay.example/stream" && socket.protocols == ["chat", "v2"])
        socket.open("v2")
        #expect(listener.heard == ["open v2"])
        #expect((task.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Sec-WebSocket-Protocol") == "v2")

        let waiting = Box<Int?>(nil)
        task.receive { result in if case .failure(let error) = result { waiting.value = Self.code(of: error) } }
        // Going away is not a code a browser closes with: the server is sent 1000, the task keeps the app's.
        task.cancel(with: .goingAway, reason: Data("bye".utf8))
        #expect(socket.closedWith?.code == 1000 && socket.closedWith?.reason == "bye")
        #expect(task.closeCode == .goingAway && task.closeReason == Data("bye".utf8) && task.state == .completed)
        #expect(waiting.value == 57 && listener.heard == ["open v2", "complete nil"])

        let later = Box<String?>(nil)
        task.send(.string("late")) { error in later.value = error.flatMap { ($0 as? NSError)?.domain } }
        #expect(later.value == NSPOSIXErrorDomain && socket.sent.isEmpty)

        // An application code goes to the server as it is.
        let second = session.webSocketTask(with: URL(string: "wss://relay.example/stream")!)
        second.resume()
        host.sockets[1].open()
        second.cancel(with: URLSessionWebSocketTask.CloseCode(rawValue: 1000)!, reason: nil)
        #expect(host.sockets[1].closedWith?.code == 1000 && host.sockets[1].closedWith?.reason == "" && second.closeReason == nil)
    }

    @Test func aServerCloseAndAFailure() {
        let host = Host(); host.install(); defer { _WebSocketHost.open = nil }
        let listener = Listener()
        let session = URLSession(configuration: .default, delegate: listener, delegateQueue: nil)
        var request = URLRequest(url: URL(string: "wss://relay.example/a")!)
        request.setValue("graphql-ws, json", forHTTPHeaderField: "Sec-WebSocket-Protocol")
        let task = session.webSocketTask(with: request)
        task.resume()
        let socket = try! #require(host.sockets.first)
        #expect(socket.protocols == ["graphql-ws", "json"])
        socket.open()
        socket.events.closed(1000, "done", true)
        #expect(task.closeCode == .normalClosure && task.closeReason == Data("done".utf8) && task.state == .completed)
        #expect(listener.heard == ["open none", "close 1000 done", "complete nil"])

        // The browser could not open the socket: an error event, then an unclean close.
        listener.heard = []
        let refused = session.webSocketTask(with: URL(string: "wss://down.example/")!)
        refused.resume()
        host.sockets[1].events.failed("refused")
        host.sockets[1].events.closed(1006, "", false)
        #expect((refused.error as? URLError)?.code == .cannotConnectToHost && refused.closeCode == .abnormalClosure)
        #expect(listener.heard == ["complete -1004"])
        let failed = Box<Int?>(nil)
        refused.receive { result in if case .failure(let error) = result { failed.value = (error as? URLError)?.errorCode } }
        #expect(failed.value == -1004)

        // An open socket dropped: the connection was lost.
        let dropped = session.webSocketTask(with: URL(string: "wss://relay.example/b")!)
        dropped.resume()
        host.sockets[2].open()
        host.sockets[2].events.closed(1006, "", false)
        #expect((dropped.error as? URLError)?.code == .networkConnectionLost)
    }

    @Test func limitsCancellingAndAddresses() {
        let host = Host(); host.install(); defer { _WebSocketHost.open = nil }
        let task = URLSession.shared.webSocketTask(with: URL(string: "ws://local.example/")!)
        #expect(task.maximumMessageSize == 1_048_576 && task.closeCode == .invalid)
        task.maximumMessageSize = 4
        task.resume()
        let socket = try! #require(host.sockets.first)
        socket.open()
        let code = Box<Int?>(nil)
        task.receive { result in if case .failure(let error) = result { code.value = Self.code(of: error) } }
        socket.events.received(.text("hello"))
        #expect(code.value == 40 && task.closeCode == .messageTooBig && socket.closedWith?.code == 1000)

        // `cancel()` ends the task as cancelled and closes the socket.
        let cancelled = URLSession.shared.webSocketTask(with: URL(string: "wss://local.example/")!)
        let pinged = Box<Bool?>(nil)
        cancelled.sendPing { error in pinged.value = error == nil }
        cancelled.resume()
        cancelled.cancel()
        #expect((cancelled.error as? URLError)?.code == .cancelled && host.sockets[1].closedWith?.code == 1000)
        #expect(pinged.value == false)

        // An address that is not a socket's fails as a bad URL.
        let bad = URLSession.shared.webSocketTask(with: URL(string: "ftp://files.example/")!)
        bad.resume()
        #expect((bad.error as? URLError)?.code == .badURL && host.sockets.count == 2)

        // Cancelled before it was resumed: no socket opens, and a send and a receive both fail as
        // cancelled (-999).
        let unstarted = URLSession.shared.webSocketTask(with: URL(string: "wss://local.example/")!)
        unstarted.cancel()
        let sendCode = Box<Int?>(nil), receiveCode = Box<Int?>(nil)
        unstarted.send(.string("hi")) { error in sendCode.value = error.flatMap { Self.code(of: $0) } }
        unstarted.receive { result in if case .failure(let error) = result { receiveCode.value = Self.code(of: error) } }
        #expect(sendCode.value == -999 && receiveCode.value == -999 && host.sockets.count == 2)

        // A close reason is cut to at most 123 UTF-8 bytes at a whole character.
        let long = URLSession.shared.webSocketTask(with: URL(string: "wss://local.example/")!)
        long.resume()
        host.sockets[2].open()
        long.cancel(with: .normalClosure, reason: Data((String(repeating: "a", count: 122) + "é").utf8))
        let reason = host.sockets[2].closedWith?.reason ?? ""
        #expect(reason.utf8.count <= 123 && reason == String(repeating: "a", count: 122))

        #expect(URLSessionWebSocketTask.CloseCode.messageTooBig.rawValue == 1009)
        #expect(URLSessionWebSocketTask.CloseCode.tlsHandshakeFailure.rawValue == 1015)
        #expect(URLSessionWebSocketTask.CloseCode(rawValue: 1004) == nil)
    }
}
#endif
