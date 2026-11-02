// Core Foundation's names on the web (Packages/WebGraphics/Sources/WebFoundation/CoreFoundation.swift),
// as keychain wrappers use them, and `rangeOfCharacter(from:)`, which Alamofire's form encoder
// and TelemetryDeck call: the same answers as Foundation's on macOS and Linux.
import Testing
import WebFoundation

@Suite struct CoreFoundationTests {
    @Test func rangeOfCharacterFindsScalarsInTheSet() {
        let text = "ab1c2"
        #expect(text.rangeOfCharacter(from: .decimalDigits).map { String(text[$0]) } == "1")
        #expect(text.rangeOfCharacter(from: .decimalDigits, options: .backwards).map { String(text[$0]) } == "2")
        #expect(text.rangeOfCharacter(from: .decimalDigits, options: .anchored) == nil)
        #expect("1ab".rangeOfCharacter(from: .decimalDigits, options: .anchored).map { String("1ab"[$0]) } == "1")
        #expect(text.rangeOfCharacter(from: CharacterSet(charactersIn: "xyz")) == nil)
        let tail = text.index(text.startIndex, offsetBy: 3)
        #expect(text.rangeOfCharacter(from: .decimalDigits, range: tail..<text.endIndex).map { String(text[$0]) } == "2")
        #expect("a b".rangeOfCharacter(from: .whitespaces) != nil && "ab".rangeOfCharacter(from: .whitespaces) == nil)
    }

    #if os(WASI)
    // Apple's are Core Foundation objects bridged to these; the wasm names are the Swift types.
    @Test func coreFoundationNamesAreTheirSwiftTypes() {
        let query: CFDictionary = ["r_Data": kCFBooleanTrue as Any, "m_Limit": "m_LimitOne" as CFString]
        #expect(query["r_Data"] as? Bool == true && query["m_Limit"] as? String == "m_LimitOne")
        #expect((kCFBooleanFalse as Any) as? Bool == false)
        let status: OSStatus = noErr
        #expect(status == 0)
        let data: CFData = Data([1, 2])
        #expect(data.count == 2)
        let error: CFError = NSError(domain: "keychain", code: -25300)
        #expect(error.code == -25300)
    }
    #endif
}
