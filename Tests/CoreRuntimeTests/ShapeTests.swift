// Shape (Phase 2): Path construction against samples of Apple's `Path.description`
// (Docs/elements/Shape.md), trimming, hit testing, stroking, shape views and the styled stroke
// command. Layout against goldens is in GoldenFrameTests; Apple's paths for the fixture shapes
// are compared in PathGoldenTests.
import Testing
import SwiftUI
import SwiftUIWebHeadless

/// Compares two path descriptions number by number (Apple's carry 1e-16 noise from CGPath).
func pathsMatch(_ ours: String, _ apple: String, tolerance: Double = 1e-3, sourceLocation: SourceLocation = #_sourceLocation) {
    let a = ours.split(separator: " "), b = apple.split(separator: " ")
    #expect(a.count == b.count, "\(ours)\n≠\n\(apple)", sourceLocation: sourceLocation)
    guard a.count == b.count else { return }
    for (x, y) in zip(a, b) {
        if let dx = Double(x), let dy = Double(y) {
            #expect(abs(dx - dy) <= tolerance, "\(ours)\n≠\n\(apple) (\(x) vs \(y))", sourceLocation: sourceLocation)
        } else {
            #expect(x == y, "\(ours)\n≠\n\(apple)", sourceLocation: sourceLocation)
        }
    }
}

@Suite struct PathTests {
    let rect = CGRect(x: 0, y: 0, width: 100, height: 60)

    @Test func descriptionUsesApplesFormat() {
        var p = Path()
        p.move(to: CGPoint(x: 1234567.891, y: 0.000012345))
        p.addLine(to: CGPoint(x: 123456.7, y: -0.5))
        p.addLine(to: CGPoint(x: 1e-5, y: 1e6))
        p.addLine(to: CGPoint(x: 999999.5, y: 0.1 + 0.2))
        p.addLine(to: CGPoint(x: 100000, y: 12345.678))
        #expect(p.description == "1.23457e+06 1.2345e-05 m 123457 -0.5 l 1e-05 1e+06 l 1e+06 0.3 l 100000 12345.7 l")
        var q = Path()
        q.move(to: .zero)
        q.addQuadCurve(to: CGPoint(x: 100, y: 0), control: CGPoint(x: 50, y: 60))
        q.addCurve(to: CGPoint(x: 0, y: 60), control1: CGPoint(x: 100, y: 60), control2: CGPoint(x: 0, y: 0))
        q.closeSubpath()
        #expect(q.description == "0 0 m 50 60 100 0 q 100 60 0 0 0 60 c h")
        #expect(Path(q.description) == q)
        #expect(Path("0 0 m 100 0 l 50 60 l h")?.description == "0 0 m 100 0 l 50 60 l h")
        #expect(Path("0 0 m 1")?.description == "0 0 m")
        #expect(Path("x") == nil)
        #expect(Path("") == Path())
        #expect(Path().boundingRect.isNull)
    }

    @Test func rectanglesAndEllipses() {
        #expect(Rectangle().path(in: rect).description == "0 0 m 100 0 l 100 60 l 0 60 l h")
        pathsMatch(Circle().path(in: rect).description,
                   "80 30 m 80 46.5685 66.5685 60 50 60 c 33.4315 60 20 46.5685 20 30 c 20 13.4315 33.4315 0 50 0 c 66.5685 0 80 13.4315 80 30 c h")
        pathsMatch(Ellipse().path(in: rect).description,
                   "100 30 m 100 46.5685 77.6142 60 50 60 c 22.3858 60 0 46.5685 0 30 c 0 13.4315 22.3858 0 50 0 c 77.6142 0 100 13.4315 100 30 c h")
        #expect(Circle().path(in: rect).boundingRect == CGRect(x: 20, y: 0, width: 60, height: 60))
    }

