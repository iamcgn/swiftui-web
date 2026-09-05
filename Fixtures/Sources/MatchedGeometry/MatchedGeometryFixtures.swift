// matchedGeometryEffect at rest: non-source views take their source's geometry (frame,
// position or size); their own layout slots stay where the stack put them.
import SwiftUI
import FixtureKit

public enum MatchedGeometryFixtures {
    struct Follower: View {
        @Namespace private var space
        var body: some View {
            ZStack(alignment: .topLeading) {
                Color.red.frame(width: 40, height: 40)
                    .matchedGeometryEffect(id: "box", in: space)
                    .probe("source")
                    .padding(EdgeInsets(top: 20, leading: 120, bottom: 0, trailing: 0))
                Color.blue.frame(width: 80, height: 20)
                    .matchedGeometryEffect(id: "box", in: space, isSource: false)
                    .probe("frame")
                Color.green.frame(width: 30, height: 30)
                    .matchedGeometryEffect(id: "box", in: space, properties: .position, isSource: false)
                    .probe("position")
                    .padding(.top, 70)
                Color.orange.frame(width: 20, height: 60)
                    .matchedGeometryEffect(id: "box", in: space, properties: .size, isSource: false)
                    .probe("size")
                    .padding(.leading, 60)
            }
            .frame(width: 200, height: 100, alignment: .topLeading)
            .probe("stack")
        }
    }

    public static let follower = Fixture("matched/follower", size: CGSize(width: 300, height: 140), content: { Follower() })


    /// One source and one follower per cell: anchors × follower sizes for `.frame`, and the
    /// position-only and size-only modes; followers land on their own source only.
    struct Cell: View {
        let anchor: UnitPoint
        let size: CGSize
        let properties: MatchedGeometryProperties
        let name: String
        @Namespace private var space
        var body: some View {
            ZStack(alignment: .topLeading) {
                Color.red.frame(width: 40, height: 40)
                    .matchedGeometryEffect(id: "box", in: space)
                    .padding(EdgeInsets(top: 70, leading: 90, bottom: 0, trailing: 0))
                if size == .zero {
                    Color.blue
                        .matchedGeometryEffect(id: "box", in: space, properties: properties, anchor: anchor, isSource: false)
                        .probe(name)
                } else {
                    Color.blue.frame(width: size.width, height: size.height)
                        .matchedGeometryEffect(id: "box", in: space, properties: properties, anchor: anchor, isSource: false)
                        .probe(name)
                }
            }
            .frame(width: 200, height: 160, alignment: .topLeading)
            .probe("cell-\(name)")
        }
    }

    struct Grid: View {
        var body: some View {
            let anchors: [(String, UnitPoint)] = [("tl", .topLeading), ("c", .center), ("br", .bottomTrailing)]
            let sizes: [(String, CGSize)] = [("wide", CGSize(width: 80, height: 20)), ("tall", CGSize(width: 20, height: 60)), ("small", CGSize(width: 20, height: 20))]
            VStack(spacing: 0) {
                ForEach(anchors, id: \.0) { aname, anchor in
                    HStack(spacing: 0) {
                        ForEach(sizes, id: \.0) { sname, size in
                            Cell(anchor: anchor, size: size, properties: .frame, name: "frame-\(aname)-\(sname)")
                        }
                    }
                }
                HStack(spacing: 0) {
                    Cell(anchor: .topLeading, size: CGSize(width: 80, height: 20), properties: .position, name: "position-tl-wide")
                    Cell(anchor: .bottomTrailing, size: CGSize(width: 20, height: 60), properties: .position, name: "position-br-tall")
                    Cell(anchor: .center, size: CGSize(width: 80, height: 20), properties: .size, name: "size-c-wide")
                }
                HStack(spacing: 0) {
                    Cell(anchor: .center, size: .zero, properties: .size, name: "size-c-flex")
                    Cell(anchor: .center, size: .zero, properties: .frame, name: "frame-c-flex")
                    Cell(anchor: .topLeading, size: .zero, properties: .frame, name: "frame-tl-flex")
                }
            }
            .probe("grid")
        }
    }

    public static let anchors = Fixture("matched/anchors", size: CGSize(width: 620, height: 820), content: { Grid() })

    public static let all: [Fixture] = [follower, anchors]
}
