// Paint fixtures: background/overlay layout, shapes, and a colour swatch grid whose pixels
// give the macOS system colour table (sampled by scripts/sample-colors.py).
import SwiftUI
import FixtureKit

public enum PaintFixtures {
    public static let backgroundOverlay = Fixture("paint/background-overlay", size: CGSize(width: 300, height: 200)) {
        VStack(spacing: 20) {
            Color.red.frame(width: 100, height: 60).probe("content")
                .background(Color.blue.frame(width: 20, height: 20).probe("bg"), alignment: .bottomTrailing)
                .overlay(alignment: .topLeading) { Color.green.frame(width: 10, height: 10).probe("ov") }
                .probe("modified")
            Text("Hello").probe("text")
                .padding(4)
                .background(Color.yellow.probe("textBg"))
                .probe("padded")
            Color.red.frame(width: 40, height: 20).probe("small")
                .background { Color.blue.frame(width: 80, height: 40).probe("bigBg") }
                .probe("smallOuter")
        }
    }

    public static let shapes = Fixture("paint/shapes", size: CGSize(width: 300, height: 200)) {
        HStack(spacing: 10) {
            Circle().probe("circle")
            Rectangle().fill(Color.red).frame(width: 40).probe("rect")
            RoundedRectangle(cornerRadius: 8).fill(Color.blue).frame(width: 40, height: 40).probe("rounded")
            Capsule().fill(Color.green).frame(width: 60, height: 30).probe("capsule")
            Ellipse().frame(width: 50, height: 30).probe("ellipse")
        }
        .frame(height: 100)
        .probe("row")
    }

    public static let clipping = Fixture("paint/clipping", size: CGSize(width: 200, height: 200)) {
        VStack(spacing: 10) {
            Color.red.frame(width: 100, height: 60).probe("clipped").clipShape(RoundedRectangle(cornerRadius: 12))
            Color.blue.frame(width: 100, height: 60).probe("corner").cornerRadius(20)
            Color.green.frame(width: 100, height: 40).opacity(0.5).probe("faded")
        }
        .probe("stack")
    }

    public static let systemColors = Fixture("paint/system-colors", size: CGSize(width: 400, height: 240)) {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Color.red.probe("red"); Color.orange.probe("orange"); Color.yellow.probe("yellow"); Color.green.probe("green")
                Color.mint.probe("mint"); Color.teal.probe("teal"); Color.cyan.probe("cyan"); Color.blue.probe("blue")
            }
            HStack(spacing: 0) {
                Color.indigo.probe("indigo"); Color.purple.probe("purple"); Color.pink.probe("pink"); Color.brown.probe("brown")
                Color.white.probe("white"); Color.gray.probe("gray"); Color.black.probe("black"); Color.clear.probe("clear")
            }
            HStack(spacing: 0) {
                Color.primary.probe("primary"); Color.secondary.probe("secondary"); Color.accentColor.probe("accentColor")
                Color(red: 0.2, green: 0.4, blue: 0.6).probe("rgb"); Color(white: 0.5).probe("white50")
                Color.red.opacity(0.5).probe("redHalf"); Color(red: 1, green: 0, blue: 0, opacity: 0.25).probe("redQuarter")
                Rectangle().probe("shapeDefault")
            }
        }
    }

    public static let all: [Fixture] = [backgroundOverlay, shapes, clipping, systemColors]
}
