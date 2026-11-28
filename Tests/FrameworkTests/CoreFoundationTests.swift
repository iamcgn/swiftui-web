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
        // Clendar's app name: `Bundle.main.object(forInfoDictionaryKey: kCFBundleNameKey as String)`.
        #expect(kCFBundleNameKey as String == "CFBundleName" && kCFBundleVersionKey as String == "CFBundleVersion")
        #expect(kCFBundleIdentifierKey as String == "CFBundleIdentifier")
    }
    #endif

    #if os(WASI) || canImport(Darwin)
    // SwiftyChrono's Japanese parser folds full-width text to half-width this way before it
    // reads the numbers. Linux's Foundation keeps Core Foundation to itself, so this runs on
    // macOS and wasm.
    private func transformed(_ text: String, reverse: Bool = false) -> (String, Bool) {
        let str = NSMutableString(string: text) as CFMutableString
        let known = CFStringTransform(str, nil, kCFStringTransformFullwidthHalfwidth, reverse)
        return (str as String, known)
    }

    @Test func theWidthTransformFoldsFullwidthFormsToHalfwidth() {
        #expect(transformed("２０２６年１１月２８日") == ("2026年11月28日", true))
        #expect(transformed("ＡＢＣ\u{3000}ｘｙｚ！") == ("ABC xyz!", true))
        #expect(transformed("アイウ").0 == "\u{FF71}\u{FF72}\u{FF73}")
        #expect(transformed("ガパ").0 == "\u{FF76}\u{FF9E}\u{FF8A}\u{FF9F}")
        #expect(transformed("漢字 abc").0 == "漢字 abc")
    }

    @Test func reversedItWidensHalfwidthFormsAndVoicesKana() {
        #expect(transformed("2026", reverse: true).0 == "２０２６")
        #expect(transformed("\u{FF76}\u{FF9E}\u{FF8A}\u{FF9F}\u{FF71}", reverse: true).0 == "ガパア")
    }

    @Test func aRangeLimitsTheTransformAndTakesTheNewLength() {
        let str = NSMutableString(string: "１２ガ３") as CFMutableString
        var range = CFRangeMake(1, 2)
        #expect(CFStringTransform(str, &range, kCFStringTransformFullwidthHalfwidth, false))
        #expect(str as String == "１2\u{FF76}\u{FF9E}３")
        #expect(range.location == 1 && range.length == 3)
    }
    #endif
}
