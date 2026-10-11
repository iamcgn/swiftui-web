// Gradient fixtures: linear, radial and angular gradients filling shapes and backgrounds.
import SwiftUI
import FixtureKit

public enum GradientFixtures {
    public static let basic = Fixture("gradient/basic", size: CGSize(width: 320, height: 240)) {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                Rectangle().fill(LinearGradient(colors: [.red, .blue], startPoint: .leading, endPoint: .trailing)).frame(width: 80, height: 50).probe("linear")
                Rectangle().fill(LinearGradient(gradient: Gradient(stops: [.init(color: .yellow, location: 0), .init(color: .green, location: 0.25), .init(color: .black, location: 1)]), startPoint: .top, endPoint: .bottom)).frame(width: 80, height: 50).probe("stops")
                Circle().fill(RadialGradient(colors: [.white, .blue], center: .center, startRadius: 0, endRadius: 25)).frame(width: 50, height: 50).probe("radial")
            }
            .probe("row1")
            HStack(spacing: 16) {
                RoundedRectangle(cornerRadius: 8).fill(AngularGradient(colors: [.red, .yellow, .green, .blue, .red], center: .center)).frame(width: 60, height: 60).probe("angular")
                Text("Sky").padding(12).background(LinearGradient(colors: [.blue, .white], startPoint: .top, endPoint: .bottom)).probe("background")
                Capsule().strokeBorder(LinearGradient(colors: [.purple, .orange], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 6).frame(width: 80, height: 40).probe("stroke")
            }
            .probe("row2")
        }
        .probe("stack")
    }

    /// Gradient foreground styles on text and gradient shadings in a Canvas.
    public static let text = Fixture("gradient/text", size: CGSize(width: 320, height: 180)) {
        VStack(spacing: 16) {
            Text("Gradient").font(.largeTitle)
                .foregroundStyle(LinearGradient(colors: [.red, .blue], startPoint: .leading, endPoint: .trailing))
                .probe("text")
            HStack(spacing: 16) {
                Text("Sky").foregroundStyle(.red).probe("red")
                Text("Sky").foregroundStyle(.red).foregroundStyle(.primary).probe("hierarchical")
            }
            Canvas { context, size in
                context.fill(Path(CGRect(x: 0, y: 0, width: 120, height: 40)),
                             with: .linearGradient(Gradient(colors: [.green, .yellow]), startPoint: .zero, endPoint: CGPoint(x: 120, y: 0)))
                context.stroke(Path(ellipseIn: CGRect(x: 140, y: 4, width: 32, height: 32)),
                               with: .radialGradient(Gradient(colors: [.blue, .purple]), center: CGPoint(x: 156, y: 20), startRadius: 0, endRadius: 16), lineWidth: 6)
                context.fill(Path(CGRect(x: 0, y: 48, width: 180, height: 12)),
                             with: .style(AngularGradient(colors: [.red, .orange, .red], center: .center)))
            }
            .frame(width: 180, height: 60)
            .probe("canvas")
        }
        .probe("stack")
    }

    /// Corners (sw-gradients): an elliptical gradient (the end fraction 0.5 touches the edges),
    /// a mesh gradient smooth and flat, `in(_:)` pinning the frame, `opacity` and `.secondary`
    /// fading, a symbol and a template image under a gradient foreground style.
    public static let corners = Fixture("gradient/corners", size: CGSize(width: 360, height: 240)) {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Rectangle().fill(EllipticalGradient(colors: [.red, .blue])).frame(width: 110, height: 60).probe("elliptical")
                Rectangle().fill(.ellipticalGradient(colors: [.yellow, .green], center: .topLeading, startRadiusFraction: 0.2, endRadiusFraction: 0.9)).frame(width: 110, height: 60).probe("ellipticalCorner")
                Rectangle().fill(LinearGradient(colors: [.red, .blue], startPoint: .leading, endPoint: .trailing).in(CGRect(x: 30, y: 0, width: 50, height: 60))).frame(width: 110, height: 60).probe("inRect")
            }
            .probe("row1")
            HStack(spacing: 10) {
                MeshGradient(width: 3, height: 3, points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.5], [0.8, 0.3], [1, 0.5],
                    [0, 1], [0.5, 1], [1, 1],
                ], colors: [.red, .purple, .indigo, .orange, .white, .blue, .yellow, .green, .mint])
                .frame(width: 110, height: 110).probe("mesh")
                MeshGradient(width: 2, height: 2, points: [[0, 0], [1, 0], [0, 1], [1, 1]], colors: [.red, .blue, .yellow, .green], smoothsColors: false)
                    .frame(width: 110, height: 110).probe("meshFlat")
                VStack(spacing: 6) {
                    Rectangle().fill(LinearGradient(colors: [.red, .blue], startPoint: .leading, endPoint: .trailing).opacity(0.5)).frame(width: 110, height: 24).probe("opacity")
                    Rectangle().fill(LinearGradient(colors: [.red, .blue], startPoint: .leading, endPoint: .trailing).secondary).frame(width: 110, height: 24).probe("secondary")
                    HStack(spacing: 6) {
                        Image(systemName: "star.fill").resizable().foregroundStyle(LinearGradient(colors: [.red, .blue], startPoint: .leading, endPoint: .trailing)).frame(width: 50, height: 50).probe("symbol")
                        Image("icon").resizable().foregroundStyle(LinearGradient(colors: [.green, .orange], startPoint: .top, endPoint: .bottom)).frame(width: 50, height: 50).probe("template")
                    }
                }
            }
            .probe("row2")
        }
    }

    public static let all: [Fixture] = [basic, text, corners]
}
