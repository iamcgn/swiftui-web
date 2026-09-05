// Redaction: placeholder layouts (one advance per character, spaces included, rounded to the half
// point, wrapped by character), placeholder bars on the baseline, privacy on the plain layout,
// unredacted, and symbol placeholders.
import Testing
import SwiftUI
import SwiftUIWebHeadless

#if !os(WASI)
@Suite @MainActor struct RedactionTests {
    private static let system13 = ResolvedFont(family: "system", size: 13, weight: .regular, italic: false, textStyle: nil)

    private func runtime<V: View>(_ view: V, size: CGSize = CGSize(width: 200, height: 100)) -> Runtime {
        var entries: [String: RecordedTextEngine.Entry] = [:]
        for (word, width) in [("Hidden", 42.0), ("Hello", 31.0)] {
            entries[RecordedTextEngine.key(font: Self.system13, width: nil, string: word)] = .init(width: width, height: 16, firstBaseline: 13, lastBaseline: 13)
        }
        let runtime = Runtime()
        runtime.textEngine = RecordedTextEngine(entries: entries)
        runtime.mount(view)
        runtime.layout(in: size)
        return runtime
    }

    private func commands(_ runtime: Runtime) -> [String] { runtime.render(scale: 2).commands.map(\.description) }

    @Test func placeholderWidthsAndBars() {
        // Ten characters at 13 pt: 63 wide (measured), one bar of the cap height on the baseline.
        let runtime = runtime(Text("iiiiiiiiii").redacted(reason: .placeholder)._probe("text"))
        #expect(runtime.probeFrames["text"] == CGRect(x: 68.5, y: 42, width: 63, height: 16))
        let bars = commands(runtime).filter { $0.hasPrefix("fillRRect") }
        #expect(bars == ["fillRRect(68.5, 45.5, 63, 9.5) r=1.9 #000000@0.137"])
        // Nine characters round to the nearest half (56.5); spaces count; letters do not matter.
        #expect(self.runtime(Text("a b c d e").redacted(reason: .placeholder)._probe("t")).probeFrames["t"]?.width == 56.5)
        #expect(self.runtime(Text("MMMMMMMMM").redacted(reason: .placeholder)._probe("t")).probeFrames["t"]?.width == 56.5)
        #expect(_Placeholder.advance(for: ResolvedFont(family: "system", size: 22, weight: .regular, italic: false, textStyle: nil)) == 10.5)
        #expect(_Placeholder.advance(for: ResolvedFont(family: "system", size: 15, weight: .regular, italic: false, textStyle: nil)) == 7.1)
    }

    @Test func wrappedPlaceholdersStretchAllButTheLastLine() {
        // 40 characters at 6.3 pt in 100 pt: 15 per line, so three lines; the last holds ten.
        let runtime = runtime(Text("abcdefghijklmnopqrstuvwxyzabcdefghijklmn").frame(width: 100, alignment: .leading).redacted(reason: .placeholder)._probe("t"))
        #expect(runtime.probeFrames["t"]?.height == 48)
        let bars = commands(runtime).filter { $0.hasPrefix("fillRRect") }
        #expect(bars.count == 3 && bars[0].contains(", 100, 9.5)") && bars[1].contains(", 100, 9.5)") && bars[2].contains(", 63, 9.5)"))
    }

    @Test func privacyKeepsThePlainLayoutAndUnredactedOptsOut() {
        // Privacy alone leaves ordinary text; a privacy-sensitive text keeps its width under a bar.
        let plain = runtime(Text("Hello").redacted(reason: .privacy))
        #expect(commands(plain).contains { $0.hasPrefix("drawText(\"Hello\"") })
        let secret = runtime(Text("Hidden").privacySensitive().redacted(reason: .privacy)._probe("s"))
        #expect(secret.probeFrames["s"]?.width == 42 && commands(secret).contains { $0.hasPrefix("fillRRect") } && !commands(secret).contains { $0.hasPrefix("drawText") })
        // Under the placeholder reason a privacy-sensitive text draws as itself (measured).
        let sensitive = runtime(Text("Hello").privacySensitive().redacted(reason: .placeholder)._probe("s"))
        #expect(sensitive.probeFrames["s"]?.width == 31 && commands(sensitive).contains { $0.hasPrefix("drawText(\"Hello\"") })
        // unredacted clears the reasons; invalidated changes nothing.
        let un = runtime(VStack { Text("Hello").unredacted(); Text("Hello") }.redacted(reason: .placeholder))
        #expect(commands(un).filter { $0.hasPrefix("drawText") }.count == 1 && commands(un).filter { $0.hasPrefix("fillRRect") }.count == 1)
        #expect(commands(runtime(Text("Hello").redacted(reason: .invalidated))).contains { $0.hasPrefix("drawText") })
        var environment = EnvironmentValues()
        environment.redactionReasons = [.placeholder, .privacy]
        #expect(environment._drawsPlaceholders && environment.redactionReasons.contains(.privacy))
    }

    @Test func symbolPlaceholdersTakeTheMeasuredFrameAndSquare() {
        // At 22 pt: a 26 × 25 frame with a 22 pt square centred, whatever the symbol.
        let runtime = runtime(Image(systemName: "star").font(.system(size: 22)).redacted(reason: .placeholder)._probe("i"))
        #expect(runtime.probeFrames["i"]?.size == CGSize(width: 26, height: 25))
        let squares = commands(runtime).filter { $0.hasPrefix("fillRect") }
        #expect(squares == ["fillRect(89, 39, 22, 22) #000000@0.137"])
        #expect(self.runtime(Image(systemName: "gear").redacted(reason: .placeholder)._probe("i")).probeFrames["i"]?.size == CGSize(width: 15, height: 15))
    }
}
#endif
