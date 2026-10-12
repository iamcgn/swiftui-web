// swiftui-host: serves a package directory holding a built wasm bundle (Examples/Counter after
// scripts/build-wasm.sh) on 127.0.0.1 and shows its index.html in a WKWebView window.
//
//   swift run swiftui-host <package-dir> [--port N] [--path index.html] [--width W] [--height H]
//                          [--screenshot out.png] [--timeout seconds]
//
// --screenshot writes a snapshot of the page once it has loaded and quits; --timeout quits after
// the given number of seconds (both for scripts and CI). Without a package directory the host
// waits for one from the Finder: `scripts/build-host-app.sh` wraps it as SwiftUIHost.app, which
// opens `.swiftuiweb` bundles (a built package directory renamed) and plain bundle folders
// by double click or drop (pf-native-text), one window per bundle.
import AppKit
import Foundation
import Network
import WebKit

// MARK: - Arguments

struct Options {
    /// The bundle to serve; nil waits for the Finder to open one.
    var root: URL?
    var port: UInt16 = 0
    var path = "index.html"
    var width: CGFloat = 900
    var height: CGFloat = 640
    var screenshot: URL?
    var timeout: TimeInterval?

    init?(_ arguments: [String]) {
        var rootPath: String?
        var index = 0
        func value() -> String? {
            index += 1
            return index < arguments.count ? arguments[index] : nil
        }
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--port": guard let v = value(), let port = UInt16(v) else { return nil }; self.port = port
            case "--path": guard let v = value() else { return nil }; path = v
            case "--width": guard let v = value(), let w = Double(v) else { return nil }; width = w
            case "--height": guard let v = value(), let h = Double(v) else { return nil }; height = h
            case "--screenshot": guard let v = value() else { return nil }; screenshot = URL(fileURLWithPath: v)
            case "--timeout": guard let v = value(), let t = Double(v) else { return nil }; timeout = t
            default:
                if argument.hasPrefix("--") || rootPath != nil { return nil }
                rootPath = argument
            }
            index += 1
        }
        root = rootPath.map { URL(fileURLWithPath: $0).standardizedFileURL }
    }
}

func usage() -> Never {
    FileHandle.standardError.write(Data("""
    usage: swiftui-host <package-dir> [--port N] [--path index.html] [--width W] [--height H] [--screenshot out.png] [--timeout seconds]
    The package directory holds index.html and the bundle built by scripts/build-wasm.sh.

    """.utf8))
    exit(64)
}

// The Finder launches the app with `-psn_…` or no arguments and opens the bundle afterwards.
guard let options = Options(CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-psn") }) else { usage() }
if let root = options.root {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
        FileHandle.standardError.write(Data("swiftui-host: \(root.path) is not a directory\n".utf8))
        exit(66)
    }
}

// MARK: - Static file server

/// A minimal HTTP/1.1 server for one directory: GET and HEAD, no caching, one request per
/// connection. Enough for a wasm bundle (wasm, js, html, json, images, fonts).
final class StaticServer: @unchecked Sendable {
    let root: URL
    private let listener: NWListener
    private let queue = DispatchQueue(label: "swiftui-host.server")
    private(set) var port: UInt16 = 0

    init(root: URL, port: UInt16) throws {
        self.root = root
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        listener = try NWListener(using: parameters, on: port == 0 ? .any : NWEndpoint.Port(rawValue: port)!)
    }