    @Test func circularCorners() {
        pathsMatch(RoundedRectangle(cornerRadius: 12, style: .circular).path(in: rect).description,
                   "100 30 m 100 48 l 100 54.6274 94.6274 60 88 60 c 12 60 l 5.37258 60 4.05812e-16 54.6274 0 48 c 2.66454e-15 12 l 3.47616e-15 5.37258 5.37258 -8.11625e-16 12 0 c 88 0 l 94.6274 4.05812e-16 100 5.37258 100 12 c h")
        pathsMatch(RoundedRectangle(cornerSize: CGSize(width: 20, height: 8), style: .circular).path(in: rect).description,
                   "100 30 m 100 52 l 100 56.4183 91.0457 60 80 60 c 20 60 l 8.95431 60 6.76354e-16 56.4183 0 52 c 8.88178e-15 8 l 1.02345e-14 3.58172 8.95431 -5.41083e-16 20 0 c 80 0 l 91.0457 2.70542e-16 100 3.58172 100 8 c h")
        // Both radii are limited to half the smaller side.
        pathsMatch(RoundedRectangle(cornerSize: CGSize(width: 60, height: 8), style: .circular).path(in: rect).description,
                   "100 30 m 100 52 l 100 56.4183 86.5685 60 70 60 c 30 60 l 13.4315 60 1.01453e-15 56.4183 0 52 c 1.33227e-14 8 l 1.53517e-14 3.58172 13.4315 -5.41083e-16 30 0 c 70 0 l 86.5685 2.70542e-16 100 3.58172 100 8 c h")
        pathsMatch(Capsule(style: .circular).path(in: rect).description,
                   "100 30 m 100 30 l 100 46.5685 86.5685 60 70 60 c 30 60 l 13.4315 60 1.01453e-15 46.5685 0 30 c 0 30 l 2.02906e-15 13.4315 13.4315 4.63228e-15 30 6.66134e-15 c 70 0 l 86.5685 1.01453e-15 100 13.4315 100 30 c h")
        #expect(RoundedRectangle(cornerRadius: 0).path(in: rect).description == "0 0 m 100 0 l 100 60 l 0 60 l h")
        #expect(RoundedRectangle(cornerRadius: -5).path(in: rect).description == "0 0 m 100 0 l 100 60 l 0 60 l h")
        pathsMatch(RoundedRectangle(cornerRadius: 8, style: .circular).path(in: CGRect(x: 10, y: 20, width: 50, height: 40)).description,
                   "60 40 m 60 52 l 60 56.4183 56.4183 60 52 60 c 18 60 l 13.5817 60 10 56.4183 10 52 c 10 28 l 10 23.5817 13.5817 20 18 20 c 52 20 l 56.4183 20 60 23.5817 60 28 c h")
    }

    @Test func continuousCorners() {
        pathsMatch(RoundedRectangle(cornerRadius: 12).path(in: rect).description,
                   "100 30 m 100 41.656 l 100 46.9381 100 49.5791 99.1011 52.4221 c 97.9713 55.5261 95.5261 57.9713 92.4221 59.1011 c 89.5791 60 86.9381 60 81.656 60 c 18.344 60 l 13.0619 60 10.4209 60 7.57793 59.1011 c 4.47389 57.9713 2.02872 55.5261 0.898937 52.4221 c 0 49.5791 0 46.9381 0 41.656 c 0 18.344 l 0 13.0619 0 10.4209 0.898937 7.57793 c 2.02872 4.47389 4.47389 2.02872 7.57793 0.898937 c 10.4209 0 13.0619 0 18.344 0 c 81.656 0 l 86.9381 0 89.5791 0 92.4221 0.898937 c 95.5261 2.02872 97.9713 4.47389 99.1011 7.57793 c 100 10.4209 100 13.0619 100 18.344 c h")
        // Elliptical corners scale each axis by its own radius.
        pathsMatch(RoundedRectangle(cornerSize: CGSize(width: 20, height: 8)).path(in: rect).description,
                   "100 30 m 100 47.7707 l 100 51.2921 100 53.0527 98.5018 54.948 c 96.6188 57.0174 92.5435 58.6475 87.3701 59.4007 c 82.6319 60 78.2302 60 69.4267 60 c 30.5733 60 l 21.7698 60 17.3681 60 12.6299 59.4007 c 7.45648 58.6475 3.3812 57.0174 1.49823 54.948 c 0 53.0527 0 51.2921 0 47.7707 c 0 12.2293 l 0 8.70792 0 6.94726 1.49823 5.05195 c 3.3812 2.98259 7.45648 1.35248 12.6299 0.599291 c 17.3681 0 21.7698 0 30.5733 0 c 69.4267 0 l 78.2302 0 82.6319 0 87.3701 0.599291 c 92.5435 1.35248 96.6188 2.98259 98.5018 5.05195 c 100 6.94726 100 8.70792 100 12.2293 c h")
        // Compressed: the radius is limited to 30 and the vertical extent to the half height.
        let capsule = "100 30 m 100 30 l 100 31.2 100 35.4 97.7527 41.0552 c 94.9282 48.8153 88.8153 54.9282 81.0552 57.7527 c 73.9478 60 67.3453 60 54.1401 60 c 45.8599 60 l 32.6547 60 26.0522 60 18.9448 57.7527 c 11.1847 54.9282 5.0718 48.8153 2.24734 41.0552 c 0 35.4 0 31.2 0 30 c 0 30 l 0 28.8 0 24.6 2.24734 18.9448 c 5.0718 11.1847 11.1847 5.0718 18.9448 2.24734 c 26.0522 0 32.6547 0 45.8599 0 c 54.1401 0 l 67.3453 0 73.9478 0 81.0552 2.24734 c 88.8153 5.0718 94.9282 11.1847 97.7527 18.9448 c 100 24.6 100 28.8 100 30 c h"
        pathsMatch(RoundedRectangle(cornerRadius: 40).path(in: rect).description, capsule)
        pathsMatch(Capsule().path(in: rect).description, capsule)
        // Partially compressed (r = 100 in a 2000 × 240 rect): control points move linearly.
        pathsMatch(RoundedRectangle(cornerRadius: 100).path(in: CGRect(x: 0, y: 0, width: 2000, height: 240)).description,
                   "2000 120 m 2000 120 l 2000 139.139 2000 156.169 1992.51 176.851 c 1983.09 202.718 1962.72 223.094 1936.85 232.509 c 1913.16 240 1891.15 240 1847.13 240 c 152.866 240 l 108.849 240 86.8407 240 63.1494 232.509 c 37.2824 223.094 16.906 202.718 7.49114 176.851 c 0 156.169 0 139.139 0 120 c 0 120 l 0 100.861 0 83.8313 7.49114 63.1494 c 16.906 37.2824 37.2824 16.906 63.1494 7.49114 c 86.8407 0 108.849 0 152.866 0 c 1847.13 0 l 1891.15 0 1913.16 0 1936.85 7.49114 c 1962.72 16.906 1983.09 37.2824 1992.51 63.1494 c 2000 83.8313 2000 100.861 2000 120 c h",
                   tolerance: 0.01)
        pathsMatch(Capsule().path(in: CGRect(x: 0, y: 0, width: 30, height: 80)).description,
                   "30 40 m 30 57.07 l 30 63.6726 30 66.9739 28.8763 70.5276 c 27.4641 74.4076 24.4076 77.4641 20.5276 78.8763 c 17.7 80 15.6 80 15 80 c 15 80 l 14.4 80 12.3 80 9.47241 78.8763 c 5.59236 77.4641 2.5359 74.4076 1.12367 70.5276 c 0 66.9739 0 63.6726 0 57.07 c 0 22.93 l 0 16.3274 0 13.0261 1.12367 9.47241 c 2.5359 5.59236 5.59236 2.5359 9.47241 1.12367 c 12.3 0 14.4 0 15 0 c 15 0 l 15.6 0 17.7 0 20.5276 1.12367 c 24.4076 2.5359 27.4641 5.59236 28.8763 9.47241 c 30 13.0261 30 16.3274 30 22.93 c h")
    }

