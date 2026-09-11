// Tier A for UIKitWeb: our layout must reproduce the probe frames Apple's UIKit produced for
// every UIKit fixture (Fixtures/Goldens/uikit/<name>/frames.json, from
// scripts/gen-goldens-sim.sh uikit on an iPhone simulator). Exact comparison, no tolerance; the text engine
// replays the UILabel measurements recorded next to the goldens (uikit/text-metrics.json).
#if !os(WASI)   // reads golden files from disk; the wasm test runner has no package directory
import Testing
import UIKit
import UIKitFixtureKit
import UIKitFixtures
import WebGraphicsHeadless
import Foundation

struct GoldenFrames: Decodable {
    struct Rect: Decodable { let x, y, width, height: Double }
    struct Step: Decodable { let name: String; let frames: [String: Rect] }
    let fixture: String
    let frames: [String: Rect]
    let steps: [Step]?
}

enum Goldens {
    /// Fixtures/Goldens at the repository root (this package lives under Packages/).
    static let root: URL = {
        var url = URL(fileURLWithPath: #filePath)
        while url.lastPathComponent != "Packages" { url.deleteLastPathComponent() }
        url.deleteLastPathComponent()
        return url.appendingPathComponent("Fixtures/Goldens")
    }()

    static func frames(for fixture: UIKitFixture) throws -> GoldenFrames? {
        let file = root.appendingPathComponent(fixture.name).appendingPathComponent("frames.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try JSONDecoder().decode(GoldenFrames.self, from: Data(contentsOf: file))
    }

    static let textMetrics = root.appendingPathComponent("uikit/text-metrics.json")

    @MainActor
    static func textEngine() throws -> RecordedTextEngine {
        try RecordedTextEngine(contentsOf: textMetrics)
    }
}

@Suite @MainActor struct UIKitGoldenFrameTests {
    nonisolated static var fixtureNames: [String] { AllUIKitFixtures.all.map(\.name) }

    @Test(arguments: fixtureNames)
    func framesMatchGolden(name: String) throws {
        let fixture = try #require(AllUIKitFixtures.all.first { $0.name == name })
        let golden = try #require(try Goldens.frames(for: fixture), "missing golden for \(name); run scripts/gen-goldens-sim.sh uikit")
        let engine = try Goldens.textEngine()
        let runner = UIKitFixtureRunner(fixture, textEngine: engine)
        try compare(runner.layoutFrames(), to: golden.frames, label: name)
        #expect(engine.misses.isEmpty, "\(name): no recorded text metrics for \(engine.misses)")

        let steps = golden.steps ?? []
        #expect(steps.map(\.name) == fixture.stepNames, "\(name): golden steps differ from the fixture's; regenerate")
        for (index, step) in steps.enumerated() where index < fixture.stepNames.count {
            runner.apply(step: index)
            try compare(runner.layoutFrames(), to: step.frames, label: "\(name)/\(step.name)")
        }
        #expect(engine.misses.isEmpty, "\(name): no recorded text metrics for \(engine.misses)")
    }

    private func compare(_ ours: [String: CGRect], to golden: [String: GoldenFrames.Rect], label: String) throws {
        for (id, expected) in golden.sorted(by: { $0.key < $1.key }) {
            let actual = try #require(ours[id], "\(label): probe \(id) not recorded")
            let expectedRect = CGRect(x: expected.x, y: expected.y, width: expected.width, height: expected.height)
            // Exact up to floating-point summation order (Apple's frames carry 1-ulp noise).
            let tolerance = 1e-9
            let close = abs(actual.minX - expectedRect.minX) < tolerance && abs(actual.minY - expectedRect.minY) < tolerance
                && abs(actual.width - expectedRect.width) < tolerance && abs(actual.height - expectedRect.height) < tolerance
            #expect(close, "\(label)/\(id): \(actual) != \(expectedRect)")
        }
        #expect(Set(ours.keys) == Set(golden.keys), "\(label): probe sets differ")
    }
}

/// UIFont's metrics (SF's hhea table scaled to the point size) against what UIKit reports for
/// every font the fixtures use.
@Suite @MainActor struct UIFontMetricsTests {
    struct Document: Decodable { let fonts: [String: [String: Double]] }

    @Test func fontsMatchRecorded() throws {
        let document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: Goldens.textMetrics))
        #expect(!document.fonts.isEmpty)
        for font in UIKitTextMetricsRequests.fonts {
            let recorded = try #require(document.fonts[font.key], "no recorded metrics for \(font.key)")
            let ours = font.uiFont
            for (name, value) in [("pointSize", ours.pointSize), ("ascender", ours.ascender), ("descender", ours.descender),
                                  ("lineHeight", ours.lineHeight), ("capHeight", ours.capHeight), ("xHeight", ours.xHeight), ("leading", ours.leading)] {
                let expected = try #require(recorded[name])
                #expect(abs(value - expected) < 0.01, "\(font.key).\(name): \(value) != \(expected)")
            }
        }
    }
}
#endif
