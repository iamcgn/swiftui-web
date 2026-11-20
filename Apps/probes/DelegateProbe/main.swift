// Scratch probe (not for merging): Foundation's own URLSession delegate protocols, called the way
// Nuke's DataLoader calls them (`(delegate as? URLSessionTaskDelegate)?.urlSession?(...)`), and a
// session that delivers its task events to an @objc delegate on the Objective-C runtime SDK.
import Foundation

final class Forwarded: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) { print("didCreateTask") }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) { print("data \(data.count)") }
    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completionHandler(.cancelAuthenticationChallenge, nil)
    }
}

let delegate: AnyObject = Forwarded()
let session = URLSession.shared
let task = session.dataTask(with: URL(string: "https://example.com")!)
(delegate as? URLSessionTaskDelegate)?.urlSession?(session, didCreateTask: task)
(delegate as? URLSessionDataDelegate)?.urlSession?(session, dataTask: task, didReceive: Data([1, 2, 3]))
let unimplemented: Void? = (delegate as? URLSessionTaskDelegate)?.urlSession?(session, task: task, didCompleteWithError: nil)
print("unimplemented call gives \(unimplemented == nil ? "nil" : "a value")")
print("redirect implemented: \((delegate as? NSObject)?.responds(to: #selector(URLSessionTaskDelegate.urlSession(_:task:willPerformHTTPRedirection:newRequest:completionHandler:))) ?? false)")
print("data implemented: \((delegate as? NSObject)?.responds(to: #selector(URLSessionDataDelegate.urlSession(_:dataTask:didReceive:) as ((URLSessionDataDelegate) -> ((URLSession, URLSessionDataTask, Data) -> Void)?))) ?? false)")

final class Recorder: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) { print("session created a task") }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        print("session completed a task (error: \(error == nil ? "none" : "yes"))")
        print("probe done")
    }
}
let recording = URLSession(configuration: .default, delegate: Recorder(), delegateQueue: nil)
recording.dataTask(with: URL(string: "https://example.invalid/")!).resume()