    @Test func unevenCorners() {
        pathsMatch(UnevenRoundedRectangle(cornerRadii: .init(topLeading: 5, bottomLeading: 10, bottomTrailing: 15, topTrailing: 20), style: .circular).path(in: rect).description,
                   "100 32.5 m 100 45 l 100 53.2843 93.2843 60 85 60 c 10 60 l 4.47715 60 0 55.5228 0 50 c 0 5 l 0 2.23858 2.23858 0 5 0 c 80 0 l 91.0457 0 100 8.95431 100 20 c h")
        pathsMatch(UnevenRoundedRectangle(cornerRadii: .init(topLeading: 5, bottomLeading: 10, bottomTrailing: 15, topTrailing: 20)).path(in: rect).description,
                   "100 32.5 m 100 37.07 l 100 43.6726 100 46.9739 98.8763 50.5276 c 97.4641 54.4076 94.4076 57.4641 90.5276 58.8763 c 86.9739 60 83.6726 60 77.07 60 c 15.2866 60 l 10.8849 60 8.68407 60 6.31494 59.2509 c 3.72824 58.3094 1.6906 56.2718 0.749114 53.6851 c 0 51.3159 0 49.1151 0 44.7134 c 0 7.64332 l 0 5.44245 0 4.34204 0.374557 3.15747 c 0.8453 1.86412 1.86412 0.8453 3.15747 0.374557 c 4.34204 0 5.44245 0 7.64332 0 c 69.4267 0 l 78.2302 0 82.6319 0 87.3701 1.49823 c 92.5435 3.3812 96.6188 7.45648 98.5018 12.6299 c 100 17.3681 100 21.7698 100 30.5733 c h")
        // Two corners sharing an edge split it in proportion to their radii.
        pathsMatch(UnevenRoundedRectangle(cornerRadii: .init(topLeading: 22, bottomLeading: 18)).path(in: CGRect(x: 0, y: 0, width: 200, height: 60)).description,
                   "200 30 m 200 60 l 200 60 200 60 200 60 c 200 60 200 60 200 60 c 200 60 200 60 200 60 c 27.516 60 l 19.5928 60 15.6313 60 11.3669 58.6516 c 6.71083 56.9569 3.04308 53.2892 1.34841 48.6331 c 0 44.4159 0 40.5326 0 33 c 0 33 l 0 23.7935 0 19.0472 1.64805 13.8929 c 3.71932 8.20213 8.20213 3.71932 13.8929 1.64805 c 19.105 0 23.9468 0 33.6306 0 c 200 0 l 200 0 200 0 200 0 c 200 0 200 0 200 0 c 200 0 200 0 200 0 c h")
        // Oversized radii: each is limited to the larger of half the edge and the edge minus its neighbour.
        pathsMatch(UnevenRoundedRectangle(cornerRadii: .init(topLeading: 20, topTrailing: 90), style: .circular).path(in: CGRect(x: 0, y: 0, width: 100, height: 300)).description,
                   "100 190 m 100 300 l 100 300 100 300 100 300 c 0 300 l 0 300 0 300 0 300 c 0 20 l 0 8.95431 8.95431 0 20 0 c 20 0 l 64.1828 0 100 35.8172 100 80 c h")
        pathsMatch(UnevenRoundedRectangle(cornerRadii: .init(topLeading: 50, topTrailing: 70), style: .circular).path(in: CGRect(x: 0, y: 0, width: 100, height: 300)).description,
                   "100 175 m 100 300 l 100 300 100 300 100 300 c 0 300 l 0 300 0 300 0 300 c 0 50 l 0 22.3858 22.3858 0 50 0 c 50 0 l 77.6142 0 100 22.3858 100 50 c h")
        pathsMatch(UnevenRoundedRectangle(cornerRadii: .init(topLeading: 40)).path(in: CGRect(x: 0, y: 0, width: 200, height: 60)).description,
                   "200 30 m 200 60 l 200 60 200 60 200 60 c 200 60 200 60 200 60 c 200 60 200 60 200 60 c 0 60 l 0 60 0 60 0 60 c 0 60 0 60 0 60 c 0 60 0 60 0 60 c 0 60 l 0 43.2609 0 34.6313 2.99646 25.2598 c 6.7624 14.913 14.913 6.7624 25.2598 2.99646 c 34.7363 0 43.5396 0 61.1466 0 c 200 0 l 200 0 200 0 200 0 c 200 0 200 0 200 0 c 200 0 200 0 200 0 c h")
    }

