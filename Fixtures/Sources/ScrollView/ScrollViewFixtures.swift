import SwiftUI
import FixtureKit

/// A column of 20 pt rows in alternating colours, `count` of them, each probed as `row<i>`.
struct Rows: View {
    var count: Int
    var width: CGFloat = 120
    var spacing: CGFloat = 0

    var body: some View {
        VStack(spacing: spacing) {
            ForEach(0..<count, id: \.self) { index in
                (index.isMultiple(of: 2) ? Color.blue : Color.orange)
                    .frame(width: width, height: 20)
                    .probe("row\(index)")
            }
        }
    }
}

/// Drives `scroll/scroll-to`: setting `target` scrolls the row with that id into view.
@Observable
public final class ScrollTargetModel {
    public var target: Int? = nil
    public var anchor: UnitPoint? = nil
    public init() {}
}

struct ScrollToRows: View {
    let model: ScrollTargetModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(0..<20, id: \.self) { index in
                        (index.isMultiple(of: 2) ? Color.blue : Color.orange)
                            .frame(width: 120, height: 20)
                            .probe("row\(index)")
                            .id(index)
                    }
                }
                .probe("content")
            }
            .probe("scroll")
            .onChange(of: model.target) { _, target in
                if let target { proxy.scrollTo(target, anchor: model.anchor) }
            }
        }
    }
}

public enum ScrollViewFixtures {
    /// Content shorter than the viewport: where the scroll view and its content sit.
    public static let vertical = Fixture("scroll/vertical", size: CGSize(width: 300, height: 200)) {
        ScrollView {
            Rows(count: 3).probe("content")
        }
        .probe("scroll")
    }

    /// Content taller than the viewport; the initial offset is zero and rows below the fold keep
    /// their frames in the root space.
    public static let verticalOverflow = Fixture("scroll/vertical-overflow", size: CGSize(width: 300, height: 200)) {
        ScrollView {
            Rows(count: 20, spacing: 8).probe("content")
        }
        .probe("scroll")
    }

    public static let horizontal = Fixture("scroll/horizontal", size: CGSize(width: 300, height: 200)) {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(0..<12, id: \.self) { index in
                    (index.isMultiple(of: 2) ? Color.blue : Color.orange)
                        .frame(width: 60, height: 40)
                        .probe("cell\(index)")
                }
            }
            .probe("content")
        }
        .probe("scroll")
    }

    public static let both = Fixture("scroll/both", size: CGSize(width: 300, height: 200)) {
        ScrollView([.horizontal, .vertical]) {
            Color.blue.frame(width: 500, height: 400).probe("content")
        }
        .probe("scroll")
    }

    /// The cross axis when the content is narrower than the space a frame proposes.
    public static let narrowContent = Fixture("scroll/narrow-content", size: CGSize(width: 300, height: 200)) {
        ScrollView {
            Color.blue.frame(width: 100, height: 400).probe("content")
        }
        .probe("scroll")
        .frame(width: 250, height: 150)
        .probe("frame")
    }

    /// The cross axis when the content is wider than the proposal.
    public static let wideContent = Fixture("scroll/wide-content", size: CGSize(width: 300, height: 200)) {
        ScrollView {
            Color.blue.frame(width: 400, height: 400).probe("content")
        }
        .probe("scroll")
    }

    /// Text wraps at the width the scroll view proposes.
    public static let text = Fixture("scroll/text", size: CGSize(width: 300, height: 200)) {
        ScrollView {
            Text("Layout must wrap this sentence onto several lines inside a narrow frame.").probe("text")
        }
        .probe("scroll")
    }

    /// A scroll view between fixed siblings takes the remaining length of the stack.
    public static let inStack = Fixture("scroll/in-stack", size: CGSize(width: 300, height: 200)) {
        VStack(spacing: 0) {
            Text("Header").probe("header")
            ScrollView {
                Rows(count: 20).probe("content")
            }
            .probe("scroll")
            Text("Footer").probe("footer")
        }
        .probe("stack")
    }

    /// Padding inside the content is part of the scrollable size.
    public static let padding = Fixture("scroll/padding", size: CGSize(width: 300, height: 200)) {
        ScrollView {
            Rows(count: 20).padding().probe("padded")
        }
        .probe("scroll")
    }

    /// `defaultScrollAnchor(.bottom)` starts at the end of the content.
    public static let anchorBottom = Fixture("scroll/anchor-bottom", size: CGSize(width: 300, height: 200)) {
        ScrollView {
            Rows(count: 20).probe("content")
        }
        .defaultScrollAnchor(.bottom)
        .probe("scroll")
    }

    /// Indicator and interaction modifiers leave layout alone.
    public static let modifiers = Fixture("scroll/modifiers", size: CGSize(width: 300, height: 200)) {
        HStack(spacing: 20) {
            ScrollView(showsIndicators: false) {
                Rows(count: 20, width: 80).probe("contentA")
            }
            .probe("scrollA")
            ScrollView {
                Rows(count: 20, width: 80).probe("contentB")
            }
            .scrollIndicators(.hidden)
            .scrollDisabled(true)
            .probe("scrollB")
        }
        .probe("row")
    }

    /// Several views in a scroll view's builder: how they are arranged along each axis.
    public static let children = Fixture("scroll/children", size: CGSize(width: 300, height: 200)) {
        HStack(alignment: .top, spacing: 20) {
            ScrollView {
                Text("Top").probe("vTop")
                Color.blue.frame(width: 60, height: 30).probe("vBlock")
                Text("Bottom").probe("vBottom")
            }
            .probe("vScroll")
            ScrollView(.horizontal) {
                Text("Top").probe("hTop")
                Color.blue.frame(width: 60, height: 30).probe("hBlock")
                Text("Bottom").probe("hBottom")
            }
            .probe("hScroll")
        }
        .probe("row")
    }

    /// Behaviour: `ScrollViewReader.scrollTo` with and without an anchor.
    public static let scrollTo = Fixture(
        "scroll/scroll-to", size: CGSize(width: 300, height: 200),
        model: { ScrollTargetModel() },
        steps: [
            FixtureStep("row15") { $0.target = 15 },                               // below the fold: minimal scroll
            FixtureStep("row3-top") { $0.anchor = .top; $0.target = 3 },
            FixtureStep("row10-center") { $0.anchor = .center; $0.target = 10 },
            FixtureStep("row0") { $0.anchor = nil; $0.target = 0 },                // above: back to the top
        ]
    ) { model in
        ScrollToRows(model: model)
    }

    public static let all: [Fixture] = [vertical, verticalOverflow, horizontal, both, narrowContent, wideContent, text,
                                        inStack, padding, anchorBottom, modifiers, children, scrollTo]
}
