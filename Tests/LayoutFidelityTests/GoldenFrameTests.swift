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
    let fixture: String
    let frames: [String: Rect]
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
    static let enabledPrefixes = ["layout/", "text/"]

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
        let ours = fixture.layoutFrames(textEngine: engine)
        #expect(engine.misses.isEmpty, "\(name): no recorded text metrics for \(engine.misses)")
        for (id, expected) in golden.frames.sorted(by: { $0.key < $1.key }) {
            let actual = try #require(ours[id], "\(name): probe \(id) not recorded")
            let expectedRect = CGRect(x: expected.x, y: expected.y, width: expected.width, height: expected.height)
            // Exact up to floating-point summation order (Apple's frames carry 1-ulp noise).
            let close = abs(actual.minX - expectedRect.minX) < 1e-9 && abs(actual.minY - expectedRect.minY) < 1e-9
                && abs(actual.width - expectedRect.width) < 1e-9 && abs(actual.height - expectedRect.height) < 1e-9
            #expect(close, "\(name)/\(id): \(actual) != \(expectedRect)")
        }
        #expect(Set(ours.keys) == Set(golden.frames.keys), "\(name): probe sets differ")
    }
}
#endif
