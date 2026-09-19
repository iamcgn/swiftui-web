import SwiftUI
import FixtureKit

// The scroll position, content margins, geometry and anchor-role APIs (Docs/elements/ScrollView.md,
// "Scroll position, targets and geometry"). Values a golden cannot show as pixels are encoded
// in probe widths: `ValueProbe` is 1 pt tall and `value + 100` wide.

/// Drives the behaviour fixtures: the positioned row, a reader target, the row count.
@Observable
public final class ScrollAPIModel {
    public var position: Int? = 10
    public var target: Int? = nil
    public var targetAnchor: UnitPoint? = .top
    public var count = 20
    public var sample = GeometrySample()
    public var phaseChanges = 0
    public var geometryCalls = 0
    public init() {}
}

/// The parts of a `ScrollGeometry` the geometry fixture records.
public struct GeometrySample: Equatable, Sendable {
    public var offset = CGPoint.zero
    public var size = CGSize.zero
    public var insets = EdgeInsets()
    public var container = CGSize.zero
    public var visible = CGRect.zero
    public var bounds = CGRect.zero
    public init() {}
}

/// A 1 pt tall probe whose width is `value + 100`, so negatives stay measurable.
struct ValueProbe: View {
    let name: String
    let value: CGFloat
    init(_ name: String, _ value: CGFloat) {
        self.name = name
        self.value = value
    }
    var body: some View {
        Color.clear.frame(width: max(1, value + 100), height: 1).probe(name)
    }
}

/// `count` identified rows, `height` tall, probed as `<prefix><i>`.
struct IDRows: View {
    var count: Int
    var prefix = "row"
    var height: CGFloat = 20

    var body: some View {
        ForEach(0..<count, id: \.self) { index in
            (index.isMultiple(of: 2) ? Color.blue : Color.orange)
                .frame(width: 120, height: height)
                .probe("\(prefix)\(index)")
                .id(index)
        }
    }
}

/// A scroll view positioned by `model.position` through `scrollPosition(id:anchor:)`; a reader
/// scrolls to `model.target` so the binding's reads can be measured.
struct PositionedRows: View {
    let model: ScrollAPIModel
    var anchor: UnitPoint? = nil
    var rowHeight: CGFloat = 20
    var lazy = true

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    if lazy {
                        LazyVStack(spacing: 0) { IDRows(count: 30, height: rowHeight) }.scrollTargetLayout()
                    } else {
                        VStack(spacing: 0) { IDRows(count: 30, height: rowHeight) }.scrollTargetLayout()
                    }
                }
                .scrollPosition(id: Binding(get: { model.position }, set: { model.position = $0 }), anchor: anchor)
                .probe("scroll")
                .onChange(of: model.target) { _, target in
                    if let target { proxy.scrollTo(target, anchor: model.targetAnchor) }
                }
            }
            ValueProbe("position", CGFloat(model.position ?? -1))
        }
    }
}

/// A scroll view reporting its geometry and phase changes through the model.
struct GeometryRows: View {
    let model: ScrollAPIModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) { IDRows(count: 20, prefix: "g") }
                }
                .contentMargins(.top, 20, for: .scrollContent)
                .frame(height: 150)
                .probe("scroll")
                .onScrollGeometryChange(for: GeometrySample.self) { geometry in
                    var sample = GeometrySample()
                    sample.offset = geometry.contentOffset
                    sample.size = geometry.contentSize
                    sample.insets = geometry.contentInsets
                    sample.container = geometry.containerSize
                    sample.visible = geometry.visibleRect
                    sample.bounds = geometry.bounds
                    return sample
                } action: { _, sample in
                    model.sample = sample
                    model.geometryCalls += 1
                }
                .onScrollPhaseChange { _, _ in model.phaseChanges += 1 }
                .onChange(of: model.target) { _, target in
                    if let target { proxy.scrollTo(target, anchor: .top) }
                }
            }
            let sample = model.sample
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    ValueProbe("offsetX", sample.offset.x)
                    ValueProbe("offsetY", sample.offset.y)
                    ValueProbe("sizeW", sample.size.width)
                    ValueProbe("sizeH", sample.size.height)
                    ValueProbe("insetTop", sample.insets.top)
                    ValueProbe("insetBottom", sample.insets.bottom)
                    ValueProbe("insetLeading", sample.insets.leading)
                    ValueProbe("containerW", sample.container.width)
                }
                VStack(spacing: 0) {
                    ValueProbe("containerH", sample.container.height)
                    ValueProbe("visibleY", sample.visible.minY)
                    ValueProbe("visibleH", sample.visible.height)
                    ValueProbe("boundsY", sample.bounds.minY)
                    ValueProbe("boundsH", sample.bounds.height)
                    ValueProbe("phaseChanges", CGFloat(model.phaseChanges))
                    ValueProbe("geometryCalls", CGFloat(model.geometryCalls))
                }
            }
        }
    }
}

/// Anchor roles: alignment of short content, and the anchor kept as the content grows.
struct AnchorRoles: View {
    let model: ScrollAPIModel

