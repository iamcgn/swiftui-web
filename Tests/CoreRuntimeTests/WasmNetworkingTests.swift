// The URLSession pieces Alamofire builds on (its requests, uploads, downloads and streams), over a
// host that answers at once: tasks that key a dictionary, download and upload tasks with handlers
// and with a delegate, a streamed upload's body asked of the delegate, bound streams, the
// credential store, certificate trust built by hand, and the browser's online state.
#if os(WASI)
import Testing
import WebFoundation

@Suite(.serialized) struct WasmNetworkingTests {
    final class Host: _WebHTTPTask, @unchecked Sendable { func cancel() {} }

    /// Answers every request with `body`, recording what was sent.
    final class Echo: @unchecked Sendable {
        var sent: [_WebHTTPRequest] = []
        func install(_ body: String = "ok") {
            _WebHTTPHost.send = { [self] request, completion in
                sent.append(request)
                completion(.success(_WebHTTPResponse(url: request.url, status: 200, headers: ["Content-Type": "text/plain"], body: Array(body.utf8))))
                return Host()
            }
        }
    }

    @Test func tasksKeyDictionariesAndSuspend() {
        let echo = Echo(); echo.install(); defer { _WebHTTPHost.send = nil }
        let session = URLSession(configuration: .default)
        let first = session.dataTask(with: URL(string: "https://api.example/a")!) { _, _, _ in }
        let second = session.dataTask(with: URL(string: "https://api.example/b")!) { _, _, _ in }
        let requests: [URLSessionTask: String] = [first: "a", second: "b"]
        #expect(requests[first] == "a" && requests[second] == "b" && first != second)
        first.resume()
        #expect(first.state == .completed)
        second.suspend()
        #expect(second.state == .suspended && echo.sent.count == 1)
        #expect(session.configuration.urlCredentialStorage === URLCredentialStorage.shared)
        #expect(NSURLSessionTransferSizeUnknown == -1 && URLSessionTaskMetrics().taskInterval.duration == 0)
    }

    @Test func downloadAndUploadTasksWithHandlers() throws {
        let echo = Echo(); echo.install("downloaded"); defer { _WebHTTPHost.send = nil }
        let session = URLSession(configuration: .default)
        nonisolated(unsafe) var contents: String?
        nonisolated(unsafe) var kept: URL?
        session.downloadTask(with: URL(string: "https://files.example/report.txt")!) { file, response, error in
            kept = file
            contents = file.flatMap { try? Data(contentsOf: $0) }.map { String(decoding: $0, as: UTF8.self) }
            #expect((response as? HTTPURLResponse)?.statusCode == 200 && error == nil)
        }.resume()
        #expect(contents == "downloaded")
        // Removed once the handler returned, as Foundation removes it.
        #expect(kept.map { (try? $0.checkResourceIsReachable()) == nil } == true)

        var request = URLRequest(url: URL(string: "https://api.example/upload")!)
        request.httpMethod = "PUT"
        nonisolated(unsafe) var answer: Data?
        let upload = session.uploadTask(with: request, from: Data("body".utf8)) { data, _, _ in answer = data }
        upload.resume()
        #expect(echo.sent.last?.method == "PUT" && echo.sent.last?.body == Array("body".utf8) && answer == Data("downloaded".utf8))

        let file = FileManager.default.temporaryDirectory.appendingPathComponent("part.bin")
        try Data([1, 2, 3]).write(to: file)
        #expect(try file.checkPromisedItemIsReachable())
        session.uploadTask(with: URLRequest(url: URL(string: "https://api.example/file")!), fromFile: file) { _, _, _ in }.resume()
        #expect(echo.sent.last?.method == "POST" && echo.sent.last?.body == [1, 2, 3])

        nonisolated(unsafe) var missing: Error?
        _ = session.uploadTask(with: request, fromFile: FileManager.default.temporaryDirectory.appendingPathComponent("none")) { _, _, error in missing = error }
        #expect((missing as? URLError)?.code == .fileDoesNotExist)

        nonisolated(unsafe) var resumeData: Data? = Data([0])
        let download = session.downloadTask(with: URL(string: "https://files.example/big")!) { _, _, _ in }
        download.cancel { resumeData = $0 }
        #expect(resumeData == nil && (download.error as? URLError)?.code == .cancelled)
    }

