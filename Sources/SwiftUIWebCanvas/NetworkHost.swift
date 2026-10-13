// The browser behind URLSession (decision 0021, pf-urlsession): `fetch` with the request's
// method, headers and body, an `AbortController` for cancellation and the timeout, the final
// response's status, headers and bytes read whole. The browser's rules are the app's: CORS is
// decided here — a refused cross-origin request is a `TypeError` from `fetch`, reported as a
// transport failure (`URLError.cannotConnectToHost` with the browser's message), never as a
// status; redirects are followed by the browser (the final URL and status come back); the
// browser's HTTP cache serves `fetch` as it serves the page.
#if os(WASI)
import JavaScriptKit
import WebFoundation

@MainActor
enum NetworkHost {
    static func install() {
        guard JSObject.global.fetch.function != nil else { return }
        _WebHTTPHost.send = { request, completion in FetchTask(request: request, completion: completion) }
    }
}

/// One fetch in flight.
final class FetchTask: _WebHTTPTask, @unchecked Sendable {
    private var controller: JSObject?
    private var closures: [JSClosure] = []
    private var timeout: JSValue = .undefined
    private var done = false

    init?(request: _WebHTTPRequest, completion: @escaping @Sendable (Result<_WebHTTPResponse, _WebHTTPFailure>) -> Void) {
        guard let fetch = JSObject.global.fetch.function else { return nil }
        let options = JSObject.global.Object.function!.new()
        options.method = .string(request.method)
        let headers = JSObject.global.Object.function!.new()
        for (key, value) in request.headers { headers[dynamicMember: key] = .string(value) }
        options.headers = .object(headers)
        if let body = request.body, request.method != "GET", request.method != "HEAD" {
            options.body = JSTypedArray<UInt8>(body).jsValue
        }
        if let abort = JSObject.global.AbortController.function {
            let controller = abort.new()
            self.controller = controller
            options.signal = controller.signal
        }
        let finish: @Sendable (Result<_WebHTTPResponse, _WebHTTPFailure>) -> Void = { [weak self] result in
            guard let self, !self.done else { return }
            self.done = true
            if let clear = JSObject.global.clearTimeout.function { _ = clear(self.timeout) }
            completion(result)
        }
        // The timeout: abort after the interval; the rejection below reports `.timedOut`.
        nonisolated(unsafe) var timedOut = false
        if request.timeout > 0, let setTimeout = JSObject.global.setTimeout.function, let controller {
            let fire = JSClosure { (_: [JSValue]) -> JSValue in timedOut = true; _ = controller.abort?(); return .undefined }
            closures.append(fire)
            timeout = setTimeout(fire, request.timeout * 1000)
        }
        let onResponse = JSClosure { (arguments: [JSValue]) -> JSValue in
            guard let response = arguments.first?.object, let status = response.status.number else { finish(.failure(.unreachable("no response"))); return .undefined }
            let url = response.url.string ?? request.url
            var headers: [String: String] = [:]
            if let list = response.headers.object, let each = list.forEach.function {
                let collect = JSClosure { (pair: [JSValue]) -> JSValue in
                    if let value = pair.first?.string, let key = pair.dropFirst().first?.string { headers[key] = value }
                    return .undefined
                }
                _ = each(this: list, collect)   // synchronous: the pairs are collected before this returns
            }
            guard let bytesPromise = response.arrayBuffer?().object else { finish(.success(_WebHTTPResponse(url: url, status: Int(status), headers: headers, body: []))); return .undefined }
            let onBytes = JSClosure { (bytes: [JSValue]) -> JSValue in
                var body: [UInt8] = []
                if let buffer = bytes.first?.object, let array = JSObject.global.Uint8Array.function?.new(buffer) {
                    body = JSTypedArray<UInt8>(unsafelyWrapping: array).withUnsafeBytes { Array($0) }
                }
                finish(.success(_WebHTTPResponse(url: url, status: Int(status), headers: headers, body: body)))
                return .undefined
            }
            let onBytesError = JSClosure { (_: [JSValue]) -> JSValue in finish(.failure(.unreachable("the response body could not be read"))); return .undefined }
            _ = bytesPromise.then!(onBytes, onBytesError)
            FetchTask.retained.append(onBytes)
            FetchTask.retained.append(onBytesError)
            return .undefined
        }
        let onError = JSClosure { [weak self] (arguments: [JSValue]) -> JSValue in
            let error = arguments.first?.object
            let name = error?.name.string ?? ""
            let message = error?.message.string ?? "fetch failed"
            let reason = (name.isEmpty ? "TypeError" : name) + ": " + message
            if name == "AbortError" {
                finish(.failure(timedOut ? .timedOut : .cancelled))
            } else if !(JSObject.global.navigator.onLine.boolean ?? true) {
                finish(.failure(.notConnected))
            } else {
                finish(.failure(.unreachable(reason)))
            }
            _ = self
            return .undefined
        }
        closures.append(contentsOf: [onResponse, onError])
        _ = fetch(request.url, options).object?.then?(onResponse, onError)
    }

    func cancel() {
        guard !done else { return }
        _ = controller?.abort?()
    }

    nonisolated(unsafe) static var retained: [JSClosure] = []
}
#endif
