// `commonPrefix(with:options:)` (WebFoundation's StringCompare.swift on wasm): Clendar merges
// event titles by the start they share, ignoring case. The cases run against Foundation on
// macOS and Linux too, so the wasm form answers as Apple's does.
import Testing
import WebFoundation

@Suite struct CommonPrefixTests {
    @Test func theSharedStartComesFromTheReceiver() {
        #expect("Hello world".commonPrefix(with: "help") == "Hel")
        #expect("Team sync".commonPrefix(with: "team SYNC notes", options: .caseInsensitive) == "Team sync")
        #expect("Team sync".commonPrefix(with: "team SYNC notes") == "")
        #expect("abc".commonPrefix(with: "") == "" && "".commonPrefix(with: "abc") == "")
        #expect("abc".commonPrefix(with: "abc") == "abc")
        let line = "Standup: daily"
        #expect(line[line.startIndex...].commonPrefix(with: "Standup: weekly") == "Standup: ")
    }
}
