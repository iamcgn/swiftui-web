// Right-to-left layout fixtures (sw-rtl, Docs/elements/Layout.md): `layoutDirection` set on a
// subtree mirrors every container's placements (stacks, Spacer, padding, frame alignment,
// ZStack, grids, a custom Layout), a left-to-right island inside stays as written, text and
// labels align to the leading (right) edge, shapes follow their `layoutDirectionBehavior` and a
// horizontal scroll view starts at its trailing end. (Controls were measured on a macOS 26.6
// golden whose control sizes the clone does not model; RTLTests holds them.)
import SwiftUI
import FixtureKit

/// A triangle pointing to the trailing edge: mirrored in a right-to-left layout by default.
struct ArrowShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// The same triangle declaring that it never mirrors.
struct FixedArrowShape: Shape {
    func path(in rect: CGRect) -> Path { ArrowShape().path(in: rect) }
    var layoutDirectionBehavior: LayoutDirectionBehavior { .fixed }
}

public enum RTLFixtures {
    static func box(_ color: Color, _ w: CGFloat, _ h: CGFloat) -> some View { color.frame(width: w, height: h) }

    public static let stacks = Fixture("layout/rtl-stacks", size: CGSize(width: 320, height: 260)) {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                box(.red, 40, 30).probe("a")
                box(.blue, 60, 30).probe("b")
                Spacer()
                box(.green, 30, 30).probe("c")
            }
            .probe("hstack")
            box(.orange, 50, 20).padding(.leading, 30).probe("padded")
            box(.purple, 40, 20).frame(width: 120, alignment: .leading).probe("framed")
            ZStack(alignment: .topLeading) {
                box(.gray, 100, 40).probe("zback")
                box(.black, 20, 20).probe("zfront")
            }
            .probe("zstack")
            HStack {
                box(.red, 30, 20).probe("ltrA")
                box(.blue, 30, 20).probe("ltrB")
            }
            .environment(\.layoutDirection, .leftToRight)
            .probe("island")
            Text("One").probe("text")
            box(.cyan, 30, 20).alignmentGuide(.leading) { _ in -10 }.probe("guided")
        }
        .frame(width: 300, alignment: .leading)
        .probe("vstack")
        .environment(\.layoutDirection, .rightToLeft)
    }

    public static let grid = Fixture("layout/rtl-grid", size: CGSize(width: 320, height: 220)) {
        VStack(spacing: 16) {
            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    box(.red, 40, 30).probe("a")
                    box(.blue, 60, 30).probe("b")
                    box(.green, 30, 30).probe("c")
                }
                GridRow {
                    box(.orange, 100, 30).gridCellColumns(2).probe("d")
                    box(.purple, 30, 30).probe("e")
                }
                GridRow {
                    box(.gray, 40, 30).gridColumnAlignment(.trailing).probe("f")
                }
            }
            .probe("grid")
            LazyVGrid(columns: [GridItem(.fixed(40)), GridItem(.fixed(40)), GridItem(.fixed(40))], spacing: 8) {
                box(.red, 40, 20).probe("l0")
                box(.blue, 40, 20).probe("l1")
                box(.green, 40, 20).probe("l2")
                box(.orange, 40, 20).probe("l3")
                box(.purple, 40, 20).probe("l4")
            }
            .frame(width: 200)
            .probe("lazy")
        }
        .environment(\.layoutDirection, .rightToLeft)
    }

    public static let text = Fixture("layout/rtl-text", size: CGSize(width: 260, height: 300)) {
        VStack(alignment: .leading, spacing: 8) {
            Text(TextMetricsRequests.paragraph).frame(width: 150).probe("leading")
            Text(TextMetricsRequests.paragraph).multilineTextAlignment(.trailing).frame(width: 150).probe("trailing")
            Text(TextMetricsRequests.paragraph).multilineTextAlignment(.center).frame(width: 150).probe("center")
            Label("One", systemImage: "star").probe("label")
            Text("Two").frame(width: 100, alignment: .leading).probe("framedText")
        }
        .environment(\.layoutDirection, .rightToLeft)
    }

    public static let shapes = Fixture("layout/rtl-shapes", size: CGSize(width: 300, height: 200)) {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ArrowShape().fill(.red).frame(width: 40, height: 30).probe("arrow")
                FixedArrowShape().fill(.blue).frame(width: 40, height: 30).probe("fixedArrow")
                Image(systemName: "arrow.right").probe("image")
                Image(systemName: "arrow.right").flipsForRightToLeftLayoutDirection(true).probe("flippedImage")
            }
            .probe("row")
            LinearGradient(colors: [.red, .blue], startPoint: .leading, endPoint: .trailing).frame(width: 120, height: 20).probe("gradient")
            ZStack(alignment: .topLeading) {
                Color.clear.frame(width: 160, height: 40).probe("positionBox")
                box(.green, 20, 20).position(x: 30, y: 20).probe("positioned")
            }
            .frame(width: 160, height: 40)
            box(.orange, 20, 20).offset(x: 40).probe("offset")
        }
        .environment(\.layoutDirection, .rightToLeft)
    }

    public static let scroll = Fixture("layout/rtl-scroll", size: CGSize(width: 200, height: 80)) {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                box(.red, 50, 40).probe("s0")
                box(.blue, 50, 40).probe("s1")
                box(.green, 50, 40).probe("s2")
                box(.orange, 50, 40).probe("s3")
                box(.purple, 50, 40).probe("s4")
                box(.gray, 50, 40).probe("s5")
            }
            .probe("content")
        }
        .frame(width: 180, height: 60)
        .probe("scroll")
        .environment(\.layoutDirection, .rightToLeft)
    }

    public static let custom = Fixture("layout/rtl-custom", size: CGSize(width: 300, height: 120)) {
        FlowLayout {
            box(.red, 60, 20).probe("c0")
            box(.blue, 90, 20).probe("c1")
            box(.green, 50, 20).probe("c2")
            box(.orange, 70, 20).probe("c3")
            box(.purple, 40, 20).probe("c4")
        }
        .frame(width: 200)
        .probe("flow")
        .environment(\.layoutDirection, .rightToLeft)
    }

    public static let all: [Fixture] = [stacks, grid, text, shapes, scroll, custom]
}