    /// Starts listening; calls `ready` with the port once bound.
    func start(ready: @escaping @Sendable (UInt16) -> Void) {
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.port = self.listener.port?.rawValue ?? 0
                ready(self.port)
            case .failed(let error):
                FileHandle.standardError.write(Data("swiftui-host: server failed: \(error)\n".utf8))
                exit(69)
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in self?.serve(connection) }
        listener.start(queue: queue)
    }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(connection, buffer: Data())
    }

    private func receiveRequest(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let range = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(decoding: buffer[..<range.lowerBound], as: UTF8.self)
                self.respond(connection, head: head)
            } else if isComplete || error != nil || buffer.count > 65536 {
                connection.cancel()
            } else {
                self.receiveRequest(connection, buffer: buffer)
            }
        }
    }

    private func respond(_ connection: NWConnection, head: String) {
        let requestLine = head.split(separator: "\r\n", maxSplits: 1).first.map(String.init) ?? ""
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET" || parts[0] == "HEAD" else {
            send(connection, status: "405 Method Not Allowed", type: "text/plain", body: Data("method not allowed\n".utf8), headOnly: false)
            return
        }
        let target = String(parts[1]).split(separator: "?", maxSplits: 1).first.map(String.init) ?? "/"
        var path = target.removingPercentEncoding ?? target
        if path.hasSuffix("/") { path += "index.html" }
        let components = path.split(separator: "/").map(String.init)
        guard !components.contains("..") else {
            send(connection, status: "403 Forbidden", type: "text/plain", body: Data("forbidden\n".utf8), headOnly: parts[0] == "HEAD")
            return
        }
        var url = root
        for component in components { url.appendPathComponent(component) }
        var directory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &directory), directory.boolValue {
            url.appendPathComponent("index.html")
        }
        guard let body = FileManager.default.contents(atPath: url.path) else {
            send(connection, status: "404 Not Found", type: "text/plain", body: Data("not found: \(path)\n".utf8), headOnly: parts[0] == "HEAD")
            return
        }
        send(connection, status: "200 OK", type: Self.mimeType(for: url.pathExtension), body: body, headOnly: parts[0] == "HEAD")
    }

    private func send(_ connection: NWConnection, status: String, type: String, body: Data, headOnly: Bool) {
        var response = Data("""
        HTTP/1.1 \(status)\r
        Content-Type: \(type)\r
        Content-Length: \(body.count)\r
        Cache-Control: no-store\r
        Connection: close\r
        \r

        """.utf8)
        if !headOnly { response.append(body) }
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }

    static func mimeType(for pathExtension: String) -> String {
        switch pathExtension.lowercased() {
        case "html", "htm": return "text/html; charset=utf-8"
        case "js", "mjs": return "text/javascript; charset=utf-8"
        case "wasm": return "application/wasm"
        case "json", "map": return "application/json"
        case "css": return "text/css; charset=utf-8"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "svg": return "image/svg+xml"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "ico": return "image/x-icon"
        case "woff2": return "font/woff2"
        case "woff": return "font/woff"
        case "ttf", "otf": return "font/\(pathExtension.lowercased())"
        case "txt", "swift", "ts": return "text/plain; charset=utf-8"
        default: return "application/octet-stream"
        }
    }
}

// MARK: - Window

@MainActor
final class HostDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate {
    let options: Options
    /// The bundle the command line named, served once the app has launched.
    private var initialServer: StaticServer?
    var window: NSWindow!
    var webView: WKWebView!
    /// The bundles open: their servers and windows (the Finder may open several).
    private var opened: [(server: StaticServer, window: NSWindow)] = []

    init(options: Options, server: StaticServer?) {
        self.options = options
        initialServer = server
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let server = initialServer {
            initialServer = nil
            open(server: server)
        }
        if let timeout = options.timeout {
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { exit(0) }
        }
    }

