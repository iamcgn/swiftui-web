// Shape boolean operations: rectangles combine exactly, curves at flattened precision, line
// operations keep the parts of an outline inside or outside the other shape.
import Testing
import SwiftUI
import SwiftUIWebCore

@Suite struct PathBooleanTests {
    static let a = Path(CGRect(x: 0, y: 0, width: 100, height: 100))
    static let b = Path(CGRect(x: 50, y: 50, width: 100, height: 100))

    private func area(_ path: Path) -> CGFloat {
        path.flattenedPolygons().reduce(0) { $0 + abs(PathBoolean.signedArea($1)) }
    }

    @Test func rectanglesCombineExactly() {
        let union = Self.a.combined(.union, with: Self.b)
        #expect(union.boundingRect == CGRect(x: 0, y: 0, width: 150, height: 150))
        #expect(abs(area(union) - 17500) < 1e-6)
        #expect(union.flattenedPolygons().count == 1)

        let intersection = Self.a.combined(.intersection, with: Self.b)
        #expect(intersection.boundingRect == CGRect(x: 50, y: 50, width: 50, height: 50))
        #expect(abs(area(intersection) - 2500) < 1e-6)

        let difference = Self.a.combined(.subtraction, with: Self.b)
        #expect(difference.boundingRect == CGRect(x: 0, y: 0, width: 100, height: 100))
        #expect(abs(area(difference) - 7500) < 1e-6)

        let symmetric = Self.a.combined(.symmetricDifference, with: Self.b)
        #expect(abs(area(symmetric) - 15000) < 1e-6)
        let pieces = symmetric.flattenedPolygons()
        #expect(PathBoolean.contains(pieces, CGPoint(x: 25, y: 25), evenOdd: false))
        #expect(PathBoolean.contains(pieces, CGPoint(x: 125, y: 125), evenOdd: false))
        #expect(!PathBoolean.contains(pieces, CGPoint(x: 75, y: 75), evenOdd: false))
    }

    @Test func holesAreOrientedAgainstTheirContainer() {
        let ring = Path(CGRect(x: 0, y: 0, width: 100, height: 100)).combined(.subtraction, with: Path(CGRect(x: 25, y: 25, width: 50, height: 50)))
        let polygons = ring.flattenedPolygons()
        #expect(polygons.count == 2)
        let areas = polygons.map(PathBoolean.signedArea)
        #expect(areas.contains { $0 > 0 } && areas.contains { $0 < 0 })
        #expect(!PathBoolean.contains(polygons, CGPoint(x: 50, y: 50), evenOdd: false))
        #expect(PathBoolean.contains(polygons, CGPoint(x: 10, y: 10), evenOdd: false))
    }

    @Test func circlesCombineAtFlattenedPrecision() {
        let circle = Path(ellipseIn: CGRect(x: 0, y: 0, width: 100, height: 100))
        let square = Path(CGRect(x: 50, y: 0, width: 100, height: 100))
        let union = circle.combined(.union, with: square)
        // The circle's area (π·50²) plus the square's, minus the overlapping half disc.
        let expected = CGFloat.pi * 2500 + 10000 - CGFloat.pi * 1250
        #expect(abs(area(union) - expected) / expected < 0.01)
        let intersection = circle.combined(.intersection, with: square)
        #expect(abs(area(intersection) - CGFloat.pi * 1250) / (CGFloat.pi * 1250) < 0.01)
    }

    @Test func disjointAndNestedShapes() {
        let far = Path(CGRect(x: 200, y: 0, width: 50, height: 50))
        #expect(Self.a.combined(.union, with: far).flattenedPolygons().count == 2)
        #expect(Self.a.combined(.intersection, with: far).isEmpty)
        let inner = Path(CGRect(x: 20, y: 20, width: 10, height: 10))
        #expect(abs(area(Self.a.combined(.union, with: inner)) - 10000) < 1e-6)
        #expect(abs(area(Self.a.combined(.intersection, with: inner)) - 100) < 1e-6)
    }

    @Test func lineOperationsClipTheOutline() {
        let inside = Self.a.lineClipped(by: Self.b, keepInside: true)
        let outside = Self.a.lineClipped(by: Self.b, keepInside: false)
        func length(_ path: Path) -> CGFloat {
            path.flattenedPolylines().reduce(0) { sum, line in
                sum + zip(line, line.dropFirst()).reduce(0) { $0 + $1.0._distance(to: $1.1) }
            }
        }
        #expect(abs(length(inside) - 100) < 1e-6)     // two 50 pt edges of A run inside B
        #expect(abs(length(outside) - 300) < 1e-6)
        #expect(inside.boundingRect == CGRect(x: 50, y: 50, width: 50, height: 50))
    }

    @MainActor @Test func shapesExposeTheOperations() {
        let shape = Rectangle().union(Circle()).intersection(Rectangle()).subtracting(Capsule()).symmetricDifference(Ellipse())
        _ = shape.path(in: CGRect(x: 0, y: 0, width: 40, height: 20))
        let lines = Circle().lineIntersection(Rectangle()).lineSubtraction(Rectangle())
        _ = lines.path(in: CGRect(x: 0, y: 0, width: 40, height: 20))
    }
}
