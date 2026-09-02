// Image fixtures: named images from Fixtures/Assets.xcassets (the asset catalog format Xcode
// writes), intrinsic sizes, resizing, aspect ratio, template tinting, stack spacing, tiling and
// cap insets, and a behaviour fixture that swaps the image name.
import SwiftUI
import FixtureKit

/// Drives `image/swap`: the image shown follows `name`.
@Observable
public final class ImageNameModel {
    public var name = "swatch"
    public init() {}
}

public enum ImageFixtures {
    /// Intrinsic sizes: pixels ÷ scale for 1×+2×, 2×-only and JPEG sets; folder namespaces; the
    /// mac idiom over universal; the light appearance; a missing name is 0 × 0.
    public static let intrinsic = Fixture("image/intrinsic", size: CGSize(width: 300, height: 200)) {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 4) {
                Image("swatch").probe("swatch")
                Image("tall").probe("tall")
                Image("photo").probe("photo")
            }
            .probe("row1")
            HStack(alignment: .top, spacing: 4) {
                Image("Folder/nested").probe("nested")
                Image("loose").probe("loose")
                Image("badge").probe("badge")
                Image("dual").probe("dual")
                Image("missing").probe("missing")
                Image("nested").probe("wrongNamespace")
            }
            .probe("row2")
        }
        .probe("stack")
    }

    /// `resizable()` takes the proposal; a non-resizable image keeps its size, centred in and
    /// overflowing a smaller frame unless clipped.
    public static let resizable = Fixture("image/resizable", size: CGSize(width: 300, height: 200)) {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image("swatch").resizable().frame(width: 30, height: 30).probe("shrunk")
                Image("swatch").resizable().frame(width: 96, height: 30).probe("stretched")
                Image("swatch").frame(width: 30, height: 30).probe("overflow")
                Image("swatch").frame(width: 30, height: 30).clipped().probe("overflowClipped")
            }
            .probe("row1")
            Image("swatch").resizable().frame(height: 24).probe("flexibleWidth")
            HStack(spacing: 0) {
                Image("tall").resizable().probe("flexA")
                Image("swatch").resizable().probe("flexB")
            }
            .frame(height: 40)
            .probe("row3")
            Image("swatch").resizable().padding(10).background(Color.yellow).frame(width: 120, height: 60).probe("padded")
        }
        .probe("stack")
    }

    /// `aspectRatio` / `scaledToFit` / `scaledToFill` with full, partial and no proposals, on
    /// resizable and rigid images and on a colour.
    public static let aspectRatio = Fixture("image/aspect-ratio", size: CGSize(width: 400, height: 340)) {
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image("swatch").resizable().scaledToFit().probe("fitWideImage").frame(width: 100, height: 40).probe("fitWide")
                Image("swatch").resizable().scaledToFit().probe("fitTallImage").frame(width: 40, height: 100).probe("fitTall")
                Image("swatch").resizable().scaledToFill().probe("fillImage").frame(width: 40, height: 60).probe("fill")
                Image("swatch").resizable().scaledToFill().probe("fillClippedImage").frame(width: 40, height: 60).clipped().probe("fillClipped")
                Image("swatch").resizable().aspectRatio(1, contentMode: .fit).probe("squareImage").frame(width: 60, height: 40).probe("square")
                Image("swatch").resizable().aspectRatio(CGSize(width: 1, height: 3), contentMode: .fill).probe("thirdImage").frame(width: 30, height: 30).probe("third")
            }
            .probe("row1")
            HStack(alignment: .top, spacing: 8) {
                Image("swatch").resizable().scaledToFit().probe("widthOnlyImage").frame(width: 100).probe("widthOnly")
                Image("swatch").resizable().scaledToFit().probe("heightOnlyImage").frame(height: 30).probe("heightOnly")
                Image("swatch").scaledToFit().probe("rigidImage").frame(width: 100, height: 40).probe("rigid")
                Image("tall").resizable().scaledToFit().probe("flexibleImage")
            }
            .frame(height: 100)
            .probe("row2")
            Color.blue.aspectRatio(2, contentMode: .fit).probe("colorRatio").frame(width: 100, height: 100).probe("colorRatioFrame")
        }
        .probe("stack")
    }

    /// Template images take the foreground colour (primary by default); `renderingMode` forces
    /// either mode; opacity applies on top.
    public static let template = Fixture("image/template", size: CGSize(width: 400, height: 120)) {
        HStack(spacing: 8) {
            Image("icon").probe("default")
            Image("icon").foregroundColor(.red).probe("red")
            Image("icon").foregroundStyle(.blue).probe("blue")
            Image("icon").renderingMode(.original).probe("original")
            Image("swatch").renderingMode(.template).foregroundColor(.green).probe("forced")
            Image("swatch").renderingMode(.template).probe("forcedDefault")
            Image("icon").resizable().frame(width: 48, height: 48).foregroundColor(.orange).probe("big")
            Image("icon").opacity(0.5).probe("faded")
        }
        .probe("row")
    }

    /// Images are plain views for spacing (8 pt) and alignment (baseline at the bottom edge).
    public static let stackSpacing = Fixture("image/stack-spacing", size: CGSize(width: 300, height: 280)) {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: nil) {
                Image("swatch").probe("hImage")
                Text("Hg").probe("hText")
                Image("swatch").probe("hImage2")
                Color.clear.frame(width: 10, height: 10).probe("hBox")
            }
            .probe("hstack")
            VStack(spacing: nil) {
                Image("swatch").probe("vImage")
                Text("Hg").probe("vText")
                Image("swatch").probe("vImage2")
                Color.clear.frame(width: 10, height: 10).probe("vBox")
            }
            .probe("vstack")
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("Hg").probe("blText")
                Image("swatch").probe("blImage")
            }
            .probe("baseline")
            HStack(alignment: .lastTextBaseline, spacing: 0) {
                Text("Hg").probe("lblText")
                Image("swatch").probe("lblImage")
            }
            .probe("lastBaseline")
        }
        .probe("stack")
    }

    /// Cap insets (nine-part stretching and tiling), whole-image tiling and nearest-neighbour
    /// interpolation; the frames are fixed, the pixels are the test.
    public static let tiling = Fixture("image/tiling", size: CGSize(width: 300, height: 200)) {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image("panel").resizable(capInsets: EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)).frame(width: 120, height: 80).probe("sliced")
                Image("panel").resizable(capInsets: EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8), resizingMode: .tile).frame(width: 120, height: 80).probe("slicedTiled")
            }
            .probe("row1")
            HStack(spacing: 8) {
                Image("swatch").resizable(resizingMode: .tile).frame(width: 150, height: 90).probe("tiled")
                Image("swatch").resizable().interpolation(.none).frame(width: 96, height: 60).probe("nearest")
            }
            .probe("row2")
        }
        .probe("stack")
    }

    /// Behaviour: the layout follows the image a name resolves to, including a missing one.
    public static let swap = Fixture(
        "image/swap", size: CGSize(width: 300, height: 200),
        model: { ImageNameModel() },
        steps: [
            FixtureStep("tall") { $0.name = "tall" },
            FixtureStep("missing") { $0.name = "nope" },
            FixtureStep("back") { $0.name = "swatch" },
        ]
    ) { model in
        HStack(alignment: .top) {
            Image(model.name).probe("image")
            Text("Hg").probe("text")
        }
        .probe("row")
    }

    public static let all: [Fixture] = [intrinsic, resizable, aspectRatio, template, stackSpacing, tiling, swap]
}