    @Test func insets() {
        pathsMatch(Circle().inset(by: 5).path(in: rect).description,
                   "75 30 m 75 43.8071 63.8071 55 50 55 c 36.1929 55 25 43.8071 25 30 c 25 16.1929 36.1929 5 50 5 c 63.8071 5 75 16.1929 75 30 c h")
        // Rounded rectangles also shrink their radius (12 − 5 = 7).
        pathsMatch(RoundedRectangle(cornerRadius: 12).inset(by: 5).path(in: rect).description,
                   "95 30 m 95 44.2993 l 95 47.3806 95 48.9212 94.4756 50.5795 c 93.8166 52.3902 92.3902 53.8166 90.5795 54.4756 c 88.9212 55 87.3806 55 84.2993 55 c 15.7007 55 l 12.6194 55 11.0788 55 9.42046 54.4756 c 7.60977 53.8166 6.18342 52.3902 5.52438 50.5795 c 5 48.9212 5 47.3806 5 44.2993 c 5 15.7007 l 5 12.6194 5 11.0788 5.52438 9.42046 c 6.18342 7.60977 7.60977 6.18342 9.42046 5.52438 c 11.0788 5 12.6194 5 15.7007 5 c 84.2993 5 l 87.3806 5 88.9212 5 90.5795 5.52438 c 92.3902 6.18342 93.8166 7.60977 94.4756 9.42046 c 95 11.0788 95 12.6194 95 15.7007 c h")
        #expect(RoundedRectangle(cornerRadius: 12).inset(by: 20).path(in: rect).description == "20 20 m 80 20 l 80 40 l 20 40 l h")
        #expect(Rectangle().inset(by: 5).path(in: rect).description == "5 5 m 95 5 l 95 55 l 5 55 l h")
        #expect(Rectangle().inset(by: 2).inset(by: 3).path(in: rect).description == "5 5 m 95 5 l 95 55 l 5 55 l h")
        pathsMatch(Capsule().inset(by: 5).path(in: rect).description,
                   "95 30 m 95 30 l 95 31 95 34.5 93.1272 39.2127 c 90.7735 45.6794 85.6794 50.7735 79.2127 53.1272 c 73.2898 55 67.7877 55 56.7834 55 c 43.2166 55 l 32.2123 55 26.7102 55 20.7873 53.1272 c 14.3206 50.7735 9.2265 45.6794 6.87279 39.2127 c 5 34.5 5 31 5 30 c 5 30 l 5 29 5 25.5 6.87279 20.7873 c 9.2265 14.3206 14.3206 9.2265 20.7873 6.87279 c 26.7102 5 32.2123 5 43.2166 5 c 56.7834 5 l 67.7877 5 73.2898 5 79.2127 6.87279 c 85.6794 9.2265 90.7735 14.3206 93.1272 20.7873 c 95 25.5 95 29 95 30 c h")
    }

