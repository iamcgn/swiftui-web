// Layout fixtures: only Color, stacks, Spacer, Divider and layout modifiers, so they hold
// before text exists. Each also pins one undocumented constant (see PlatformMetrics).
import SwiftUI
import FixtureKit

public enum LayoutFixtures {
    static func box(_ color: Color, _ w: CGFloat, _ h: CGFloat) -> some View {
        color.frame(width: w, height: h)
    }

    public static let rootCentering = Fixture("layout/root-centering", size: CGSize(width: 200, height: 100)) {
        Color.red.frame(width: 50, height: 30).probe("box")
    }

    public static let paddingDefault = Fixture("layout/padding-default", size: CGSize(width: 200, height: 100)) {
        Color.red.probe("inner").padding().probe("outer")
    }

    public static let paddingEdges = Fixture("layout/padding-edges", size: CGSize(width: 200, height: 100)) {
        Color.red.probe("inner").padding(.leading, 30).padding(.vertical).padding(EdgeInsets(top: 1, leading: 2, bottom: 3, trailing: 4)).probe("outer")
    }

    public static let spacingDefault = Fixture("layout/spacing-default", size: CGSize(width: 300, height: 100)) {
        HStack {
            box(.red, 50, 50).probe("a")
            box(.blue, 50, 50).probe("b")
            box(.green, 50, 50).probe("c")
        }
        .probe("stack")
    }

    public static let vstackSpacingDefault = Fixture("layout/vstack-spacing-default", size: CGSize(width: 100, height: 300)) {
        VStack {
            box(.red, 50, 50).probe("a")
            box(.blue, 50, 50).probe("b")
        }
        .probe("stack")
    }

    public static let divider = Fixture("layout/divider", size: CGSize(width: 200, height: 200)) {
        VStack(spacing: 0) {
            box(.red, 100, 20).probe("a")
            Divider().probe("hdivider")
            HStack(spacing: 0) {
                box(.blue, 20, 60).probe("b")
                Divider().probe("vdivider")
                box(.green, 20, 60).probe("c")
            }
            .probe("hstack")
        }
        .probe("vstack")
    }

    public static let hstackDistribution = Fixture("layout/hstack-distribution", size: CGSize(width: 300, height: 100)) {
        HStack(spacing: 0) {
            Color.red.probe("a")
            Color.blue.frame(width: 50).probe("b")
            Color.green.probe("c")
        }
    }

    public static let hstackPriority = Fixture("layout/hstack-priority", size: CGSize(width: 300, height: 100)) {
        HStack(spacing: 0) {
            Color.red.frame(minWidth: 20).probe("a")
            Color.blue.frame(minWidth: 20).layoutPriority(1).probe("b")
            Color.green.frame(width: 60).probe("c")
        }
    }

    public static let spacer = Fixture("layout/spacer", size: CGSize(width: 300, height: 100)) {
        HStack {
            box(.red, 50, 50).probe("a")
            Spacer().probe("spacer")
            box(.blue, 50, 50).probe("b")
        }
        .probe("stack")
    }