    /// The Finder opened bundles (a double click on a `.swiftuiweb` package or a bundle folder,
    /// a drop on the app): each gets a window.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            // AppKit hands the command line's directory here too (before the launch finishes):
            // the server made for it serves it once.
            let path = url.standardizedFileURL.resolvingSymlinksInPath().path
            if opened.contains(where: { $0.server.root.resolvingSymlinksInPath().path == path }) { continue }
            if let initial = initialServer, initial.root.resolvingSymlinksInPath().path == path { continue }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue,
                  let server = try? StaticServer(root: url.standardizedFileURL, port: 0) else {
                NSSound.beep()
                continue
            }
            open(server: server)
        }
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        application(sender, open: [URL(fileURLWithPath: filename)])
        return true
    }

    /// Serves a bundle and shows it in a window of its own.
    private func open(server: StaticServer) {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        // Page errors are collected for --screenshot diagnostics.
        let errors = WKUserScript(source: """
            window.__hostErrors = [];
            window.addEventListener('error', e => window.__hostErrors.push(String(e.message)));
            window.addEventListener('unhandledrejection', e => window.__hostErrors.push('rejection: ' + String(e.reason)));
            window.__hostRaf = 0;
            (function tick() { window.__hostRaf++; requestAnimationFrame(tick); })();
            """, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        configuration.userContentController.addUserScript(errors)
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: options.width, height: options.height), configuration: configuration)
        webView.navigationDelegate = self
        let window = NSWindow(contentRect: webView.frame, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = server.root.lastPathComponent.replacingOccurrences(of: ".swiftuiweb", with: "")
        window.contentView = webView
        window.isReleasedWhenClosed = false
        if opened.isEmpty { window.center() } else { window.cascadeTopLeft(from: NSPoint(x: opened.last!.window.frame.minX + 24, y: opened.last!.window.frame.maxY - 24)) }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        self.webView = webView
        self.window = window
        opened.append((server, window))
        let path = options.path
        server.start { port in
            DispatchQueue.main.async {
                let url = URL(string: "http://127.0.0.1:\(port)/\(path)")!
                print("swiftui-host: \(url)")
                webView.load(URLRequest(url: url))
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard options.screenshot != nil else { return }
        waitForFirstFrame(attempts: 120)
    }

    /// Polls the app's debug hook until it has painted a frame (or gives up), reports page
    /// errors, then snapshots the page and quits.
    private func waitForFirstFrame(attempts: Int) {
        let probe = """
            JSON.stringify({ frames: window.__swiftuiwebDebug ? window.__swiftuiwebDebug.frameCount() : -1, errors: window.__hostErrors || [],
                             visibility: document.visibilityState, canvas: (document.querySelector('canvas') || {}).width || 0,
                             raf: window.__hostRaf || 0 })
            """
        webView.evaluateJavaScript(probe) { [weak self] result, _ in
            guard let self else { return }
            let text = result as? String ?? "{}"
            let status = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] ?? [:]
            let frames = status["frames"] as? Int ?? -1
            let errors = status["errors"] as? [String] ?? []
            if frames > 0 || attempts == 0 || !errors.isEmpty {
                for error in errors { FileHandle.standardError.write(Data("swiftui-host: page error: \(error)\n".utf8)) }
                if frames <= 0 { FileHandle.standardError.write(Data("swiftui-host: no frame painted (\(text))\n".utf8)) }
                // One more moment so the painted frame reaches the compositor.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.snapshot(exitCode: frames > 0 && errors.isEmpty ? 0 : 72) }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.waitForFirstFrame(attempts: attempts - 1) }
            }
        }
    }

    private func snapshot(exitCode: Int32) {
        guard let screenshot = options.screenshot else { exit(exitCode) }
        webView.takeSnapshot(with: nil) { image, error in
            guard let image, let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:]) else {
                FileHandle.standardError.write(Data("swiftui-host: snapshot failed: \(error.map { "\($0)" } ?? "no image")\n".utf8))
                exit(70)
            }
            do {
                try png.write(to: screenshot)
                print("swiftui-host: wrote \(screenshot.path)")
                exit(exitCode)
            } catch {
                FileHandle.standardError.write(Data("swiftui-host: could not write \(screenshot.path): \(error)\n".utf8))
                exit(73)
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        FileHandle.standardError.write(Data("swiftui-host: navigation failed: \(error)\n".utf8))
        if options.screenshot != nil || options.timeout != nil { exit(71) }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        self.webView(webView, didFail: navigation, withError: error)
    }
}

var server: StaticServer?
if let root = options.root {
    do {
        server = try StaticServer(root: root, port: options.port)
    } catch {
        FileHandle.standardError.write(Data("swiftui-host: cannot listen: \(error)\n".utf8))
        exit(69)
    }
}
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = HostDelegate(options: options, server: server)
app.delegate = delegate
app.run()