    @Test func arcs() {
        func arc(_ start: Double, _ end: Double, clockwise: Bool) -> String {
            var p = Path()
            p.addArc(center: CGPoint(x: 50, y: 50), radius: 40, startAngle: .degrees(start), endAngle: .degrees(end), clockwise: clockwise)
            return p.description
        }
        let quarter = "90 50 m 90 72.0914 72.0914 90 50 90 c"
        pathsMatch(arc(0, 90, clockwise: false), quarter)
        pathsMatch(arc(0, 120, clockwise: false), "90 50 m 90 72.0914 72.0914 90 50 90 c 42.9785 90 36.0808 88.1517 30 84.641 c")
        pathsMatch(arc(0, 30, clockwise: false), "90 50 m 90 57.0215 88.1517 63.9192 84.641 70 c")
        pathsMatch(arc(0, 450, clockwise: false), "90 50 m 90 72.0914 72.0914 90 50 90 c 27.9086 90 10 72.0914 10 50 c 10 27.9086 27.9086 10 50 10 c 72.0914 10 90 27.9086 90 50 c 90 72.0914 72.0914 90 50 90 c")
        pathsMatch(arc(0, -90, clockwise: false), "90 50 m 90 72.0914 72.0914 90 50 90 c 27.9086 90 10 72.0914 10 50 c 10 27.9086 27.9086 10 50 10 c")
        pathsMatch(arc(0, 360, clockwise: false), "90 50 m 90 72.0914 72.0914 90 50 90 c 27.9086 90 10 72.0914 10 50 c 10 27.9086 27.9086 10 50 10 c 72.0914 10 90 27.9086 90 50 c h")
        pathsMatch(arc(0, -360, clockwise: false), "90 50 m 90 72.0914 72.0914 90 50 90 c 27.9086 90 10 72.0914 10 50 c 10 27.9086 27.9086 10 50 10 c 72.0914 10 90 27.9086 90 50 c")
        pathsMatch(arc(0, 0, clockwise: false), "90 50 m")
        pathsMatch(arc(0, -90, clockwise: true), "90 50 m 90 27.9086 72.0914 10 50 10 c")
        pathsMatch(arc(0, 45, clockwise: true), "90 50 m 90 27.9086 72.0914 10 50 10 c 27.9086 10 10 27.9086 10 50 c 10 72.0914 27.9086 90 50 90 c 60.6087 90 70.7828 85.7857 78.2843 78.2843 c")
        pathsMatch(arc(0, 360, clockwise: true), "90 50 m 90 27.9086 72.0914 10 50 10 c 27.9086 10 10 27.9086 10 50 c 10 72.0914 27.9086 90 50 90 c 72.0914 90 90 72.0914 90 50 c h")
        pathsMatch(arc(0, 720, clockwise: true), "90 50 m 90 27.9086 72.0914 10 50 10 c 27.9086 10 10 27.9086 10 50 c 10 72.0914 27.9086 90 50 90 c 72.0914 90 90 72.0914 90 50 c")
        pathsMatch(arc(-90, 0, clockwise: true), "50 10 m 27.9086 10 10 27.9086 10 50 c 10 72.0914 27.9086 90 50 90 c 72.0914 90 90 72.0914 90 50 c")
        // A current point gets a line to the arc's start.
        var p = Path()
        p.move(to: .zero)
        p.addArc(center: CGPoint(x: 50, y: 30), radius: 20, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        pathsMatch(p.description, "0 0 m 70 30 l 70 41.0457 61.0457 50 50 50 c")
        var rel = Path()
        rel.addRelativeArc(center: CGPoint(x: 50, y: 50), radius: 40, startAngle: .degrees(0), delta: .degrees(190))
        pathsMatch(rel.description, "90 50 m 90 72.0914 72.0914 90 50 90 c 27.9086 90 10 72.0914 10 50 c 10 47.6714 10.2033 45.3473 10.6077 43.0541 c")
        var full = Path()
        full.addRelativeArc(center: CGPoint(x: 50, y: 50), radius: 40, startAngle: .degrees(0), delta: .degrees(-360))
        pathsMatch(full.description, "90 50 m 90 27.9086 72.0914 10 50 10 c 27.9086 10 10 27.9086 10 50 c 10 72.0914 27.9086 90 50 90 c 72.0914 90 90 72.0914 90 50 c")
        var scaled = Path()
        scaled.addArc(center: CGPoint(x: 50, y: 50), radius: 40, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false, transform: CGAffineTransform(scaleX: 2, y: 1))
        pathsMatch(scaled.description, "180 50 m 180 72.0914 144.183 90 100 90 c")
    }

    @Test func trimming() {
        let rectPath = Rectangle().path(in: rect)
        #expect(rectPath.trimmedPath(from: 0.1, to: 0.6).description == "32 0 m 100 0 l 100 60 l 68 60 l")
        #expect(rectPath.trimmedPath(from: 0, to: 1).description == "0 0 m 100 0 l 100 60 l 0 60 l h")
        #expect(rectPath.trimmedPath(from: -0.5, to: 1.5).description == "0 0 m 100 0 l 100 60 l 0 60 l h")
        pathsMatch(rectPath.trimmedPath(from: 0, to: 0.999).description, "0 0 m 100 0 l 100 60 l 0 60 l 0 0.319996 l")
        #expect(rectPath.trimmedPath(from: 0.5, to: 0.5).isEmpty)
        #expect(rectPath.trimmedPath(from: 0.75, to: 0.25).isEmpty)
        var tri = Path()
        tri.move(to: .zero); tri.addLine(to: CGPoint(x: 100, y: 0)); tri.addLine(to: CGPoint(x: 50, y: 60)); tri.closeSubpath()
        pathsMatch(tri.trimmedPath(from: 0.25, to: 0.75).description, "64.0512 0 m 100 0 l 50 60 l 41.0046 49.2055 l")
        var two = Path()
        two.addRect(CGRect(x: 0, y: 0, width: 10, height: 10)); two.addRect(CGRect(x: 20, y: 0, width: 10, height: 10))
        #expect(two.trimmedPath(from: 0.25, to: 0.75).description == "10 10 m 0 10 l 0 0 l 20 0 m 30 0 l 30 10 l")
        pathsMatch(Circle().path(in: rect).trimmedPath(from: 0, to: 0.5).description,
                   "80 30 m 80 46.5685 66.5685 60 50 60 c 33.4315 60 20 46.5685 20 30 c")
        // Splitting inside a curve: within a tenth of a point of Apple's split.
        pathsMatch(Circle().path(in: CGRect(x: 0, y: 0, width: 100, height: 100)).trimmedPath(from: 0.2, to: 0.8).description,
                   "65.4856 97.5557 m 60.6098 99.1423 55.4051 100 50 100 c 22.3858 100 0 77.6142 0 50 c 0 22.3858 22.3858 0 50 0 c 55.4051 0 60.6098 0.857649 65.4856 2.44428 c",
                   tolerance: 0.1)
        var quad = Path()
        quad.move(to: .zero)
        quad.addQuadCurve(to: CGPoint(x: 100, y: 0), control: CGPoint(x: 50, y: 60))
        quad.addCurve(to: CGPoint(x: 0, y: 60), control1: CGPoint(x: 100, y: 60), control2: CGPoint(x: 0, y: 0))
        pathsMatch(quad.trimmedPath(from: 0.5, to: 1).description, "99.3886 7.51934 m 91.0402 54.7503 0 2.751 0 60 c", tolerance: 0.5)
        #expect(Rectangle().trim(from: 0.25, to: 0.5).path(in: rect).description == "80 0 m 100 0 l 100 60 l")
    }

    @Test func containment() {
        var tri = Path()
        tri.move(to: .zero); tri.addLine(to: CGPoint(x: 100, y: 0)); tri.addLine(to: CGPoint(x: 50, y: 60)); tri.closeSubpath()
        #expect(tri.contains(CGPoint(x: 50, y: 30)))
        #expect(!tri.contains(CGPoint(x: 5, y: 50)))
        var ring = Path(rect)
        ring.addRect(rect.insetBy(dx: 20, dy: 20))
        #expect(ring.contains(CGPoint(x: 50, y: 30)))
        #expect(!ring.contains(CGPoint(x: 50, y: 30), eoFill: true))
        var reversed = Path(rect)
        reversed.move(to: CGPoint(x: 25, y: 25)); reversed.addLine(to: CGPoint(x: 25, y: 50)); reversed.addLine(to: CGPoint(x: 75, y: 50)); reversed.addLine(to: CGPoint(x: 75, y: 25)); reversed.closeSubpath()
        #expect(!reversed.contains(CGPoint(x: 50, y: 40)))
        #expect(reversed.contains(CGPoint(x: 0, y: 30)))
        #expect(!reversed.contains(CGPoint(x: 150, y: 30)))
        #expect(Circle().path(in: rect).contains(CGPoint(x: 50, y: 30)))
        #expect(!Circle().path(in: rect).contains(CGPoint(x: 21, y: 1)))
    }

    @Test func shapeModifiers() {
        #expect(Rectangle().offset(x: 10, y: 5).path(in: rect).description == "10 5 m 110 5 l 110 65 l 10 65 l h")
        #expect(Rectangle().scale(0.5).path(in: rect).description == "25 15 m 75 15 l 75 45 l 25 45 l h")
        #expect(Rectangle().scale(x: 0.5, y: 0.5, anchor: .topLeading).path(in: rect).description == "0 0 m 50 0 l 50 30 l 0 30 l h")
        pathsMatch(Rectangle().rotation(.degrees(90)).path(in: rect).description, "80 -20 m 80 80 l 20 80 l 20 -20 l h")
        #expect(Rectangle().size(width: 40, height: 20).path(in: rect).description == "0 0 m 40 0 l 40 20 l 0 20 l h")
        #expect(Rectangle().transform(CGAffineTransform(scaleX: 2, y: 2)).path(in: rect).description == "0 0 m 200 0 l 200 120 l 0 120 l h")
        #expect(AnyShape(Circle()).path(in: rect) == Circle().path(in: rect))
        #expect(AnyShape(Circle()).sizeThatFits(ProposedViewSize(rect.size)) == CGSize(width: 60, height: 60))
        #expect(Circle().scale(0.5).sizeThatFits(ProposedViewSize(rect.size)) == CGSize(width: 60, height: 60))
        #expect(ContainerRelativeShape().path(in: rect) == Path(rect))
        #expect(Rectangle().stroke(lineWidth: 2).path(in: rect).boundingRect == CGRect(x: -1, y: -1, width: 102, height: 62))
    }

    @Test func stroking() {
        var tri = Path()
        tri.move(to: .zero); tri.addLine(to: CGPoint(x: 100, y: 0)); tri.addLine(to: CGPoint(x: 50, y: 60)); tri.closeSubpath()
        let mitered = tri.strokedPath(StrokeStyle(lineWidth: 4)).boundingRect
        let apple = CGRect(x: -4.270083427429199, y: -2, width: 108.5401611328125, height: 65.12409973144531)
        #expect(abs(mitered.minX - apple.minX) < 0.01 && abs(mitered.minY - apple.minY) < 0.01)
        #expect(abs(mitered.maxX - apple.maxX) < 0.01 && abs(mitered.maxY - apple.maxY) < 0.01)
        let rounded = tri.strokedPath(StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)).boundingRect
        #expect(abs(rounded.minX + 2) < 0.01 && abs(rounded.maxX - 102) < 0.01 && abs(rounded.maxY - 62) < 0.01)
        // The union of the stroke polygons contains points on the outline and not far away.
        let outline = tri.strokedPath(StrokeStyle(lineWidth: 4))
        #expect(outline.contains(CGPoint(x: 50, y: 1)))
        #expect(outline.contains(CGPoint(x: 50, y: -1)))
        #expect(!outline.contains(CGPoint(x: 50, y: 30)))
        var line = Path()
        line.move(to: .zero); line.addLine(to: CGPoint(x: 50, y: 0))
        #expect(line.strokedPath(StrokeStyle(lineWidth: 2, lineCap: .square)).boundingRect == CGRect(x: -1, y: -1, width: 52, height: 2))
        #expect(line.strokedPath(StrokeStyle(lineWidth: 2)).boundingRect == CGRect(x: 0, y: -1, width: 50, height: 2))
        // Dashes: 10 on, 5 off, phase 3 → 7, 12–22, 27–37, 42–50 (four pieces).
        let dashed = line.strokedPath(StrokeStyle(lineWidth: 2, dash: [10, 5], dashPhase: 3))
        #expect(dashed.elements.filter { if case .move = $0 { return true } else { return false } }.count == 4)
        #expect(dashed.contains(CGPoint(x: 5, y: 0)) && !dashed.contains(CGPoint(x: 9, y: 0)) && dashed.contains(CGPoint(x: 15, y: 0)))
        #expect(dashed.contains(CGPoint(x: 45, y: 0)) && !dashed.contains(CGPoint(x: 40, y: 0)))
        #expect(Path().strokedPath(StrokeStyle()).isEmpty)
    }
}