    public static let spacerMinLength = Fixture("layout/spacer-min-length", size: CGSize(width: 300, height: 100)) {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                box(.red, 250, 20).probe("a")
                Spacer(minLength: 20).probe("s1")
                box(.blue, 100, 20).probe("b")
            }
            .probe("overflow")
            HStack(spacing: 0) {
                Spacer().probe("s2")
                box(.green, 40, 20).probe("c")
                Spacer().probe("s3")
            }
            .probe("balanced")
            Spacer().probe("vspacer")
        }
    }

    public static let vstackAlignment = Fixture("layout/vstack-alignment", size: CGSize(width: 300, height: 200)) {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                box(.red, 100, 20).probe("l1")
                box(.blue, 50, 20).probe("l2")
            }
            .probe("leading")
            VStack(alignment: .trailing, spacing: 4) {
                box(.red, 100, 20).probe("t1")
                box(.blue, 50, 20).probe("t2")
            }
            .probe("trailing")
        }
    }

    public static let hstackAlignment = Fixture("layout/hstack-alignment", size: CGSize(width: 300, height: 200)) {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 4) {
                box(.red, 20, 60).probe("top1")
                box(.blue, 20, 30).probe("top2")
            }
            HStack(alignment: .bottom, spacing: 4) {
                box(.red, 20, 60).probe("bottom1")
                box(.blue, 20, 30).probe("bottom2")
            }
        }
    }

    public static let zstack = Fixture("layout/zstack", size: CGSize(width: 200, height: 200)) {
        ZStack(alignment: .bottomTrailing) {
            box(.red, 100, 100).probe("a")
            box(.blue, 30, 30).probe("b")
        }
        .probe("stack")
    }

    public static let zstackFill = Fixture("layout/zstack-fill", size: CGSize(width: 200, height: 200)) {
        ZStack(alignment: .topLeading) {
            Color.red.probe("fill")
            box(.blue, 30, 30).probe("b")
        }
    }

    public static let frameFixed = Fixture("layout/frame-fixed", size: CGSize(width: 200, height: 200)) {
        box(.red, 40, 40).probe("inner")
            .frame(width: 120, height: 80, alignment: .topLeading)
            .probe("outer")
    }

    public static let frameFlex = Fixture("layout/frame-flex", size: CGSize(width: 300, height: 300)) {
        VStack(spacing: 0) {
            box(.red, 40, 20).frame(minWidth: 100).probe("min")
            box(.red, 40, 20).frame(maxWidth: 200).probe("max")
            box(.red, 40, 20).frame(minWidth: 50, maxWidth: .infinity).probe("fill")
            box(.red, 40, 20).frame(idealWidth: 150).fixedSize().probe("ideal")
            Color.red.frame(maxWidth: 120, maxHeight: 20).probe("clampFlexible")
            box(.red, 250, 20).frame(maxWidth: 200).probe("overflow")
        }
    }

    public static let fixedSize = Fixture("layout/fixed-size", size: CGSize(width: 200, height: 200)) {
        VStack(spacing: 0) {
            Color.red.fixedSize().probe("both")
            Color.blue.fixedSize(horizontal: true, vertical: false).frame(height: 30).probe("horizontal")
        }
    }

    public static let alignmentGuide = Fixture("layout/alignment-guide", size: CGSize(width: 300, height: 200)) {
        VStack(alignment: .leading, spacing: 4) {
            box(.red, 100, 20).alignmentGuide(.leading) { $0[.trailing] }.probe("a")
            box(.blue, 50, 20).probe("b")
            box(.green, 30, 20).alignmentGuide(.leading) { $0.width / 2 }.probe("c")
        }
        .probe("stack")
    }

    public static let groupModifier = Fixture("layout/group-modifier", size: CGSize(width: 300, height: 100)) {
        HStack(spacing: 0) {
            Group {
                Color.red.probe("a")
                Color.blue.probe("b")
            }
            .frame(width: 50, height: 50)
            .padding(5)
            Color.green.probe("c")
        }
    }

    public static let nestedStacks = Fixture("layout/nested-stacks", size: CGSize(width: 300, height: 200)) {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Color.red.probe("a")
                Color.blue.frame(width: 80).probe("b")
            }
            .padding(10)
            .probe("row")
            HStack {
                box(.green, 40, 40).probe("c")
                Spacer()
                box(.yellow, 40, 40).probe("d")
            }
            .frame(height: 60)
            .probe("bottom")
        }
    }

    public static let hstackIdeal = Fixture("layout/hstack-ideal", size: CGSize(width: 300, height: 200)) {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                box(.red, 30, 30).probe("a")
                box(.blue, 40, 30).probe("b")
            }
            .probe("row")
            box(.green, 200, 10).probe("wide")
        }
        .probe("column")
    }

    public static let all: [Fixture] = [
        rootCentering, paddingDefault, paddingEdges, spacingDefault, vstackSpacingDefault, divider,
        hstackDistribution, hstackPriority, spacer, spacerMinLength, vstackAlignment, hstackAlignment,
        zstack, zstackFill, frameFixed, frameFlex, fixedSize, alignmentGuide, groupModifier,
        nestedStacks, hstackIdeal,
    ]
}
