// Tier A for paths: SwiftUIWeb's `Path` must reproduce Apple's element for element for every
// shared request (Fixtures/Goldens/shape/paths.json, from `scripts/gen-goldens.sh shape/`).
// Coordinates within 1e-3 (Apple's carry CGPath rounding noise); stroked outlines, which
// SwiftUIWeb approximates, by bounding box only.
#if !os(WASI)
import Testing
import SwiftUI
import FixtureKit
import SwiftUIWebFixtures
import Foundation

struct PathGoldens: Decodable {
    let macOS: String
    let paths: [String: String]
}

@Suite @MainActor struct PathGoldenTests {
    nonisolated static var requestNames: [String] { PathRequests.all.map(\.name) }

    static func goldens() throws -> PathGoldens {
        let file = Goldens.root.appendingPathComponent("shape/paths.json")
        return try JSONDecoder().decode(PathGoldens.self, from: Data(contentsOf: file))
    }

    @Test(arguments: requestNames)
    func pathMatchesApple(name: String) throws {
        let request = try #require(PathRequests.all.first { $0.name == name })
        let apple = try #require(try Self.goldens().paths[name], "missing path golden for \(name); run scripts/gen-goldens.sh shape/")
        let ours = request.make()
        let expected = try #require(Path(apple), "\(name): Apple's description did not parse: \(apple)")
        switch request.comparison {
        case .elements:
            #expect(ours.elements.count == expected.elements.count, "\(name):\n\(ours.description)\n≠\n\(apple)")
            for (a, b) in zip(ours.elements, expected.elements) {
                #expect(close(a, b), "\(name):\n\(ours.description)\n≠\n\(apple)")
            }
        case .bounds:
            // Bounds include Bézier control points, and Apple's round joins are wider arcs than
            // our discs, so their control points reach further: allow a point.
            let a = ours.boundingRect, b = expected.boundingRect
            let tolerance = 1.0
            #expect(abs(a.minX - b.minX) < tolerance && abs(a.minY - b.minY) < tolerance
                    && abs(a.maxX - b.maxX) < tolerance && abs(a.maxY - b.maxY) < tolerance,
                    "\(name): bounds \(a) vs \(b)")
        }
    }

    private func close(_ a: CGPoint, _ b: CGPoint) -> Bool {
        abs(a.x - b.x) <= 1e-3 + abs(b.x) * 1e-5 && abs(a.y - b.y) <= 1e-3 + abs(b.y) * 1e-5
    }

    private func close(_ a: Path.Element, _ b: Path.Element) -> Bool {
        switch (a, b) {
        case (.move(let p), .move(let q)), (.line(let p), .line(let q)):
            return close(p, q)
        case (.quadCurve(let p, let c), .quadCurve(let q, let d)):
            return close(p, q) && close(c, d)
        case (.curve(let p, let c1, let c2), .curve(let q, let d1, let d2)):
            return close(p, q) && close(c1, d1) && close(c2, d2)
        case (.closeSubpath, .closeSubpath):
            return true
        default:
            return false
        }
    }
}
#endif
