// `position` (the view's centre at a point in its parent's space, taking the proposed size) and
// safe-area modifiers (`safeAreaInset`, `safeAreaPadding`, `ignoresSafeArea`).
import SwiftUI
import FixtureKit

public enum PositionFixtures {
    public static let position = Fixture("position/basic", size: CGSize(width: 320, height: 240), content: {
        VStack(spacing: 10) {
            ZStack {
                Color(white: 0.9)
                Color.red.frame(width: 40, height: 40).position(x: 50, y: 30).probe("inZStack")
                Color.blue.frame(width: 30, height: 30).position(CGPoint(x: 150, y: 60)).probe("point")
            }
            .frame(width: 200, height: 90)
            .probe("zstack")
            HStack(spacing: 10) {
                Text("Left").probe("left")
                Color.green.frame(width: 30, height: 30).position(x: 20, y: 20).probe("inHStack")
                Text("Right").probe("right")
            }
            .frame(height: 50)
            .probe("hstack")
            VStack(spacing: 4) {
                Text("Above").probe("above")
                Color.orange.frame(width: 30, height: 20).position(x: 40, y: 10).probe("inVStack")
                Text("Below").probe("below")
            }
            .probe("vstack")
        }
        .probe("stack")
    })

    /// Safe-area insets in a fixed box: plain content is laid out inside the reduced area, a
    /// scroll view keeps its frame and pads its content, `ignoresSafeArea` extends under the bar.
    public static let safeArea = Fixture("position/safe-area", size: CGSize(width: 400, height: 260), content: {
        HStack(spacing: 20) {
            VStack(spacing: 0) {
                Color.red.probe("plainContent")
            }
            .safeAreaInset(edge: .bottom) { Color.blue.frame(height: 30).probe("plainBar") }
            .frame(width: 100, height: 200)
            .probe("plain")
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { i in Color.green.opacity(i % 2 == 0 ? 1 : 0.5).frame(height: 30).probe("row\(i)") }
                }
                .probe("scrollContent")
            }
            .safeAreaInset(edge: .bottom) { Color.blue.frame(height: 30).probe("scrollBar") }
            .frame(width: 100, height: 200)
            .probe("scroll")
            VStack(spacing: 0) {
                Color.orange.probe("ignoringContent")
            }
            .ignoresSafeArea()
            .safeAreaInset(edge: .top, spacing: 0) { Color.blue.frame(height: 30).probe("ignoringBar") }
            .frame(width: 100, height: 200)
            .probe("ignoring")
        }
        .probe("row")
    })

    public static let safeAreaPadding = Fixture("position/safe-area-padding", size: CGSize(width: 320, height: 200), content: {
        HStack(spacing: 20) {
            Color.red.safeAreaPadding(20).frame(width: 100, height: 150).probe("padded")
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(0..<6, id: \.self) { i in Color.green.opacity(i % 2 == 0 ? 1 : 0.5).frame(height: 30).probe("prow\(i)") }
                }
                .probe("paddedScrollContent")
            }
            .safeAreaPadding(.vertical, 20)
            .frame(width: 100, height: 150)
            .probe("paddedScroll")
        }
        .probe("row")
    })

    public static let all: [Fixture] = [position, safeArea, safeAreaPadding]
}
