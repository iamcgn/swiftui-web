// Gradients (Phase 2 opens): shapes and strokes paint gradient ops whose geometry spans the
// shape's bounds; stops are expanded and blended in Oklab; evenly spaced colours get locations.
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless

#if !os(WASI)
@Suite @MainActor struct GradientTests {
    private func commands<V: View>(_ view: V) -> [DisplayCommand] {
        let r = Runtime()
        r.mount(view)
        r.layout(in: CGSize(width: 200, height: 100))
        return r.render(scale: 2).commands
    }

    @Test func gradientsFillAndStrokeShapes() {
        let painted = commands(VStack(spacing: 0) {
            Rectangle().fill(LinearGradient(colors: [.red, .blue], startPoint: .leading, endPoint: .trailing)).frame(width: 80, height: 20)
            Circle().fill(RadialGradient(colors: [.white, .blue], center: .center, startRadius: 0, endRadius: 10)).frame(width: 20, height: 20)
            Capsule().strokeBorder(AngularGradient(colors: [.red, .blue], center: .center), lineWidth: 4).frame(width: 40, height: 20)
        })
        var gradients: [DisplayGradient] = []
        for command in painted {
            if case .fillGradient(_, let g, _) = command { gradients.append(g) }
            if case .strokeGradient(_, _, let g) = command { gradients.append(g) }
        }
        #expect(gradients.count == 3)
        // The linear gradient spans the 80-wide rectangle at (60, 20).
        if case .linear(let start, let end) = gradients[0].kind {
            #expect(start == CGPoint(x: 60, y: 30) && end == CGPoint(x: 140, y: 30))
        } else { Issue.record("expected a linear gradient") }
        if case .radial(let center, let r0, let r1) = gradients[1].kind {
            #expect(center == CGPoint(x: 100, y: 50) && r0 == 0 && r1 == 10)
        } else { Issue.record("expected a radial gradient") }
        if case .angular(let center, let angle) = gradients[2].kind {
            #expect(center == CGPoint(x: 100, y: 70) && angle == 0)
        } else { Issue.record("expected an angular gradient") }
        // Two colours expand into 8 sub-stops blended in Oklab: the middle one is brighter than sRGB's mix.
        let stops = gradients[0].stops
        #expect(stops.count == 9 && stops.first?.location == 0 && stops.last?.location == 1)
        let mid = stops[4].color
        #expect(abs(mid.red * 255 - 172) < 3 && abs(mid.green * 255 - 121) < 3 && abs(mid.blue * 255 - 168) < 3)
    }

    @Test func gradientStopsAndSweeps() {
        let g = Gradient(colors: [.red, .green, .blue])
        #expect(g.stops.map(\.location) == [0, 0.5, 1])
        let partial = AngularGradient(colors: [.red, .blue], center: .center, startAngle: .zero, endAngle: .degrees(180))
        let resolved = partial._resolveGradient(in: CGRect(x: 0, y: 0, width: 10, height: 10), environment: EnvironmentValues())
        // Half a turn: the stops end at 0.5 and the end colour holds to 1.
        #expect(abs(resolved.stops[resolved.stops.count - 2].location - 0.5) < 1e-9 && resolved.stops.last?.location == 1)
    }
}
#endif
