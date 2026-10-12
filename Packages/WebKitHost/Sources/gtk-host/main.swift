// gtk-host (Packages/WebKitHost): the Linux counterpart of Tools/Host (pf-linux): serves a package directory holding
// a built wasm bundle on 127.0.0.1 and shows its index.html in a WebKitGTK window.
//
//   swift run gtk-host <package-dir> [--port N] [--path index.html] [--width W] [--height H] [--timeout seconds]
//
// The server is a few lines of POSIX sockets (GET and HEAD, the bundle's MIME types, one
// request per connection); the window is a GtkApplication with a WebKitWebView.
#if canImport(CWebKitGTK)
import CGtk
import CWebKitGTK
import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

struct Options {
    var root: URL
    var port: UInt16 = 0
    var path = "index.html"
    var width: Int32 = 900
    var height: Int32 = 640
    var timeout: Double?

    init?(_ arguments: [String]) {
        var rootPath: String?
        var index = 0
        func value() -> String? { index += 1; return index < arguments.count ? arguments[index] : nil }
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--port": guard let v = value(), let p = UInt16(v) else { return nil }; port = p
            case "--path": guard let v = value() else { return nil }; path = v
            case "--width": guard let v = value(), let w = Int32(v) else { return nil }; width = w
            case "--height": guard let v = value(), let h = Int32(v) else { return nil }; height = h
            case "--timeout": guard let v = value(), let t = Double(v) else { return nil }; timeout = t
            default:
                if argument.hasPrefix("--") || rootPath != nil { return nil }
                rootPath = argument
            }
            index += 1
        }
        guard let rootPath else { return nil }
        root = URL(fileURLWithPath: rootPath).standardizedFileURL
    }
}

/// A minimal HTTP/1.1 server for one directory over POSIX sockets.
final class StaticServer: @unchecked Sendable {
    let root: URL
    private(set) var port: UInt16 = 0
    private var socket: Int32 = -1

    init(root: URL, port: UInt16) throws {
        self.root = root
        socket = Glibc_socket()
        guard socket >= 0 else { throw POSIXError(.EIO) }
        var one: Int32 = 1
        setsockopt(socket, SOL_SOCKET, SO_REUSEADDR, &one, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = UInt32(0x7F000001).bigEndian
        let bound = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        guard bound == 0, listen(socket, 16) == 0 else { throw POSIXError(.EADDRINUSE) }
        var bound_address = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &bound_address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(socket, $0, &length) } }
        self.port = UInt16(bigEndian: bound_address.sin_port)
    }

    private func Glibc_socket() -> Int32 {
        #if canImport(Glibc)
        return Glibc.socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
        #else
        return Darwin.socket(AF_INET, SOCK_STREAM, 0)
        #endif
    }

    func start() {
        let thread = Thread { [self] in
            while true {
                let client = accept(socket, nil, nil)
                guard client >= 0 else { continue }
                serve(client)
            }
        }
        thread.start()
    }

    private static let mimeTypes = ["html": "text/html; charset=utf-8", "js": "text/javascript", "mjs": "text/javascript", "wasm": "application/wasm", "json": "application/json",
                                    "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "svg": "image/svg+xml", "css": "text/css", "txt": "text/plain",
                                    "ttf": "font/ttf", "otf": "font/otf", "woff": "font/woff", "woff2": "font/woff2", "ico": "image/x-icon", "map": "application/json"]

    private func serve(_ client: Int32) {
        defer { close(client) }
        var buffer = [UInt8](repeating: 0, count: 8192)
        let received = recv(client, &buffer, buffer.count, 0)
        guard received > 0 else { return }
        let request = String(decoding: buffer[0..<received], as: UTF8.self)
        let parts = request.split(separator: " ", maxSplits: 2)
        guard parts.count >= 2 else { return }
        let method = String(parts[0])
        var path = String(parts[1])
        if let query = path.firstIndex(of: "?") { path = String(path[..<query]) }
        if path == "/" { path = "/index.html" }
        let file = root.appendingPathComponent(path.removingPercentEncoding ?? path)
        guard file.path.hasPrefix(root.path), let data = FileManager.default.contents(atPath: file.path) else {
            send(client, "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
            return
        }
        let type = Self.mimeTypes[file.pathExtension.lowercased()] ?? "application/octet-stream"
        send(client, "HTTP/1.1 200 OK\r\nContent-Type: \(type)\r\nContent-Length: \(data.count)\r\nCache-Control: no-cache\r\nConnection: close\r\n\r\n")
        if method != "HEAD" { send(client, data) }
    }

    private func send(_ client: Int32, _ string: String) { send(client, Data(string.utf8)) }
    private func send(_ client: Int32, _ data: Data) {
        data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                #if canImport(Glibc)
                let sent = Glibc.send(client, bytes.baseAddress! + offset, bytes.count - offset, Int32(MSG_NOSIGNAL))
                #else
                let sent = Darwin.send(client, bytes.baseAddress! + offset, bytes.count - offset, 0)
                #endif
                guard sent > 0 else { return }
                offset += sent
            }
        }
    }
}

func usage() -> Never {
    FileHandle.standardError.write(Data("usage: gtk-host <package-dir> [--port N] [--path index.html] [--width W] [--height H] [--timeout seconds]\n".utf8))
    exit(64)
}

guard let options = Options(Array(CommandLine.arguments.dropFirst())) else { usage() }
let server: StaticServer
do { server = try StaticServer(root: options.root, port: options.port) } catch {
    FileHandle.standardError.write(Data("gtk-host: cannot listen: \(error)\n".utf8))
    exit(69)
}
server.start()
let url = "http://127.0.0.1:\(server.port)/\(options.path)"
print("gtk-host: \(url)")

final class HostState { var options: Options; var url: String; init(options: Options, url: String) { self.options = options; self.url = url } }
let state = HostState(options: options, url: url)

let activate: @convention(c) (UnsafeMutablePointer<GtkApplication>?, gpointer?) -> Void = { app, data in
    guard let app, let data else { return }
    let state = Unmanaged<HostState>.fromOpaque(data).takeUnretainedValue()
    let window = gtk_application_window_new(app)!
    let gtkWindow = UnsafeMutableRawPointer(window).assumingMemoryBound(to: GtkWindow.self)
    gtk_window_set_title(gtkWindow, state.options.root.lastPathComponent)
    gtk_window_set_default_size(gtkWindow, state.options.width, state.options.height)
    let webView = webkit_web_view_new()!
    webkit_web_view_load_uri(UnsafeMutableRawPointer(webView).assumingMemoryBound(to: WebKitWebView.self), state.url)
    gtk_window_set_child(gtkWindow, webView)
    gtk_window_present(gtkWindow)
    if let timeout = state.options.timeout {
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { exit(0) }
    }
}

let app = gtk_application_new("dev.swiftuiweb.gtk-host", GApplicationFlags(rawValue: 0))!
g_signal_connect_data(UnsafeMutableRawPointer(app).assumingMemoryBound(to: GObject.self), "activate", unsafeBitCast(activate, to: GCallback.self), Unmanaged.passUnretained(state).toOpaque(), nil, GConnectFlags(rawValue: 0))
let status = g_application_run(UnsafeMutableRawPointer(app).assumingMemoryBound(to: GApplication.self), 0, nil)
g_object_unref(app)
exit(status)
#else
print("gtk-host needs WebKitGTK 6 (libwebkitgtk-6.0-dev)")
#endif
