// Scratch probe (not for merging): which URLSession delegate shapes the Objective-C runtime SDK
// accepts as @objc optional requirements, as Nuke's DataLoader calls them
// (`(delegate as? URLSessionTaskDelegate)?.urlSession?(session, didCreateTask: task)`).
// Every line that fails is one type the bridge still needs.
import Foundation

@objc enum ProbeDisposition: Int { case allow, cancel }

@objc protocol ProbeSessionDelegate: NSObjectProtocol {
    @objc optional func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask)
    @objc optional func urlSession(_ session: URLSession, didBecomeInvalidWithError error: (any Error)?)
    @objc optional func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?)
    @objc optional func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data)
    @objc optional func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                                   completionHandler: @escaping @Sendable (ProbeDisposition) -> Void)
    @objc optional func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                                   newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void)
    @objc optional func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                                   completionHandler: @escaping @Sendable (ProbeDisposition, URLCredential?) -> Void)
    @objc optional func urlSession(_ session: URLSession, task: URLSessionTask, needNewBodyStream completionHandler: @escaping @Sendable (InputStream?) -> Void)
    @objc optional func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics)
    @objc optional func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, willCacheResponse proposedResponse: CachedURLResponse,
                                   completionHandler: @escaping @Sendable (CachedURLResponse?) -> Void)
    @objc optional func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL)
}

final class ProbeImpl: NSObject, ProbeSessionDelegate {
    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) { print("didCreateTask") }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) { print("data \(data.count)") }
}

let delegate: AnyObject = ProbeImpl()
let session = URLSession.shared
let task = session.dataTask(with: URL(string: "https://example.com")!)
(delegate as? ProbeSessionDelegate)?.urlSession?(session, didCreateTask: task)
(delegate as? ProbeSessionDelegate)?.urlSession?(session, dataTask: task, didReceive: Data([1, 2, 3]))
(delegate as? ProbeSessionDelegate)?.urlSession?(session, task: task, didCompleteWithError: nil)
print("probe done")
