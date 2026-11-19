// APIs Mlem's own packages reach for (its icon helpers, its API client, its Markdown and link
// preview packages): labels and pickers titled by string resources and symbols, matching a
// `URLError` code against any error, and the CoreGraphics and CoreFoundation C helpers on wasm.
import WebFoundation
import Testing
import SwiftUI
import SwiftUIWebCore
import WebGraphics

/// Built off the main actor, as an app's own `nonisolated` helpers build them.
nonisolated private func resourceLabels(_ choice: Binding<Int>) -> (Label<Text, Image>, Label<Text, Image>, Picker<Label<Text, Image>, Int, Text>, Picker<Label<Text, Image>, Int, Text>) {
    let title = LocalizedStringResource("Inbox")
    return (Label(title, systemImage: "tray"),
            Label(title, image: "Mascot"),
            Picker("Sort", systemImage: "arrow.up.arrow.down", selection: choice) { Text("New") },
            Picker(title, systemImage: "tray", selection: choice) { Text("All") })
}

@Suite struct MlemPackageAPITests {
    @MainActor @Test func labelsAndPickersTakeResourcesAndSymbols() {
        var value = 1
        let choice = Binding(get: { value }, set: { value = $0 })
        let (symbol, image, sort, inbox) = resourceLabels(choice)
        #expect(symbol.title.resolvedString == "Inbox" && image.title.resolvedString == "Inbox")
        #expect(sort.label.title.resolvedString == "Sort" && inbox.label.title.resolvedString == "Inbox")
        sort.selection.wrappedValue = 3
        #expect(value == 3)
    }

#if os(WASI)
    @Test func urlErrorCodesMatchAnyError() {
        let cancelled: any Error = URLError(.cancelled)
        guard case URLError.cancelled = cancelled else { Issue.record("cancelled did not match"); return }
        let timedOut: any Error = URLError(.timedOut)
        if case URLError.cancelled = timedOut { Issue.record("timed out matched cancelled") }
        struct Other: Error {}
        if case URLError.cancelled = Other() as any Error { Issue.record("another error matched") }
    }

    @Test func rectFunctionsMatchTheirMethods() {
        let a = CGRect(x: 0, y: 0, width: 10, height: 10)
        let b = CGRect(x: 5, y: 20, width: 10, height: 5)
        #expect([a, b].reduce(CGRect.null, CGRectUnion) == CGRect(x: 0, y: 0, width: 15, height: 25))
        #expect(CGRectIntersectsRect(a, b) == false && CGRectIsNull(CGRectIntersection(a, b)))
        #expect(CGRectContainsPoint(a, CGPoint(x: 5, y: 5)) && CGRectContainsRect(a, CGRectInset(a, 2, 2)))
        #expect(CGRectEqualToRect(CGRectOffset(a, 1, 2), CGRect(x: 1, y: 2, width: 10, height: 10)))
        #expect(CGRectStandardize(CGRect(x: 10, y: 10, width: -4, height: -4)) == CGRect(x: 6, y: 6, width: 4, height: 4))
        #expect(CGRectIsEmpty(.zero) && !CGRectIsInfinite(a) && CGPointEqualToPoint(.zero, .zero) && CGSizeEqualToSize(a.size, b.size) == false)
    }

    @Test func charsetNamesConvertToStringEncodings() {
        let utf8 = CFStringConvertIANACharSetNameToEncoding("UTF-8" as CFString)
        #expect(CFStringConvertEncodingToNSStringEncoding(utf8) == String.Encoding.utf8.rawValue)
        #expect(CFStringConvertEncodingToNSStringEncoding(CFStringConvertIANACharSetNameToEncoding("latin1" as CFString)) == String.Encoding.isoLatin1.rawValue)
        #expect(CFStringConvertIANACharSetNameToEncoding("x-unknown" as CFString) == kCFStringEncodingInvalidId)
        #expect(CFStringConvertNSStringEncodingToEncoding(String.Encoding.utf16LittleEndian.rawValue) == 0x1400_0100)
    }
#endif
}
