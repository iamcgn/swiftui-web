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

    public static let all: [Fixture] = [basic]
}
