// Tier A: our layout must reproduce the probe frames Apple's SwiftUI produced for every fixture
// (Fixtures/Goldens/<name>/frames.json). Exact comparison, no tolerance.
#if !os(WASI)   // reads golden files from disk; the wasm test runner has no package directory
import Testing
import SwiftUI
import SwiftUIWebHeadless
import FixtureKit
import SwiftUIWebFixtures
import Foundation

struct GoldenFrames: Decodable {
    struct Rect: Decodable { let x, y, width, height: Double }
    struct Step: Decodable { let name: String; let frames: [String: Rect] }
    let fixture: String
    let frames: [String: Rect]
    /// Behaviour fixtures: frames after each step, in order.
    let steps: [Step]?
}

enum Goldens {
    static let root: URL = {
        var url = URL(fileURLWithPath: #filePath)
        while url.lastPathComponent != "Tests" { url.deleteLastPathComponent() }
        url.deleteLastPathComponent()
        return url.appendingPathComponent("Fixtures/Goldens")
    }()

    static func frames(for fixture: Fixture) throws -> GoldenFrames? {
        let file = root.appendingPathComponent(fixture.name).appendingPathComponent("frames.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try JSONDecoder().decode(GoldenFrames.self, from: Data(contentsOf: file))
    }

    /// Fixture names whose goldens exist and whose feature area is implemented.
    static let enabledPrefixes = ["layout/", "paint/", "text/", "button/", "foreach/", "section/", "scroll/", "image/", "color/", "shape/"]

    /// The fixtures' asset catalog as `scripts/assets.py` reads it (Fixtures/Assets.manifest.json).
    static func assets() throws -> AssetCatalog {
        try AssetCatalog(contentsOf: root.deletingLastPathComponent().appendingPathComponent("Assets.manifest.json"))
    }

    @MainActor
    static func textEngine() throws -> RecordedTextEngine {
        try RecordedTextEngine(contentsOf: root.appendingPathComponent("text-metrics.json"))
    }
}

@Suite @MainActor struct GoldenFrameTests {
    nonisolated static var fixtureNames: [String] {
        AllFixtures.all.filter { fixture in Goldens.enabledPrefixes.contains { fixture.name.hasPrefix($0) } }.map(\.name)
    }

    @Test(arguments: fixtureNames)
    func framesMatchGolden(name: String) throws {
        let fixture = try #require(AllFixtures.all.first { $0.name == name })
        let golden = try #require(try Goldens.frames(for: fixture), "missing golden for \(name); run scripts/gen-goldens.sh")
        let engine = try Goldens.textEngine()
        let runner = FixtureRunner(fixture, textEngine: engine, assets: try Goldens.assets())
        try compare(runner.layoutFrames(), to: golden.frames, label: name)
        #expect(engine.misses.isEmpty, "\(name): no recorded text metrics for \(engine.misses)")

        // Behaviour steps: mutate the model exactly as the harness did and compare again.
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
            let close = abs(actual.minX - expectedRect.minX) < 1e-9 && abs(actual.minY - expectedRect.minY) < 1e-9
                && abs(actual.width - expectedRect.width) < 1e-9 && abs(actual.height - expectedRect.height) < 1e-9
            #expect(close, "\(label)/\(id): \(actual) != \(expectedRect)")
        }
        #expect(Set(ours.keys) == Set(golden.keys), "\(label): probe sets differ")
    }
}
#endif
