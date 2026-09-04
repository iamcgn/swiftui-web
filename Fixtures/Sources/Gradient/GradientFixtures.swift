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

    public static let all: [Fixture] = [basic, text]
}
