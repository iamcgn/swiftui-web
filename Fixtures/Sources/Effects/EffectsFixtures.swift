// Layer effect fixtures: `shadow` paints outside the frame without changing layout, `zIndex`
// reorders overlapping siblings, and `hidden` keeps a view's space while drawing nothing.
import SwiftUI
import FixtureKit

public enum EffectsFixtures {
    public static let shadow = Fixture("effects/shadow", size: CGSize(width: 360, height: 260)) {
        VStack(spacing: 50) {
            HStack(spacing: 60) {
                Color.red.frame(width: 60, height: 60).shadow(radius: 8).probe("default")
                Color.blue.frame(width: 60, height: 60).shadow(color: .black, radius: 4, x: 6).probe("offset")
                Circle().fill(Color.green).frame(width: 60, height: 60).shadow(color: .blue.opacity(0.5), radius: 0, x: 4).probe("hard")
            }
            .probe("row1")
            HStack(spacing: 60) {
                Text("Shadow").font(.title).shadow(radius: 2).probe("text")
                RoundedRectangle(cornerRadius: 12).fill(Color.orange).frame(width: 90, height: 50).shadow(color: .purple, radius: 12).probe("rounded")
                Color.gray.frame(width: 60, height: 60).opacity(0.5).shadow(radius: 6).probe("faded")
            }
            .probe("row2")
        }
        .probe("stack")
    }

    /// Black squares on a transparent background: the golden's alpha across each edge gives
    /// the blur profile (Docs/elements/Effects.md).
    public static let shadowProfile = Fixture("effects/shadow-profile", size: CGSize(width: 360, height: 160)) {
        HStack(spacing: 60) {
            Color.black.frame(width: 60, height: 60).shadow(color: .black, radius: 10).probe("blur10")
            Color.black.frame(width: 60, height: 60).shadow(color: .black, radius: 4, x: 10).probe("blur4")
            Color.black.frame(width: 60, height: 60).shadow(color: .red, radius: 0, x: 5).probe("sharp")
        }
        .probe("row")
    }

    /// Vertical offsets. The harness's offscreen window draws them upwards (a CoreGraphics
    /// base-space offset), unlike a window on screen, so this fixture's pixels are not compared.
    public static let shadowOffset = Fixture("effects/shadow-offset", size: CGSize(width: 360, height: 160)) {
        HStack(spacing: 60) {
            Color.blue.frame(width: 60, height: 60).shadow(color: .black, radius: 4, x: 6, y: 6).probe("offset")
            Color.black.frame(width: 60, height: 60).shadow(color: .red, radius: 0, x: 5, y: 5).probe("sharp")
            Text("Shadow").font(.title).shadow(radius: 2, y: 2).probe("text")
        }
        .probe("row")
    }

    public static let zIndex = Fixture("effects/zindex", size: CGSize(width: 320, height: 240)) {
        VStack(spacing: 30) {
            ZStack {
                Color.red.frame(width: 80, height: 80).offset(x: -25, y: -15).zIndex(2).probe("red")
                Color.blue.frame(width: 80, height: 80).probe("blue")
                Color.green.frame(width: 80, height: 80).offset(x: 25, y: 15).zIndex(1).probe("green")
                Color.yellow.frame(width: 120, height: 120).zIndex(-1).probe("yellow")
            }
            .probe("zstack")
            HStack(spacing: -30) {
                Color.orange.frame(width: 70, height: 50).probe("first")
                Color.purple.frame(width: 70, height: 50).zIndex(1).probe("middle")
                Color.mint.frame(width: 70, height: 50).probe("last")
            }
            .probe("hstack")
        }
        .probe("stack")
    }

    public static let hidden = Fixture("effects/hidden", size: CGSize(width: 240, height: 200)) {
        VStack(spacing: 10) {
            Text("Above").probe("above")
            Color.red.frame(width: 80, height: 30).hidden().probe("hidden")
            Text("Below").probe("below")
            HStack(spacing: 8) {
                Button("Ghost") {}.hidden().probe("ghostButton")
                Color.blue.frame(width: 40, height: 20).probe("visible")
            }
            .probe("row")
            Color.green.frame(width: 60, height: 20).opacity(0).probe("transparent")
        }
        .probe("stack")
    }

    public static let all: [Fixture] = [shadow, shadowProfile, shadowOffset, zIndex, hidden]
}
