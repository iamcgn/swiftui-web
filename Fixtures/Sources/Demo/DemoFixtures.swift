// Golden-less demonstrations (decision 0016, `demo/` prefix): behaviour no golden can capture,
// shown in the gallery and named by a support row. Like `probe/`, no tier enables the prefix.
import SwiftUI
import FixtureKit

@Observable final class PasteboardDemoModel {
    var pasted = "Nothing pasted yet"
}

public enum DemoFixtures {
    public static let all: [Fixture] = [pasteboard]

    /// `copyable` puts the text on the pasteboard through the host; `PasteButton` reads it back.
    public static let pasteboard = Fixture("demo/pasteboard", size: CGSize(width: 360, height: 160), model: { PasteboardDemoModel() }, steps: []) { model in
        VStack(spacing: 12) {
            #if os(iOS)   // `copyable` is macOS API; the iOS builds render only ios/ fixtures
            Text("Copy me").probe("copyable")
            #else
            Text("Copy me").copyable(["Copy me"]).probe("copyable")
            #endif
            PasteButton(payloadType: String.self) { strings in model.pasted = strings.first ?? "" }.probe("paste")
            Text(model.pasted).probe("pasted")
        }
    }
}
