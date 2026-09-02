// Shape fixtures: built-in shapes and corner styles, strokes (styles, borders, fill/stroke
// chains), custom paths (arcs, curves, even-odd fills), shape modifiers, `border`, layout in
// stacks, and a behaviour fixture that animates nothing but changes stroke and trim parameters.
import SwiftUI
import FixtureKit

/// Drives `shape/steps`.
@Observable
public final class ShapeStepsModel {
    public var radius: CGFloat = 8
    public var lineWidth: CGFloat = 2
    public var trimEnd: CGFloat = 1
    public var dashPhase: CGFloat = 0
    public init() {}
}

public enum ShapeFixtures {
    /// Corner styles (continuous is the default), elliptical and uneven corners, capsules in
    /// both orientations, a circle in a wide frame, a radius larger than half the side.
    public static let builtin = Fixture("shape/builtin", size: CGSize(width: 340, height: 220)) {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 16).fill(Color.blue).frame(width: 80, height: 50).probe("continuous")
                RoundedRectangle(cornerRadius: 16, style: .circular).fill(Color.blue).frame(width: 80, height: 50).probe("circular")
                RoundedRectangle(cornerSize: CGSize(width: 24, height: 10)).fill(Color.green).frame(width: 80, height: 50).probe("elliptical")
                UnevenRoundedRectangle(cornerRadii: .init(topLeading: 4, bottomLeading: 20, bottomTrailing: 4, topTrailing: 20))
                    .fill(Color.orange).frame(width: 60, height: 50).probe("uneven")
            }
            .probe("row1")
            HStack(spacing: 8) {
                Capsule().fill(Color.red).frame(width: 100, height: 40).probe("capsule")
                Capsule(style: .circular).fill(Color.red).frame(width: 100, height: 40).probe("capsuleCircular")
                Capsule().fill(Color.purple).frame(width: 30, height: 60).probe("capsuleTall")
                Circle().fill(Color.mint).probe("circleWide").frame(width: 70, height: 40)
            }
            .probe("row2")
            HStack(spacing: 8) {
                Ellipse().fill(Color.teal).frame(width: 90, height: 40).probe("ellipse")
                Rectangle().fill(Color.gray).frame(width: 60, height: 40).probe("rect")
                RoundedRectangle(cornerRadius: 40).fill(Color.indigo).frame(width: 60, height: 40).probe("clamped")
                AnyShape(Circle()).fill(Color.pink).probe("any").frame(width: 60, height: 40)
            }
            .probe("row3")
        }
        .probe("stack")
    }

    /// Strokes centre on the outline and overflow the frame; `strokeBorder` stays inside; fill
    /// and stroke chain in order; dashes, caps and joins.
    public static let stroke = Fixture("shape/stroke", size: CGSize(width: 320, height: 200)) {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Circle().stroke(Color.blue, lineWidth: 4).probe("stroke").frame(width: 50, height: 50)
                Circle().strokeBorder(Color.blue, lineWidth: 4).probe("strokeBorder").frame(width: 50, height: 50)
                Circle().stroke(lineWidth: 6).probe("strokeShape").frame(width: 50, height: 50)
                Circle().fill(Color.yellow).stroke(Color.red, lineWidth: 3).probe("fillStroke").frame(width: 50, height: 50)
                Circle().stroke(Color.red, lineWidth: 3).fill(Color.yellow).probe("strokeFill").frame(width: 50, height: 50)
            }
            .probe("row1")
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 8).stroke(Color.green, style: StrokeStyle(lineWidth: 3, dash: [8, 4])).frame(width: 80, height: 40).probe("dashed")
                Rectangle().stroke(Color.purple, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round, dash: [1, 12])).frame(width: 80, height: 40).probe("dots")
                Capsule().strokeBorder(Color.orange, style: StrokeStyle(lineWidth: 2, dash: [6, 3], dashPhase: 3)).frame(width: 80, height: 40).probe("capsuleDash")
            }
            .probe("row2")
            HStack(spacing: 8) {
                zigzag.stroke(Color.blue, style: StrokeStyle(lineWidth: 6, lineCap: .butt, lineJoin: .miter)).frame(width: 70, height: 40).probe("miter")
                zigzag.stroke(Color.blue, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round)).frame(width: 70, height: 40).probe("round")
                zigzag.stroke(Color.blue, style: StrokeStyle(lineWidth: 6, lineCap: .square, lineJoin: .bevel)).frame(width: 70, height: 40).probe("bevel")
            }
            .probe("row3")
        }
        .probe("stack")
    }

    static var zigzag: Path {
        Path { p in
            p.move(to: CGPoint(x: 5, y: 35))
            p.addLine(to: CGPoint(x: 25, y: 5))
            p.addLine(to: CGPoint(x: 45, y: 35))
            p.addLine(to: CGPoint(x: 65, y: 5))
        }
    }

    /// Custom paths: lines, arcs both ways, a relative arc, curves, a pentagram filled nonzero
    /// and even-odd, a parsed description, a rounded rect inside a path.
    public static let path = Fixture("shape/path", size: CGSize(width: 300, height: 160)) {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Path { p in
                    p.move(to: CGPoint(x: 30, y: 4)); p.addLine(to: CGPoint(x: 56, y: 56)); p.addLine(to: CGPoint(x: 4, y: 56)); p.closeSubpath()
                }
                .fill(Color.red).probe("triangle").frame(width: 60, height: 60)
                Path { p in
                    p.move(to: CGPoint(x: 30, y: 30))
                    p.addArc(center: CGPoint(x: 30, y: 30), radius: 26, startAngle: .degrees(0), endAngle: .degrees(120), clockwise: false)
                    p.closeSubpath()
                }
                .fill(Color.blue).probe("pie").frame(width: 60, height: 60)
                Path { p in
                    p.move(to: CGPoint(x: 30, y: 30))
                    p.addArc(center: CGPoint(x: 30, y: 30), radius: 26, startAngle: .degrees(0), endAngle: .degrees(120), clockwise: true)
                    p.closeSubpath()
                }
                .fill(Color.green).probe("pieClockwise").frame(width: 60, height: 60)
                Path { p in
                    p.addRelativeArc(center: CGPoint(x: 30, y: 30), radius: 24, startAngle: .degrees(-90), delta: .degrees(270))
                }
                .stroke(Color.orange, lineWidth: 5).probe("ring").frame(width: 60, height: 60)
            }
            .probe("row1")
            HStack(spacing: 8) {
                Path { p in
                    p.move(to: CGPoint(x: 4, y: 30))
                    p.addQuadCurve(to: CGPoint(x: 30, y: 4), control: CGPoint(x: 4, y: 4))
                    p.addCurve(to: CGPoint(x: 56, y: 56), control1: CGPoint(x: 56, y: 4), control2: CGPoint(x: 30, y: 30))
                    p.addLine(to: CGPoint(x: 4, y: 56))
                    p.closeSubpath()
                }
                .fill(Color.purple).probe("curves").frame(width: 60, height: 60)
                star.fill(Color.pink).probe("starNonzero").frame(width: 60, height: 60)
                star.fill(Color.pink, style: FillStyle(eoFill: true)).probe("starEvenOdd").frame(width: 60, height: 60)
                (Path("30 4 m 56 20 l 46 56 l 14 56 l 4 20 l h") ?? Path()).fill(Color.teal).probe("parsed").frame(width: 60, height: 60)
                Path(roundedRect: CGRect(x: 4, y: 4, width: 52, height: 52), cornerRadius: 12).fill(Color.brown).probe("rounded").frame(width: 60, height: 60)
            }
            .probe("row2")
        }
        .probe("stack")
    }

    /// A pentagram: nonzero winding fills the centre, even-odd leaves it empty.
    static var star: Path {
        var p = Path()
        let points = (0..<5).map { i -> CGPoint in
            let angle = -Double.pi / 2 + Double(i) * 4 * Double.pi / 5
            return CGPoint(x: 30 + 26 * cos(angle), y: 30 + 26 * sin(angle))
        }
        p.addLines(points)
        p.closeSubpath()
        return p
    }

    /// Shape modifiers (offset, scale, rotation, transform, size, trim, inset, stroke as a
    /// shape) and the layout they produce: forwarded from the base shape, and the ideal size.
    public static let modifiers = Fixture("shape/modifiers", size: CGSize(width: 340, height: 200)) {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Circle().scale(0.5).fill(Color.blue).probe("scaled").frame(width: 60, height: 40)
                Circle().offset(x: 10, y: 5).fill(Color.red).probe("offset").frame(width: 60, height: 40)
                Rectangle().rotation(.degrees(30)).fill(Color.green).probe("rotated").frame(width: 60, height: 40)
                Rectangle().transform(CGAffineTransform(a: 1, b: 0, c: 0.5, d: 1, tx: 0, ty: 0)).fill(Color.orange).probe("sheared").frame(width: 60, height: 40)
                Rectangle().size(width: 30, height: 20).fill(Color.purple).probe("sized").frame(width: 60, height: 40)
            }
            .probe("row1")
            HStack(spacing: 8) {
                Circle().trim(from: 0.25, to: 1).stroke(Color.blue, lineWidth: 4).probe("trimmed").frame(width: 60, height: 40)
                RoundedRectangle(cornerRadius: 12).inset(by: 5).fill(Color.teal).probe("inset").frame(width: 60, height: 40)
                Rectangle().stroke(lineWidth: 3).offset(x: 3, y: 3).fill(Color.red).probe("strokedOffset").frame(width: 60, height: 40)
                Circle().scale(x: 1.5, y: 0.5, anchor: .topLeading).fill(Color.pink).probe("anchored").frame(width: 60, height: 40)
                Ellipse().inset(by: 4).stroke(Color.indigo, lineWidth: 2).probe("insetStroke").frame(width: 60, height: 40)
            }
            .probe("row2")
            HStack(spacing: 8) {
                Circle().offset(x: 5).fill(Color.blue).probe("offsetIdeal")
                Rectangle().size(width: 30, height: 20).fill(Color.green).probe("sizedIdeal")
                Path { p in p.addRect(CGRect(x: 0, y: 0, width: 24, height: 16)) }.fill(Color.red).probe("pathIdeal")
                Circle().trim(from: 0, to: 0.5).fill(Color.orange).probe("trimIdeal")
            }
            .fixedSize()
            .probe("row3")
        }
        .probe("stack")
    }

    /// `border` draws inside the view's bounds and changes no layout.
    public static let border = Fixture("shape/border", size: CGSize(width: 300, height: 160)) {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text("Hello").probe("textInner").border(Color.red).probe("text")
                Text("Hello").padding(6).border(Color.blue, width: 3).probe("padded")
                Text("Hg").border(Color.red.opacity(0.5), width: 8).probe("thick")
                Text("OK").border(Color.green, width: 0).probe("zero")
            }
            .probe("row1")
            HStack(spacing: 8) {
                Color.yellow.frame(width: 60, height: 30).border(Color.black).probe("color")
                Color.yellow.frame(width: 60, height: 30).border(Color.black, width: 2).padding(4).border(Color.blue).probe("nested")
                Circle().fill(Color.mint).frame(width: 30, height: 30).border(Color.purple, width: 2).probe("circle")
            }
            .probe("row2")
        }
        .probe("stack")
    }

    /// Shapes in stacks: flexible, 10 × 10 ideal, the circle's square, stroked and modified
    /// shapes laid out like their base.
    public static let layout = Fixture("shape/layout", size: CGSize(width: 300, height: 200)) {
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                Circle().fill(Color.red).probe("c1")
                Ellipse().fill(Color.blue).probe("e1")
                Capsule().fill(Color.green).probe("cap1")
                Circle().stroke(lineWidth: 2).probe("strokedFlex")
            }
            .frame(height: 40)
            .probe("row1")
            HStack(spacing: 4) {
                Rectangle().fill(Color.red).probe("r1")
                Rectangle().fill(Color.blue).frame(width: 40).probe("r2")
                Capsule().fill(Color.orange).frame(width: 20).probe("capsuleFixedWidth")
                RoundedRectangle(cornerRadius: 4).fill(Color.purple).frame(maxWidth: 50).probe("maxWidth")
            }
            .frame(width: 200, height: 30)
            .probe("row2")
            HStack(spacing: 4) {
                Rectangle().fill(Color.gray).fixedSize().probe("ideal")
                Circle().fill(Color.mint).fixedSize().probe("circleIdeal")
                Circle().strokeBorder(lineWidth: 2).fixedSize().probe("strokedIdeal")
                VStack(spacing: 0) {
                    Circle().fill(Color.teal).probe("vCircle")
                    Rectangle().fill(Color.pink).probe("vRect")
                }
                .frame(width: 60, height: 100)
                .probe("column")
            }
            .probe("row3")
        }
        .probe("stack")
    }

    /// Behaviour: stroke and trim parameters follow the model (frames constant, pixels change).
    public static let steps = Fixture(
        "shape/steps", size: CGSize(width: 200, height: 120),
        model: { ShapeStepsModel() },
        steps: [
            FixtureStep("rounder") { $0.radius = 20 },
            FixtureStep("thicker") { $0.lineWidth = 6 },
            FixtureStep("half") { $0.trimEnd = 0.5; $0.dashPhase = 4 },
        ]
    ) { model in
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: model.radius)
                .strokeBorder(Color.blue, style: StrokeStyle(lineWidth: model.lineWidth, dash: [6, 3], dashPhase: model.dashPhase))
                .frame(width: 120, height: 60)
                .probe("box")
            Circle().trim(from: 0, to: model.trimEnd).stroke(Color.red, lineWidth: 4).frame(width: 40, height: 40).probe("arc")
        }
        .probe("row")
    }

    public static let all: [Fixture] = [builtin, stroke, path, modifiers, border, layout, steps]
}