    var body: some View {
        HStack(spacing: 20) {
            ScrollView { VStack(spacing: 0) { IDRows(count: 3, prefix: "a") } }
                .defaultScrollAnchor(.bottom, for: .alignment)
                .probe("bottomAligned")
            ScrollView { VStack(spacing: 0) { IDRows(count: 3, prefix: "b") } }
                .defaultScrollAnchor(.center, for: .alignment)
                .probe("centerAligned")
            ScrollView { VStack(spacing: 0) { IDRows(count: model.count, prefix: "c") } }
                .defaultScrollAnchor(.bottom, for: .sizeChanges)
                .probe("sizeChanges")
            ScrollView { VStack(spacing: 0) { IDRows(count: model.count, prefix: "d") } }
                .defaultScrollAnchor(.bottom)
                .defaultScrollAnchor(.bottom, for: .sizeChanges)
                .probe("bottomGrows")
        }
    }
}

public enum ScrollAPIFixtures {
    /// `scrollPosition(id:)`: the initial value positions row 10 at the top; setting it scrolls;
    /// a reader scroll updates the binding (rows 20 tall, 200 pt viewport).
    public static let position = Fixture(
        "scroll/position", size: CGSize(width: 300, height: 220),
        model: { ScrollAPIModel() },
        steps: [
            FixtureStep("row20") { $0.position = 20 },
            FixtureStep("proxy5") { $0.target = 5 },                                    // row 5 at the top
            FixtureStep("proxy-center") { $0.targetAnchor = .center; $0.target = 7 },  // rows 2.5–12.5 visible
        ]
    ) { model in
        PositionedRows(model: model)
    }

    /// `scrollPosition(id:anchor: .center)` with 30 pt rows in a plain stack (Apple's lazy stack
    /// parked rows 0–5 off screen): the initial value does not scroll; row 7 at the top puts
    /// row 10 (300–330) across the centre line.
    public static let positionCenter = Fixture(
        "scroll/position-center", size: CGSize(width: 300, height: 220),
        model: { ScrollAPIModel() },
        steps: [
            FixtureStep("proxy7") { $0.target = 7 },
        ]
    ) { model in
        PositionedRows(model: model, anchor: .center, rowHeight: 30, lazy: false)
    }

    /// `contentMargins`: for the scroll content (all edges, horizontal only), automatic, and for
    /// the indicators only.
    public static let margins = Fixture("scroll/margins", size: CGSize(width: 600, height: 200)) {
        HStack(spacing: 20) {
            ScrollView { VStack(spacing: 0) { IDRows(count: 20, prefix: "a") } }
                .contentMargins(20, for: .scrollContent)
                .probe("content")
            ScrollView { VStack(spacing: 0) { IDRows(count: 3, prefix: "b") } }
                .contentMargins(.horizontal, 12, for: .scrollContent)
                .probe("horizontal")
            ScrollView { VStack(spacing: 0) { IDRows(count: 3, prefix: "c") } }
                .contentMargins(.top, 30)
                .probe("automatic")
            ScrollView { VStack(spacing: 0) { IDRows(count: 20, prefix: "d") } }
                .contentMargins(20, for: .scrollIndicators)
                .probe("indicators")
        }
    }

    /// `onScrollGeometryChange` and `onScrollPhaseChange`: the geometry at rest with a 20 pt top
    /// content margin, then after a reader scroll to row 10.
    public static let geometry = Fixture(
        "scroll/geometry", size: CGSize(width: 300, height: 200),
        model: { ScrollAPIModel() },
        steps: [FixtureStep("row10") { $0.target = 10 }]
    ) { model in
        GeometryRows(model: model)
    }

    /// `defaultScrollAnchor(_:for:)`: `.alignment` for short content, `.sizeChanges` as rows are
    /// added (20 → 25).
    public static let anchorRoles = Fixture(
        "scroll/anchor-roles", size: CGSize(width: 600, height: 200),
        model: { ScrollAPIModel() },
        steps: [FixtureStep("grow") { $0.count = 25 }]
    ) { model in
        AnchorRoles(model: model)
    }

    /// `scrollIndicatorsFlash(onAppear: true)`: the overlay scroller, if the capture catches it.
    public static let flash = Fixture("scroll/flash", size: CGSize(width: 300, height: 200)) {
        ScrollView { VStack(spacing: 0) { IDRows(count: 20) } }
            .scrollIndicatorsFlash(onAppear: true)
            .probe("scroll")
    }

    /// The position fixture on iPhone (UIScrollView-backed, 40 pt rows so the content overflows
    /// the 666 pt viewport): the initial value, a set, a reader scroll.
    public static let iosPosition = Fixture(
        "ios/scroll/position", size: CGSize(width: 375, height: 667),
        model: { ScrollAPIModel() },
        steps: [
            FixtureStep("row20") { $0.position = 20 },
            FixtureStep("proxy5") { $0.target = 5 },
        ]
    ) { model in
        PositionedRows(model: model, rowHeight: 40)
    }.platform(.iOS)

    /// The geometry fixture on iPhone: the safe area and the content margin as insets.
    public static let iosGeometry = Fixture(
        "ios/scroll/geometry", size: CGSize(width: 375, height: 667),
        model: { ScrollAPIModel() },
        steps: [FixtureStep("row10") { $0.target = 10 }]
    ) { model in
        GeometryRows(model: model)
    }.platform(.iOS)

    public static let all: [Fixture] = [position, positionCenter, margins, geometry, anchorRoles, flash, iosPosition, iosGeometry]
}
