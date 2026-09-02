// Shared between the Apple harness and SwiftUIWeb: paths whose `description` GoldenGen records
// from real SwiftUI into Fixtures/Goldens/shape/paths.json, and PathGoldenTests compares with
// ours element by element (stroked outlines by bounding box only: SwiftUIWeb approximates them).
import SwiftUI

public struct PathRequest: Sendable {
    public enum Comparison: Sendable { case elements, bounds }
    public let name: String
    public let comparison: Comparison
    public let make: @MainActor @Sendable () -> Path

    public init(_ name: String, _ comparison: Comparison = .elements, make: @escaping @MainActor @Sendable () -> Path) {
        self.name = name
        self.comparison = comparison
        self.make = make
    }
}

public enum PathRequests {
    static let rect = CGRect(x: 0, y: 0, width: 100, height: 60)
    static let square = CGRect(x: 0, y: 0, width: 100, height: 100)

    static var triangle: Path {
        Path { p in p.move(to: .zero); p.addLine(to: CGPoint(x: 100, y: 0)); p.addLine(to: CGPoint(x: 50, y: 60)); p.closeSubpath() }
    }

    public static let all: [PathRequest] = [
        PathRequest("rect") { Rectangle().path(in: rect) },
        PathRequest("circle") { Circle().path(in: rect) },
        PathRequest("ellipse") { Ellipse().path(in: rect) },
        PathRequest("rounded-circular-12") { RoundedRectangle(cornerRadius: 12, style: .circular).path(in: rect) },
        PathRequest("rounded-continuous-12") { RoundedRectangle(cornerRadius: 12).path(in: rect) },
        PathRequest("rounded-continuous-size-20x8") { RoundedRectangle(cornerSize: CGSize(width: 20, height: 8)).path(in: rect) },
        PathRequest("rounded-circular-size-60x8") { RoundedRectangle(cornerSize: CGSize(width: 60, height: 8), style: .circular).path(in: rect) },
        PathRequest("rounded-continuous-20") { RoundedRectangle(cornerRadius: 20).path(in: rect) },
        PathRequest("rounded-continuous-25") { RoundedRectangle(cornerRadius: 25).path(in: rect) },
        PathRequest("rounded-continuous-40-clamped") { RoundedRectangle(cornerRadius: 40).path(in: rect) },
        PathRequest("rounded-continuous-100-in-2000x240") { RoundedRectangle(cornerRadius: 100).path(in: CGRect(x: 0, y: 0, width: 2000, height: 240)) },
        PathRequest("rounded-zero") { RoundedRectangle(cornerRadius: 0).path(in: rect) },
        PathRequest("rounded-offset-origin") { RoundedRectangle(cornerRadius: 8, style: .circular).path(in: CGRect(x: 10, y: 20, width: 50, height: 40)) },
        PathRequest("capsule") { Capsule().path(in: rect) },
        PathRequest("capsule-circular") { Capsule(style: .circular).path(in: rect) },
        PathRequest("capsule-tall") { Capsule().path(in: CGRect(x: 0, y: 0, width: 30, height: 80)) },
        PathRequest("uneven-circular") { UnevenRoundedRectangle(cornerRadii: .init(topLeading: 5, bottomLeading: 10, bottomTrailing: 15, topTrailing: 20), style: .circular).path(in: rect) },
        PathRequest("uneven-continuous") { UnevenRoundedRectangle(cornerRadii: .init(topLeading: 5, bottomLeading: 10, bottomTrailing: 15, topTrailing: 20)).path(in: rect) },
        PathRequest("uneven-shared-edge-22-18") { UnevenRoundedRectangle(cornerRadii: .init(topLeading: 22, bottomLeading: 18)).path(in: CGRect(x: 0, y: 0, width: 200, height: 60)) },
        PathRequest("uneven-oversized-20-90") { UnevenRoundedRectangle(cornerRadii: .init(topLeading: 20, topTrailing: 90), style: .circular).path(in: CGRect(x: 0, y: 0, width: 100, height: 300)) },
        PathRequest("uneven-oversized-50-70") { UnevenRoundedRectangle(cornerRadii: .init(topLeading: 50, topTrailing: 70)).path(in: CGRect(x: 0, y: 0, width: 100, height: 300)) },
        PathRequest("uneven-oversized-40-alone") { UnevenRoundedRectangle(cornerRadii: .init(topLeading: 40)).path(in: CGRect(x: 0, y: 0, width: 200, height: 60)) },
        PathRequest("uneven-all-40-in-60") { UnevenRoundedRectangle(cornerRadii: .init(topLeading: 40, bottomLeading: 40, bottomTrailing: 40, topTrailing: 40)).path(in: CGRect(x: 0, y: 0, width: 200, height: 60)) },
        PathRequest("inset-circle-5") { Circle().inset(by: 5).path(in: rect) },
        PathRequest("inset-rounded-5") { RoundedRectangle(cornerRadius: 12).inset(by: 5).path(in: rect) },
        PathRequest("inset-rounded-past-radius") { RoundedRectangle(cornerRadius: 12).inset(by: 20).path(in: rect) },
        PathRequest("inset-capsule-5") { Capsule().inset(by: 5).path(in: rect) },
        PathRequest("inset-uneven-5") { UnevenRoundedRectangle(cornerRadii: .init(topLeading: 5, bottomLeading: 10, bottomTrailing: 15, topTrailing: 20)).inset(by: 5).path(in: rect) },
        PathRequest("inset-rect-twice") { Rectangle().inset(by: 2).inset(by: 3).path(in: rect) },
        PathRequest("arc-0-90") { Path { $0.addArc(center: CGPoint(x: 50, y: 50), radius: 40, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false) } },
        PathRequest("arc-0-120") { Path { $0.addArc(center: CGPoint(x: 50, y: 50), radius: 40, startAngle: .degrees(0), endAngle: .degrees(120), clockwise: false) } },
        PathRequest("arc-0-30") { Path { $0.addArc(center: CGPoint(x: 50, y: 50), radius: 40, startAngle: .degrees(0), endAngle: .degrees(30), clockwise: false) } },
        PathRequest("arc-0-450") { Path { $0.addArc(center: CGPoint(x: 50, y: 50), radius: 40, startAngle: .degrees(0), endAngle: .degrees(450), clockwise: false) } },
        PathRequest("arc-0-minus90") { Path { $0.addArc(center: CGPoint(x: 50, y: 50), radius: 40, startAngle: .degrees(0), endAngle: .degrees(-90), clockwise: false) } },
        PathRequest("arc-0-360") { Path { $0.addArc(center: CGPoint(x: 50, y: 50), radius: 40, startAngle: .degrees(0), endAngle: .degrees(360), clockwise: false) } },
        PathRequest("arc-0-minus360") { Path { $0.addArc(center: CGPoint(x: 50, y: 50), radius: 40, startAngle: .degrees(0), endAngle: .degrees(-360), clockwise: false) } },
        PathRequest("arc-0-0") { Path { $0.addArc(center: CGPoint(x: 50, y: 50), radius: 40, startAngle: .degrees(0), endAngle: .degrees(0), clockwise: false) } },
        PathRequest("arc-cw-0-minus90") { Path { $0.addArc(center: CGPoint(x: 50, y: 50), radius: 40, startAngle: .degrees(0), endAngle: .degrees(-90), clockwise: true) } },
        PathRequest("arc-cw-0-45") { Path { $0.addArc(center: CGPoint(x: 50, y: 50), radius: 40, startAngle: .degrees(0), endAngle: .degrees(45), clockwise: true) } },
        PathRequest("arc-cw-0-360") { Path { $0.addArc(center: CGPoint(x: 50, y: 50), radius: 40, startAngle: .degrees(0), endAngle: .degrees(360), clockwise: true) } },
        PathRequest("arc-cw-0-720") { Path { $0.addArc(center: CGPoint(x: 50, y: 50), radius: 40, startAngle: .degrees(0), endAngle: .degrees(720), clockwise: true) } },
        PathRequest("arc-cw-minus90-0") { Path { $0.addArc(center: CGPoint(x: 50, y: 50), radius: 40, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: true) } },
        PathRequest("arc-after-move") { Path { $0.move(to: .zero); $0.addArc(center: CGPoint(x: 50, y: 30), radius: 20, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false) } },
        PathRequest("arc-transform") { Path { $0.addArc(center: CGPoint(x: 50, y: 50), radius: 40, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false, transform: CGAffineTransform(scaleX: 2, y: 1)) } },
        PathRequest("relative-arc-190") { Path { $0.addRelativeArc(center: CGPoint(x: 50, y: 50), radius: 40, startAngle: .degrees(0), delta: .degrees(190)) } },
        PathRequest("relative-arc-minus360") { Path { $0.addRelativeArc(center: CGPoint(x: 50, y: 50), radius: 40, startAngle: .degrees(0), delta: .degrees(-360)) } },
        PathRequest("relative-arc-0") { Path { $0.addRelativeArc(center: CGPoint(x: 50, y: 50), radius: 40, startAngle: .degrees(0), delta: .degrees(0)) } },
        PathRequest("lines") { Path { $0.addLines([CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 10), CGPoint(x: 20, y: 0)]) } },
        PathRequest("rect-transform") { Path { $0.addRect(CGRect(x: 0, y: 0, width: 10, height: 10), transform: CGAffineTransform(translationX: 5, y: 5)) } },
        PathRequest("line-after-close") { Path { $0.move(to: .zero); $0.addLine(to: CGPoint(x: 10, y: 0)); $0.closeSubpath(); $0.addLine(to: CGPoint(x: 0, y: 10)) } },
        PathRequest("quad-and-cubic") { Path { $0.move(to: .zero); $0.addQuadCurve(to: CGPoint(x: 100, y: 0), control: CGPoint(x: 50, y: 60)); $0.addCurve(to: CGPoint(x: 0, y: 60), control1: CGPoint(x: 100, y: 60), control2: CGPoint(x: 0, y: 0)) } },
        PathRequest("parsed") { Path("0 0 m 50 60 100 0 q 100 60 0 0 0 60 c h") ?? Path() },
        PathRequest("trim-rect-0.1-0.6") { Rectangle().path(in: rect).trimmedPath(from: 0.1, to: 0.6) },
        PathRequest("trim-rect-0-1") { Rectangle().path(in: rect).trimmedPath(from: 0, to: 1) },
        PathRequest("trim-rect-0-0.999") { Rectangle().path(in: rect).trimmedPath(from: 0, to: 0.999) },
        PathRequest("trim-rect-out-of-range") { Rectangle().path(in: rect).trimmedPath(from: -0.5, to: 1.5) },
        PathRequest("trim-triangle-0.25-0.75") { triangle.trimmedPath(from: 0.25, to: 0.75) },
        PathRequest("trim-circle-0-0.5") { Circle().path(in: rect).trimmedPath(from: 0, to: 0.5) },
        PathRequest("trim-two-subpaths") { Path { $0.addRect(CGRect(x: 0, y: 0, width: 10, height: 10)); $0.addRect(CGRect(x: 20, y: 0, width: 10, height: 10)) }.trimmedPath(from: 0.25, to: 0.75) },
        PathRequest("trim-shape") { Rectangle().trim(from: 0.25, to: 0.5).path(in: rect) },
        PathRequest("trim-circle-0.2-0.8", .bounds) { Circle().path(in: square).trimmedPath(from: 0.2, to: 0.8) },
        PathRequest("offset-shape") { Rectangle().offset(x: 10, y: 5).path(in: rect) },
        PathRequest("scale-shape-0.5") { Rectangle().scale(0.5).path(in: rect) },
        PathRequest("scale-shape-anchor") { Rectangle().scale(x: 0.5, y: 0.5, anchor: .topLeading).path(in: rect) },
        PathRequest("rotation-90") { Rectangle().rotation(.degrees(90)).path(in: rect) },
        PathRequest("rotation-30-anchor") { Rectangle().rotation(.degrees(30), anchor: .bottomTrailing).path(in: rect) },
        PathRequest("transform-shape") { Rectangle().transform(CGAffineTransform(a: 1, b: 0, c: 0.5, d: 1, tx: 0, ty: 0)).path(in: rect) },
        PathRequest("size-shape") { Rectangle().size(width: 40, height: 20).path(in: rect) },
        PathRequest("any-shape") { AnyShape(Circle()).path(in: rect) },
        PathRequest("stroked-triangle-4", .bounds) { triangle.strokedPath(StrokeStyle(lineWidth: 4)) },
        PathRequest("stroked-triangle-round", .bounds) { triangle.strokedPath(StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)) },
        PathRequest("stroked-line-square", .bounds) { Path { $0.move(to: .zero); $0.addLine(to: CGPoint(x: 50, y: 0)) }.strokedPath(StrokeStyle(lineWidth: 2, lineCap: .square)) },
        PathRequest("stroked-circle", .bounds) { Circle().path(in: CGRect(x: 0, y: 0, width: 40, height: 40)).strokedPath(StrokeStyle(lineWidth: 4)) },
        PathRequest("stroked-shape", .bounds) { Rectangle().stroke(lineWidth: 2).path(in: rect) },
    ]
}
