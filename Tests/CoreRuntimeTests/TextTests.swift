// Phase 1 step 6: Text, Font, LocalizedStringKey and the text engine contract.
import Testing
import SwiftUI
import SwiftUIWebHeadless

#if !os(WASI)
@MainActor private func engine() -> RecordedTextEngine {
    // The default font is the 13 pt system font (decision 0010); the numbers here are synthetic.
    let body = ResolvedFont(family: "system", size: 13, weight: .regular, italic: false, textStyle: nil)
    let title = ResolvedFont(family: "system", size: 22, weight: .regular, italic: false, textStyle: .title)
    var entries: [String: RecordedTextEngine.Entry] = [:]
    func add(_ font: ResolvedFont, _ s: String, width: CGFloat? = nil, w: Double, h: Double, base: Double) {
        entries[RecordedTextEngine.key(font: font, width: width, string: s)] =
            .init(width: w, height: h, firstBaseline: base, lastBaseline: base)
    }
    add(body, "Hello", w: 31, h: 18.5, base: 14)
    add(ResolvedFont(family: "system", size: 13, weight: .regular, italic: false, textStyle: .body), "Hello", w: 31, h: 18.5, base: 14)
    add(title, "Hello", w: 52, h: 33, base: 24)
    add(body, "A long sentence", w: 100, h: 18.5, base: 14)
    add(body, "A long sentence", width: 60, w: 58, h: 37, base: 14)
    add(body, "Count: 3", w: 52, h: 18.5, base: 14)
    add(ResolvedFont(family: "system", size: 22, weight: .bold, italic: false, textStyle: .title, weightOverridden: true), "Hello", w: 55, h: 33, base: 24)
    let fonts = ["system:13:400:default": RecordedTextEngine.FontEntry(lineHeight: 18.5, spacingBelow: 11, spacingAbove: 6, textToText: 1)]
    return RecordedTextEngine(entries: entries, fonts: fonts)
}

@Suite @MainActor struct TextTests {
    private func frames<V: View>(_ view: V, size: CGSize = CGSize(width: 200, height: 100)) -> (Runtime, [String: CGRect]) {
        let runtime = Runtime()
        runtime.textEngine = engine()
        runtime.mount(view)
        runtime.layout(in: size)
        return (runtime, runtime.probeFrames)
    }

    @Test func fontKeysMatchHarnessConvention() {
        let profile = PlatformProfile.macOS
        #expect(Font.body.resolve(profile: profile).key == "style:body")
        #expect(Font.title.resolve(profile: profile).key == "style:title")
        #expect(Font.system(size: 20).resolve(profile: profile).key == "system:20:400:default")
        #expect(Font.system(size: 20, weight: .bold, design: .rounded).resolve(profile: profile).key == "system:20:700:rounded")
        #expect(Font.body.bold().resolve(profile: profile).key == "style:body:w600")
        #expect(Font.title.bold().resolve(profile: profile).key == "style:title:w700")
        #expect(Font.headline.bold().resolve(profile: profile).key == "style:headline:w800")
        #expect(Font.system(size: 20).bold().resolve(profile: profile).key == "system:20:700:default")
        #expect(Font.body.bold().weight(.light).resolve(profile: profile).key == "style:body:w300")
        #expect(Font.body.weight(.bold).resolve(profile: profile).key == "style:body:w700")
        #expect(Font.system(size: 11.5).resolve(profile: profile).key == "system:11.5:400:default")
        #expect(Font.headline.resolve(profile: profile).key == "style:headline")
        #expect(Font.system(.title, design: .rounded, weight: .medium).resolve(profile: profile).key == "style:title:w500:rounded")
        #expect(Font.caption2.resolve(profile: profile).key == "style:caption2")
    }

    @Test func localizedStringKeyInterpolation() {
        let count = 3
        let key: LocalizedStringKey = "Count: \(count)"
        #expect(key.key == "Count: 3")
        #expect(Text("Count: \(count)").resolvedString == "Count: 3")
        #expect(Text(verbatim: "x\(1)").resolvedString == "x1")
        let s = "dyn"
        #expect(Text(s).resolvedString == "dyn")
        #expect((Text("a") + Text("b")).resolvedString == "ab")
    }

    @Test func textMeasuresAndCentres() {
        let (_, f) = frames(Text("Hello")._probe("t"))
        #expect(f["t"] == CGRect(x: 84.5, y: 40.75, width: 31, height: 18.5))
    }

    @Test func fontFromEnvironmentAndTextModifiers() {
        let (_, f) = frames(VStack(spacing: 0) {
            Text("Hello")._probe("env")
            Text("Hello").font(.body)._probe("own")
            Text("Hello").bold()._probe("bold")
        }.font(.title))
        #expect(f["env"]?.size == CGSize(width: 52, height: 33))
        #expect(f["own"]?.size == CGSize(width: 31, height: 18.5))
        #expect(f["bold"]?.size == CGSize(width: 55, height: 33))   // title from the environment; its bold trait is w700
    }

    @Test func wrappingUsesProposedWidth() {
        let (_, f) = frames(VStack(alignment: .leading, spacing: 0) {
            Text("A long sentence")._probe("free")
            Text("A long sentence")._probe("narrow").frame(width: 60)
        })
        #expect(f["free"]?.size == CGSize(width: 100, height: 18.5))
        #expect(f["narrow"]?.size == CGSize(width: 58, height: 37))
    }

    @Test func baselineAlignment() {
        let (_, f) = frames(HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("Hello").font(.title)._probe("big")
            Text("Hello")._probe("small")
            Color.red.frame(width: 10, height: 10)._probe("box")
        })
        let big = f["big"]!, small = f["small"]!, box = f["box"]!
        #expect(small.minY - big.minY == 10)          // 24 - 14
        #expect(box.maxY == big.minY + 24)            // a box's baseline is its bottom
    }

    @Test func textSpacingCategories() {
        let (_, f) = frames(VStack {
            Text("Hello")._probe("t1")
            Text("Hello")._probe("t2")
            Color.red.frame(width: 10, height: 10)._probe("box")
            Text("Hello")._probe("t3")
        }, size: CGSize(width: 200, height: 300))
        #expect(f["t2"]!.minY - f["t1"]!.maxY == 1)
        #expect(f["box"]!.minY - f["t2"]!.maxY == 11)
        #expect(f["t3"]!.minY - f["box"]!.maxY == 6)
        let (_, h) = frames(HStack { Text("Hello")._probe("a"); Text("Hello")._probe("b") })
        #expect(h["b"]!.minX - h["a"]!.maxX == 8)
    }

    @Test func missingRecordingsAreReported() {
        let runtime = Runtime()
        let recorded = engine()
        runtime.textEngine = recorded
        runtime.mount(Text("Unknown"))
        runtime.layout(in: CGSize(width: 100, height: 100))
        #expect(recorded.misses.first?.hasSuffix("|Unknown") == true)
    }
}
#endif