#if !os(WASI)
@Suite @MainActor struct ShapeViewTests {
    private func render<V: View>(_ view: V, size: CGSize = CGSize(width: 200, height: 100), scale: CGFloat = 2) -> [String] {
        let runtime = Runtime()
        runtime.mount(view)
        runtime.layout(in: size)
        return runtime.render(scale: scale).commands.map(\.description)
    }

    @Test func fillsAndStrokes() {
        // Continuous corners (the default) need a path; circular ones use the rounded-rect command.
        #expect(render(RoundedRectangle(cornerRadius: 4).fill(Color.green).frame(width: 20, height: 10)) == ["fillPath(18 elements) #34C759"])
        #expect(render(RoundedRectangle(cornerRadius: 4, style: .circular).fill(Color.green).frame(width: 20, height: 10)) == ["fillRRect(90, 45, 20, 10) r=4 #34C759"])
        #expect(render(Capsule().fill(Color.green).frame(width: 20, height: 10)) == ["fillPath(18 elements) #34C759"])
        #expect(render(Capsule(style: .circular).fill(Color.green).frame(width: 20, height: 10)) == ["fillRRect(90, 45, 20, 10) r=5 #34C759"])
        #expect(render(Circle().stroke(Color.blue, lineWidth: 2).frame(width: 20, height: 20)) == ["strokePath(6 elements) w=2 #0088FF"])
        #expect(render(Circle().stroke(Color.blue, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .bevel, dash: [4, 2], dashPhase: 1)).frame(width: 20, height: 20))
                == ["strokePath(6 elements) w=3 cap=round join=bevel dash=[4,2] phase=1 #0088FF"])
        // Stroked shapes as views stroke natively; a zero-width stroke or a clear colour draws nothing.
        #expect(render(Rectangle().stroke(lineWidth: 2).frame(width: 20, height: 10)) == ["strokePath(5 elements) w=2 #000000@0.85"])
        #expect(render(Rectangle().stroke(style: StrokeStyle(lineWidth: 1, dash: [2])).frame(width: 20, height: 10)) == ["strokePath(5 elements) w=1 dash=[2] #000000@0.85"])
        #expect(render(Circle().stroke(Color.blue, lineWidth: 0).frame(width: 20, height: 20)).isEmpty)
        #expect(render(Circle().stroke(Color.clear).frame(width: 20, height: 20)).isEmpty)
        // Fill and stroke chain: the earlier view paints first (behind).
        #expect(render(Circle().fill(Color.red).stroke(Color.blue, lineWidth: 2).frame(width: 20, height: 20))
                == ["fillPath(6 elements) #FF383C", "strokePath(6 elements) w=2 #0088FF"])
        #expect(render(Circle().stroke(Color.blue, lineWidth: 2).fill(Color.red).frame(width: 20, height: 20))
                == ["strokePath(6 elements) w=2 #0088FF", "fillPath(6 elements) #FF383C"])
        #expect(render(Rectangle().fill(Color.red).stroke(Color.blue).frame(width: 20, height: 10))
                == ["fillRect(90, 45, 20, 10) #FF383C", "strokePath(5 elements) w=1 #0088FF"])
        // Even-odd fill and clip.
        var ring = Path(); ring.addRect(CGRect(x: 0, y: 0, width: 20, height: 10)); ring.addRect(CGRect(x: 5, y: 2, width: 10, height: 6))
        #expect(render(ring.fill(Color.red, style: FillStyle(eoFill: true)).frame(width: 20, height: 10)) == ["fillPath(10 elements) eo #FF383C"])
        #expect(render(Color.red.frame(width: 20, height: 10).clipShape(ring, style: FillStyle(eoFill: true)))
                == ["save", "clipPath(10 elements) eo", "fillRect(90, 45, 20, 10) #FF383C", "restore"])
        #expect(render(Color.red.frame(width: 20, height: 10).clipShape(RoundedRectangle(cornerRadius: 4)))
                == ["save", "clipPath(18 elements)", "fillRect(90, 45, 20, 10) #FF383C", "restore"])
    }

    @Test func strokeBorderAndBorder() {
        // strokeBorder insets the path by half the line width, so the stroke stays inside.
        let runtime = Runtime()
        runtime.mount(Rectangle().strokeBorder(Color.blue, lineWidth: 4).frame(width: 20, height: 10))
        runtime.layout(in: CGSize(width: 200, height: 100))
        let list = runtime.render(scale: 2)
        guard case .strokePath(let path, let style, let color) = list.commands.first else { Issue.record("no stroke"); return }
        #expect(path.boundingRect == CGRect(x: 92, y: 47, width: 16, height: 6))
        #expect(style.lineWidth == 4 && color == Color.blue.resolve(in: EnvironmentValues()))
        #expect(render(Circle().strokeBorder(lineWidth: 2).frame(width: 20, height: 20)) == ["strokePath(6 elements) w=2 #000000@0.85"])
        #expect(render(Circle().fill(Color.red).strokeBorder(Color.blue, style: StrokeStyle(lineWidth: 2, dash: [1])).frame(width: 20, height: 20))
                == ["fillPath(6 elements) #FF383C", "strokePath(6 elements) w=2 dash=[1] #0088FF"])
        // border = an inset rectangle stroke overlaid on the content; layout unchanged.
        let bordered = Runtime()
        bordered.mount(Color.red.frame(width: 20, height: 10).border(Color.blue, width: 2)._probe("content"))
        bordered.layout(in: CGSize(width: 200, height: 100))
        #expect(bordered.probeFrames["content"] == CGRect(x: 90, y: 45, width: 20, height: 10))
        let commands = bordered.render(scale: 2).commands
        #expect(commands.map(\.description) == ["fillRect(90, 45, 20, 10) #FF383C", "strokePath(5 elements) w=2 #0088FF"])
        guard case .strokePath(let border, _, _) = commands[1] else { Issue.record("no border"); return }
        #expect(border.boundingRect == CGRect(x: 91, y: 46, width: 18, height: 8))
    }

    @Test func layoutForwardsToTheBaseShape() {
        let runtime = Runtime()
        runtime.mount(HStack(spacing: 0) {
            Circle().scale(0.5)._probe("scaled")
            Circle().stroke(lineWidth: 2)._probe("stroked")
            Circle().inset(by: 4).offset(x: 2)._probe("inset")
            Rectangle().trim(from: 0, to: 0.5)._probe("trimmed")
        })
        runtime.layout(in: CGSize(width: 200, height: 40))
        #expect(runtime.probeFrames["scaled"] == CGRect(x: 0, y: 0, width: 40, height: 40))
        #expect(runtime.probeFrames["stroked"] == CGRect(x: 40, y: 0, width: 40, height: 40))
        #expect(runtime.probeFrames["inset"] == CGRect(x: 80, y: 0, width: 40, height: 40))
        #expect(runtime.probeFrames["trimmed"] == CGRect(x: 120, y: 0, width: 80, height: 40))
    }

    @Test func styledStrokesEncode() {
        var list = DisplayList()
        let style = StrokeStyle(lineWidth: 3, lineCap: .square, lineJoin: .round, miterLimit: 4, dash: [6, 2], dashPhase: 1.5)
        list.append(.strokePath(Path(CGRect(x: 0, y: 0, width: 10, height: 10)), style: style, RGBA(r: 0, g: 136, b: 255)))
        list.append(.fillPath(Path(CGRect(x: 0, y: 0, width: 10, height: 10)), RGBA(r: 255, g: 0, b: 0), eoFill: true))
        list.append(.clipPath(Path(CGRect(x: 0, y: 0, width: 10, height: 10)), eoFill: true))
        let encoded = DisplayListEncoder.encode(list, font: DisplayListEncoder.cssFont)
        #expect(DisplayListDecoder.decode(encoded) == [
            "strokePath M0.0,0.0 L10.0,0.0 L10.0,10.0 L0.0,10.0 Z w3.0 cap2 join1 miter4.0 dash[6.0, 2.0] phase1.5 rgb(0,136,255)",
            "fillPath M0.0,0.0 L10.0,0.0 L10.0,10.0 L0.0,10.0 Z rgb(255,0,0) eo",
            "clipPath M0.0,0.0 L10.0,0.0 L10.0,10.0 L0.0,10.0 Z eo",
        ])
    }
}
#endif