    @Test func delegatedDownloadsAndStreamedUploads() {
        final class Delegate: NSObject, URLSessionDownloadDelegate, URLSessionDataDelegate {
            var events: [String] = []
            func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                            totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
                events.append("wrote \(totalBytesWritten)")
            }
            func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
                events.append("file " + String(decoding: (try? Data(contentsOf: location)) ?? Data(), as: UTF8.self))
            }
            func urlSession(_ session: URLSession, task: URLSessionTask, needNewBodyStream completionHandler: @escaping @Sendable (InputStream?) -> Void) {
                events.append("stream")
                completionHandler(InputStream(data: Data("streamed".utf8)))
            }
            func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64,
                            totalBytesExpectedToSend: Int64) {
                events.append("sent \(totalBytesSent)")
            }
            func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
                events.append("data " + String(decoding: data, as: UTF8.self))
            }
            func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
                events.append("complete \((error as? URLError)?.errorCode ?? 0)")
            }
        }
        let echo = Echo(); echo.install("hello"); defer { _WebHTTPHost.send = nil }
        let delegate = Delegate()
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: .main)
        session.downloadTask(with: URL(string: "https://files.example/hello")!).resume()
        #expect(delegate.events == ["wrote 5", "file hello", "complete 0"])

        delegate.events = []
        session.uploadTask(withStreamedRequest: URLRequest(url: URL(string: "https://api.example/stream")!)).resume()
        #expect(delegate.events == ["stream", "sent 8", "data hello", "complete 0"])
        #expect(echo.sent.last?.body == Array("streamed".utf8) && echo.sent.last?.method == "POST")

        delegate.events = []
        session.uploadTask(with: URLRequest(url: URL(string: "https://api.example/up")!), from: Data("abc".utf8)).resume()
        #expect(delegate.events == ["sent 3", "data hello", "complete 0"])
    }

    @Test func boundStreamsCarryWritesToTheirInput() {
        var input: InputStream?
        var output: OutputStream?
        Stream.getBoundStreams(withBufferSize: 4, inputStream: &input, outputStream: &output)
        guard let input, let output else { Issue.record("no streams"); return }
        input.open()
        output.open()
        let bytes: [UInt8] = Array("abcdef".utf8)
        #expect(output.write(bytes, maxLength: bytes.count) == 4 && !output.hasSpaceAvailable)
        var buffer = [UInt8](repeating: 0, count: 8)
        #expect(input.read(&buffer, maxLength: 8) == 4 && Array(buffer[0..<4]) == Array("abcd".utf8))
        #expect(output.write(Array(bytes[4...]), maxLength: 2) == 2)
        output.close()
        #expect(input.read(&buffer, maxLength: 8) == 2 && input.streamStatus == .atEnd)
    }

    @Test func credentialStorageKeysByProtectionSpace() {
        let storage = URLCredentialStorage()
        let space = URLProtectionSpace(host: "api.example", port: 443, protocol: NSURLProtectionSpaceHTTPS, realm: "api",
                                       authenticationMethod: NSURLAuthenticationMethodHTTPBasic)
        let same = URLProtectionSpace(host: "api.example", port: 443, protocol: NSURLProtectionSpaceHTTPS, realm: "api",
                                      authenticationMethod: NSURLAuthenticationMethodHTTPBasic)
        let ada = URLCredential(user: "ada", password: "x", persistence: .forSession)
        storage.setDefaultCredential(ada, for: space)
        storage.set(URLCredential(user: "bo", password: "y", persistence: .permanent), for: same)
        storage.set(URLCredential(user: "cy", password: "z", persistence: .none), for: same)
        #expect(space == same && storage.defaultCredential(for: same)?.user == "ada")
        #expect(storage.credentials(for: space).map { Set($0.keys) } == ["ada", "bo"] && storage.allCredentials.count == 1)
        storage.remove(ada, for: same)
        #expect(storage.defaultCredential(for: space) == nil && storage.credentials(for: space)?.count == 1)
    }

    @Test func trustBuiltFromCertificatesIsKeptButNotEvaluated() {
        #expect(SecCertificateCreateWithData(nil, Data()) == nil)
        let leaf = SecCertificateCreateWithData(nil, Data([0x30, 0x01]))!
        let root = SecCertificateCreateWithData(kCFAllocatorDefault, Data([0x30, 0x02]))!
        var trust: SecTrust?
        #expect(SecTrustCreateWithCertificates([leaf, root] as CFArray, SecPolicyCreateSSL(true, "api.example"), &trust) == 0)
        guard let trust else { Issue.record("no trust"); return }
        #expect(SecTrustGetCertificateCount(trust) == 2 && SecTrustGetCertificateAtIndex(trust, 1) == root)
        #expect(SecCertificateCopyData(leaf) == Data([0x30, 0x01]) && (SecTrustCopyCertificateChain(trust) as? [SecCertificate]) == [leaf, root])
        #expect(SecTrustSetPolicies(trust, [SecPolicyCreateBasicX509(), SecPolicyCreateRevocation(kSecRevocationUseAnyAvailableMethod)!]) == 0)
        #expect(SecTrustSetAnchorCertificates(trust, [root]) == 0 && SecTrustCopyKey(trust) == nil)
        var error: CFError?
        #expect(!SecTrustEvaluateWithError(trust, &error) && error?.domain == NSOSStatusErrorDomain)
        var result = SecTrustResultType.invalid
        #expect(SecTrustEvaluate(trust, &result) != 0 && result == .otherError)
    }

    @Test func onlineStateComesFromTheHost() {
        nonisolated(unsafe) var online = false
        _WebNetworkStatus.isOnline = { online }
        defer { _WebNetworkStatus.isOnline = nil }
        nonisolated(unsafe) var heard = 0
        let token = _WebNetworkStatus.addObserver { heard += 1 }
        #expect(!_WebNetworkStatus.online)
        online = true
        _WebNetworkStatus.changed()
        #expect(_WebNetworkStatus.online && heard == 1)
        _WebNetworkStatus.removeObserver(token)
        _WebNetworkStatus.changed()
        #expect(heard == 1)
    }
}
#endif
