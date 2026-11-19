// Scratch probe (not for merging): which URLSession delegate shapes the Objective-C runtime SDK
// accepts as @objc optional requirements, as Nuke's DataLoader calls them
// (`(delegate as? URLSessionTaskDelegate)?.urlSession?(session, didCreateTask: task)`).
// Every line that fails is one type the bridge still needs.
import Foundation

@objc enum ProbeDisposition: Int { case allow, cancel }
final class ProbeChallenge: NSObject {}
final class ProbeCredential: NSObject {}

@objc protocol ProbeSessionDelegate: NSObjectProtocol {
    @objc optional func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask)
    @objc optional func urlSession(_ session: URLSession, didBecomeInvalidWithError error: (any Error)?)
    @objc optional func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?)
    @objc optional func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data)
    @objc optional func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                                   completionHandler: @escaping @Sendable (ProbeDisposition) -> Void)
    @objc optional func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                                   newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void)
    // Stand-ins for the classes that still need an NSObject root (URLAuthenticationChallenge,
    // URLCredential, InputStream, URLSessionTaskMetrics, CachedURLResponse failed as they are).
    @objc optional func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: ProbeChallenge,
                                   completionHandler: @escaping @Sendable (ProbeDisposition, ProbeCredential?) -> Void)
    @objc optional func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL)
}

final class ProbeImpl: NSObject, ProbeSessionDelegate {
    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) { print("didCreateTask") }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) { print("data \(data.count)") }
    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: ProbeChallenge,
                    completionHandler: @escaping @Sendable (ProbeDisposition, ProbeCredential?) -> Void) {
        completionHandler(.cancel, nil)
    }
}

let delegate: AnyObject = ProbeImpl()
let session = URLSession.shared
let task = session.dataTask(with: URL(string: "https://example.com")!)
(delegate as? ProbeSessionDelegate)?.urlSession?(session, didCreateTask: task)
(delegate as? ProbeSessionDelegate)?.urlSession?(session, dataTask: task, didReceive: Data([1, 2, 3]))
(delegate as? ProbeSessionDelegate)?.urlSession?(session, task: task, didCompleteWithError: nil)
(delegate as? ProbeSessionDelegate)?.urlSession?(session, task: task, didReceive: ProbeChallenge()) { disposition, _ in
    print("challenge handled \(disposition.rawValue)")
}
let unimplemented = (delegate as? ProbeSessionDelegate)?.urlSession?(session, task: task, didCompleteWithError: nil)
print("unimplemented call gives \(unimplemented == nil ? "nil" : "a value")")
print("redirect implemented: \((delegate as? ProbeSessionDelegate)?.responds(to: #selector(ProbeSessionDelegate.urlSession(_:task:willPerformHTTPRedirection:newRequest:completionHandler:))) ?? false)")
print("probe done")
