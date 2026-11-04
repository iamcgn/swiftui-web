// The Foundation names RevenueCat reaches for: `NSError.UserInfoKey` and the URL error keys,
// a URL error's failing address as text, the app's directories as `URL` statics, an operation
// queue's block operations, `NSNumber.objCType` and `Locale.currency`. The cases run against
// Foundation on macOS and Linux too.
import Testing
import WebFoundation
import WebFoundationFormats

extension NSError.UserInfoKey {
    fileprivate static let statusCode: NSError.UserInfoKey = "status_code"
}

@Suite struct ErrorKeysAndDirectoriesTests {
    @Test func userInfoKeys() {
        let info: [NSError.UserInfoKey: Any] = [.statusCode: 404, NSLocalizedDescriptionKey: "Missing"]
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorBadServerResponse, userInfo: info)
        #expect(error.userInfo[NSError.UserInfoKey.statusCode] as? Int == 404)
        #expect(error.localizedDescription == "Missing")
        #expect(NSURLErrorBadServerResponse == -1011)
        #expect(NSURLErrorCannotFindHost == -1003)
    }

    @Test func failingAddressAsText() {
        let error = URLError(.badURL, userInfo: [NSURLErrorFailingURLStringErrorKey: "https://example.com/x"])
        #expect(error.failureURLString == "https://example.com/x")
    }

    @Test func directories() {
        #expect(URL.documentsDirectory == FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0])
        #expect(URL.cachesDirectory == FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0])
        #expect(URL.applicationSupportDirectory == FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0])
        #expect(URL.temporaryDirectory.path == FileManager.default.temporaryDirectory.path)
    }

    @Test func blockOperation() async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            OperationQueue.main.addOperation { done.resume() }
        }
    }

    @Test func objCTypes() {
        #expect(String(cString: NSNumber(value: 3 as Int).objCType) == "q")
        #expect(String(cString: NSNumber(value: 1.5).objCType) == "d")
        #expect(String(cString: NSNumber(value: true).objCType) == "c")
    }

    @Test func currency() {
        #expect(Locale(identifier: "en_US").currency?.identifier == "USD")
        #expect(Locale(identifier: "de_DE").currency?.identifier == "EUR")
        #expect(Locale.Currency("JPY").identifier == "JPY")
    }
}
