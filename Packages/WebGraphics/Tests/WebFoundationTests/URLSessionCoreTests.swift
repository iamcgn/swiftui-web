// The URLSession core (decision 0021, pf-urlsession) against a fake host: the request reaches
// the host as written (method, merged headers, body, timeout), an HTTP error status comes back
// as a response with its status, headers and bytes — never as an error — a transport or CORS
// refusal comes back as a failure with its reason — never as a status — and a cancelled task
// answers `.cancelled` exactly once. The public wasm types over this core are checked by the
// Launches probe in the browser against local fixtures.
import Testing
@testable import WebFoundation

@Suite(.serialized) struct URLSessionCoreTests {
    final class FakeHostTask: _WebHTTPTask, @unchecked Sendable {
        var cancelled = false
        var answer: (@Sendable (Result<_WebHTTPResponse, _WebHTTPFailure>) -> Void)?
        func cancel() { cancelled = true; answer?(.failure(.cancelled)) }
    }

    final class FakeHost: @unchecked Sendable {
        var requests: [_WebHTTPRequest] = []
        var tasks: [FakeHostTask] = []
        var script: [(_WebHTTPRequest) -> Result<_WebHTTPResponse, _WebHTTPFailure>?] = []
        func install() {
            _WebHTTPHost.send = { [self] request, completion in
                requests.append(request)
                let task = FakeHostTask()
                task.answer = completion
                tasks.append(task)
                if let next = script.first { script.removeFirst(); if let outcome = next(request) { completion(outcome) } }
                return task
            }
        }
    }

    private func outcomes(_ session: _WebURLSession, url: String, method: String? = nil, headers: [String: String]? = nil, body: [UInt8]? = nil) -> (task: _WebURLSession.Task, box: _OutcomeBox) {
        let box = _OutcomeBox()
        let task = session.send(url: url, method: method, headers: headers, body: body, timeout: nil) { box.outcomes.append($0) }
        return (task, box)
    }
    final class _OutcomeBox: @unchecked Sendable { var outcomes: [_WebURLSession.Outcome] = [] }

    @Test func theRequestReachesTheHostAsWritten() {
        let host = FakeHost(); host.install(); defer { _WebHTTPHost.send = nil }
        var configuration = _WebURLSession.Configuration()
        configuration.httpAdditionalHeaders = ["Accept": "application/json", "X-App": "countries"]
        configuration.timeoutIntervalForRequest = 60
        let session = _WebURLSession(configuration: configuration)
        host.script = [{ _ in .success(_WebHTTPResponse(url: "https://api.example/x", status: 201, headers: ["Content-Type": "application/json"], body: Array("{\"ok\":true}".utf8))) }]
        let (_, box) = outcomes(session, url: "https://api.example/x", method: "post", headers: ["X-App": "override", "Content-Type": "application/json"], body: Array("{}".utf8))
        let sent = host.requests[0]
        #expect(sent.method == "POST" && sent.url == "https://api.example/x" && sent.timeout == 60)
        #expect(sent.headers == ["Accept": "application/json", "X-App": "override", "Content-Type": "application/json"])
        #expect(sent.body == Array("{}".utf8))
        guard case .response(let response)? = box.outcomes.first else { Issue.record("no response"); return }
        #expect(response.status == 201 && response.headers["Content-Type"] == "application/json" && String(decoding: response.body, as: UTF8.self) == "{\"ok\":true}")
    }

    @Test func anHTTPErrorStatusIsAResponseNotAFailure() {
        let host = FakeHost(); host.install(); defer { _WebHTTPHost.send = nil }
        let session = _WebURLSession()
        host.script = [{ _ in .success(_WebHTTPResponse(url: "https://api.example/missing", status: 404, headers: ["Content-Type": "text/plain"], body: Array("not here".utf8))) }]
        let (task, box) = outcomes(session, url: "https://api.example/missing")
        guard case .response(let response)? = box.outcomes.first else { Issue.record("a 404 must be a response"); return }
        #expect(response.status == 404 && String(decoding: response.body, as: UTF8.self) == "not here" && task.isFinished && !task.isCancelled)
    }

    @Test func aTransportOrCORSRefusalIsAFailureWithItsReasonNotAStatus() {
        let host = FakeHost(); host.install(); defer { _WebHTTPHost.send = nil }
        let session = _WebURLSession()
        host.script = [{ _ in .failure(.unreachable("TypeError: Failed to fetch")) }, { _ in .failure(.timedOut) }, { _ in .failure(.notConnected) }]
        let (_, refused) = outcomes(session, url: "https://restcountries.example/v2/all")
        guard case .failure(let failure)? = refused.outcomes.first else { Issue.record("a refusal must be a failure"); return }
        #expect(failure == .unreachable("TypeError: Failed to fetch"))
        let (_, timed) = outcomes(session, url: "https://slow.example/")
        guard case .failure(.timedOut)? = timed.outcomes.first else { Issue.record("a timeout must be .timedOut"); return }
        let (_, offline) = outcomes(session, url: "https://any.example/")
        guard case .failure(.notConnected)? = offline.outcomes.first else { Issue.record("offline must be .notConnected"); return }
    }

    @Test func cancellationAnswersOnceAndTellsTheHost() {
        let host = FakeHost(); host.install(); defer { _WebHTTPHost.send = nil }
        let session = _WebURLSession()
        host.script = [{ _ in nil }]   // the host never answers on its own
        let (task, box) = outcomes(session, url: "https://api.example/slow")
        #expect(box.outcomes.isEmpty && !task.isFinished)
        task.cancel()
        #expect(host.tasks[0].cancelled && task.isCancelled && task.isFinished)
        task.cancel()                                   // a second cancel changes nothing
        host.tasks[0].answer?(.success(_WebHTTPResponse(url: "", status: 200, headers: [:], body: [])))   // a late answer is dropped
        #expect(box.outcomes.count == 1)
        guard case .failure(.cancelled)? = box.outcomes.first else { Issue.record("cancel must answer .cancelled"); return }
        // cancelAll ends what is in flight.
        host.script = [{ _ in nil }, { _ in nil }]
        let (a, aBox) = outcomes(session, url: "https://api.example/1")
        let (b, bBox) = outcomes(session, url: "https://api.example/2")
        session.cancelAll()
        #expect(a.isCancelled && b.isCancelled && aBox.outcomes.count == 1 && bBox.outcomes.count == 1)
    }

    @Test func withoutAHostEveryRequestIsUnreachable() {
        _WebHTTPHost.send = nil
        let (_, box) = outcomes(_WebURLSession(), url: "https://api.example/")
        guard case .failure(.unreachable(let reason))? = box.outcomes.first else { Issue.record("no host must be unreachable"); return }
        #expect(reason == "no network host")
    }
}
