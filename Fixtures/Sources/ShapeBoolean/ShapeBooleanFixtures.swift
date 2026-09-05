// Shape boolean operations: a circle against a square, filled and stroked, plus the line
// operations; the combined outlines are compared with SwiftUI's pixel for pixel.
import SwiftUI
import FixtureKit

public enum ShapeBooleanFixtures {
    static let square = Rectangle().offset(x: 30, y: 0)

    public static let fills = Fixture("shapebool/fills", size: CGSize(width: 380, height: 100), content: {
        HStack(spacing: 20) {
            Circle().union(square).fill(Color.blue).frame(width: 60, height: 60).probe("union")
            Circle().intersection(square).fill(Color.blue).frame(width: 60, height: 60).probe("intersection")
            Circle().subtracting(square).fill(Color.blue).frame(width: 60, height: 60).probe("subtracting")
            Circle().symmetricDifference(square).fill(Color.blue).frame(width: 60, height: 60).probe("symmetric")
        }
        .probe("row")
    })

    public static let strokes = Fixture("shapebool/strokes", size: CGSize(width: 380, height: 100), content: {
        HStack(spacing: 20) {
            Circle().union(square).stroke(Color.red, lineWidth: 2).frame(width: 60, height: 60).probe("union")
            Circle().intersection(square).stroke(Color.red, lineWidth: 2).frame(width: 60, height: 60).probe("intersection")
            Circle().lineIntersection(square).stroke(Color.red, lineWidth: 2).frame(width: 60, height: 60).probe("lineIntersection")
            Circle().lineSubtraction(square).stroke(Color.red, lineWidth: 2).frame(width: 60, height: 60).probe("lineSubtraction")
        }
        .probe("row")
    })

    public static let all: [Fixture] = [fills, strokes]
}
