// Tier A: our layout must reproduce the probe frames Apple's SwiftUI produced for every fixture
// (Fixtures/Goldens/<name>/frames.json). Exact comparison, no tolerance.
import Testing
import SwiftUI
import FixtureKit
import SwiftUIWebFixtures
#if canImport(Foundation)
import Foundation
#endif

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
    static let enabledPrefixes = ["layout/"]
}

@Suite @MainActor struct GoldenFrameTests {
    nonisolated static var fixtureNames: [String] {
        AllFixtures.all.filter { fixture in Goldens.enabledPrefixes.contains { fixture.name.hasPrefix($0) } }.map(\.name)
    }

    @Test(arguments: fixtureNames)
    func framesMatchGolden(name: String) throws {
        let fixture = try #require(AllFixtures.all.first { $0.name == name })
        let golden = try #require(try Goldens.frames(for: fixture), "missing golden for \(name); run scripts/gen-goldens.sh")
        let ours = fixture.layoutFrames()
        for (id, expected) in golden.frames.sorted(by: { $0.key < $1.key }) {
            let actual = try #require(ours[id], "\(name): probe \(id) not recorded")
            let expectedRect = CGRect(x: expected.x, y: expected.y, width: expected.width, height: expected.height)
            #expect(actual == expectedRect, "\(name)/\(id)")
        }
        #expect(Set(ours.keys) == Set(golden.frames.keys), "\(name): probe sets differ")
    }
}
