// Representable fixtures (`ios/representable/…`, decision 0014 Phase 2): SwiftUI views hosting
// UIKit views and view controllers, rendered by Apple's SwiftUI over Apple's UIKit on the iPhone
// simulator and reproduced by SwiftUIWebUIKit over UIKitWeb. They pin how SwiftUI sizes a
// representable from the UIKit view's intrinsic content size and priorities, how the
// representable's own `sizeThatFits` is honoured, how it spaces and aligns next to SwiftUI
// views, and that updates flow through `updateUIView`.
import SwiftUI
import FixtureKit
#if canImport(UIKit)
import UIKit

/// A plain table whose three rows are `UIHostingConfiguration`s.
struct HostingCellsTable: UIViewRepresentable {
    final class Source: NSObject, UITableViewDataSource {
        func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 3 }
        func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            switch indexPath.row {
            case 0:
                cell.contentConfiguration = UIHostingConfiguration {
                    HStack {
                        Text("Row 1")
                        Spacer()
                        Text("Detail").foregroundStyle(.secondary)
                    }
                }
            case 1:
                cell.contentConfiguration = UIHostingConfiguration {
                    HStack {
                        Text("Row 2")
                        Spacer()
                        Text("Detail").foregroundStyle(.secondary)
                    }
                }
                .margins(.horizontal, 40)
                .background(Color.yellow)
            default:
                cell.contentConfiguration = UIHostingConfiguration {
                    Text("Row 3")
                }
                .minSize(height: 80)
            }
            return cell
        }
    }

    func makeCoordinator() -> Source { Source() }
    func makeUIView(context: Context) -> UITableView {
        let table = UITableView(frame: .zero, style: .plain)
        table.dataSource = context.coordinator
        table.isScrollEnabled = false
        return table
    }
    func updateUIView(_ uiView: UITableView, context: Context) {}
}

/// A UIKit view with no intrinsic size.
struct PlainBox: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .systemBlue
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

/// A label; `hugging` and `resistance` replace UILabel's default priorities (251 / 750) on both
/// axes when given.
struct LabelBox: UIViewRepresentable {
    var text = "Hello"
    var hugging: Float? = nil
    var resistance: Float? = nil
    var lines = 1

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.font = .systemFont(ofSize: 17)
        label.numberOfLines = lines
        label.backgroundColor = .systemYellow
        if let hugging {
            label.setContentHuggingPriority(UILayoutPriority(hugging), for: .horizontal)
            label.setContentHuggingPriority(UILayoutPriority(hugging), for: .vertical)
        }
        if let resistance {
            label.setContentCompressionResistancePriority(UILayoutPriority(resistance), for: .horizontal)
            label.setContentCompressionResistancePriority(UILayoutPriority(resistance), for: .vertical)
        }
        return label
    }
    func updateUIView(_ uiView: UILabel, context: Context) { uiView.text = text }
}

struct SwitchBox: UIViewRepresentable {
    var isOn = true
    func makeUIView(context: Context) -> UISwitch { UISwitch() }
    func updateUIView(_ uiView: UISwitch, context: Context) { uiView.isOn = isOn }
}

struct FieldBox: UIViewRepresentable {
    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.borderStyle = .roundedRect
        field.text = "Field"
        return field
    }
    func updateUIView(_ uiView: UITextField, context: Context) {}
}

struct ButtonBox: UIViewRepresentable {
    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle("Tap", for: .normal)
        return button
    }
    func updateUIView(_ uiView: UIButton, context: Context) {}
}

/// A representable that sizes itself: a fixed 44 × 22.
struct FixedBox: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .systemGreen
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIView, context: Context) -> CGSize? {
        CGSize(width: 44, height: 22)
    }
}

/// A representable that takes the proposed width (100 when none) and is 20 tall.
struct ProposalBox: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .systemOrange
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 100, height: 20)
    }
}

/// A view controller whose view holds a label at a fixed frame; its preferred content size is
/// 80 × 40.
final class BoxController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemPink
        let label = UILabel()
        label.text = "Inside"
        label.font = .systemFont(ofSize: 17)
        label.frame = CGRect(x: 8, y: 4, width: 60, height: 20)
        view.addSubview(label)
        preferredContentSize = CGSize(width: 80, height: 40)
    }
}

struct ControllerBox: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> BoxController { BoxController() }
    func updateUIViewController(_ uiViewController: BoxController, context: Context) {}
}

// MARK: Safe areas and traits (Phase 8: ix-layout-options, ix-traits)

/// A view that shows its safe area: blue over its bounds, green over the bounds inset by its
/// `safeAreaInsets`.
final class SafeAreaView: UIView {
    let safe = UIView()

    static func make() -> SafeAreaView {
        let view = SafeAreaView()
        view.backgroundColor = .systemBlue
        view.safe.backgroundColor = .systemGreen
        view.addSubview(view.safe)
        return view
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        safe.frame = bounds.inset(by: safeAreaInsets)
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        setNeedsLayout()
    }
}

struct SafeAreaBox: UIViewRepresentable {
    func makeUIView(context: Context) -> SafeAreaView { SafeAreaView.make() }
    func updateUIView(_ uiView: SafeAreaView, context: Context) {}
}

/// A scroll view over 800 pt of 50 pt stripes: the first red, then blue and green in turn.
struct StripesScrollBox: UIViewRepresentable {
    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.backgroundColor = .systemBackground
        for index in 0..<16 {
            let stripe = UIView(frame: CGRect(x: 0, y: CGFloat(index) * 50, width: 320, height: 50))
            stripe.backgroundColor = index == 0 ? .systemRed : (index % 2 == 1 ? .systemBlue : .systemGreen)
            scroll.addSubview(stripe)
        }
        scroll.contentSize = CGSize(width: 320, height: 800)
        return scroll
    }
    func updateUIView(_ uiView: UIScrollView, context: Context) {}
}

/// A navigation (or tab bar) controller whose screen is a hosting controller showing yellow
/// that ignores the safe area under green that respects it.
struct HostingNavBox: UIViewControllerRepresentable {
    var regions: SafeAreaRegions = .all
    var tabs = false

    func makeUIViewController(context: Context) -> UIViewController {
        let hosting = UIHostingController(rootView: ZStack { Color.yellow.ignoresSafeArea(); Color.green })
        hosting.safeAreaRegions = regions
        hosting.title = "Settings"
        if tabs {
            let controller = UITabBarController()
            hosting.tabBarItem = UITabBarItem(title: "Home", image: UIImage(systemName: "house"), tag: 0)
            controller.viewControllers = [hosting]
            return controller
        }
        return UINavigationController(rootViewController: hosting)
    }
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

/// A view that draws its traits as red bars on white, 8 pt tall and 12 apart, each 20 pt wide
/// plus 20 per step of its value: the appearance (light 1, dark 2), the content size category
/// (its index from extraSmall, plus one), the layout direction (left to right 1, right to left
/// 2), the horizontal and vertical size classes (compact 1, regular 2), and the effective
/// layout direction (as the layout direction).
final class TraitView: UIView {
    static let categories: [UIContentSizeCategory] = [
        .extraSmall, .small, .medium, .large, .extraLarge, .extraExtraLarge, .extraExtraExtraLarge,
        .accessibilityMedium, .accessibilityLarge, .accessibilityExtraLarge, .accessibilityExtraExtraLarge, .accessibilityExtraExtraExtraLarge,
    ]
    static let rows = 6
    static let size = CGSize(width: 300, height: 68)

    static func make() -> TraitView {
        let view = TraitView()
        view.backgroundColor = .white
        for _ in 0..<rows {
            let bar = UIView()
            bar.backgroundColor = .red
            view.addSubview(bar)
        }
        return view
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let traits = traitCollection
        let category = Self.categories.firstIndex(of: traits.preferredContentSizeCategory) ?? -1
        let values = [traits.userInterfaceStyle.rawValue, category + 1, traits.layoutDirection.rawValue + 1,
                      traits.horizontalSizeClass.rawValue, traits.verticalSizeClass.rawValue, effectiveUserInterfaceLayoutDirection.rawValue + 1]
        for (row, bar) in subviews.enumerated() {
            bar.frame = CGRect(x: 0, y: CGFloat(row) * 12, width: 20 + 20 * CGFloat(values[row]), height: 8)
        }
    }
}

struct TraitBox: UIViewRepresentable {
    func makeUIView(context: Context) -> TraitView { TraitView.make() }
    func updateUIView(_ uiView: TraitView, context: Context) { uiView.setNeedsLayout() }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: TraitView, context: Context) -> CGSize? { TraitView.size }
}

// MARK: Lifecycle (Phase 8: ix-lifecycle)

/// The calls a representable receives, recorded outside observation.
final class RepresentableCallLog {
    var entries: [String] = []
}

@Observable final class RepresentableLifecycleModel {
    var identity = 0
    var shows = true
    /// The log as last read by a step, which the view draws.
    var shown: [String] = []
    @ObservationIgnored let log = RepresentableCallLog()
}

/// A representable that logs its coordinator's creation, make, update and dismantle, each with
/// the coordinator's number.
struct LoggingBox: UIViewRepresentable {
    let log: RepresentableCallLog

    final class Coordinator {
        let log: RepresentableCallLog
        let number: Int
        init(log: RepresentableCallLog, number: Int) {
            self.log = log
            self.number = number
            log.entries.append("coordinator\(number)")
        }
    }

    func makeCoordinator() -> Coordinator {
        let number = log.entries.filter { $0.hasPrefix("coordinator") }.count + 1
        return Coordinator(log: log, number: number)
    }

    func makeUIView(context: Context) -> UIView {
        log.entries.append("make\(context.coordinator.number)")
        let view = UIView()
        view.backgroundColor = .systemGray
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        log.entries.append("update\(context.coordinator.number)")
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.log.entries.append("dismantle\(coordinator.number)")
    }
}

/// One log entry as a bar: the kind picks the colour and a base width (coordinator 20, make 40,
/// update 60, dismantle 80), the coordinator's number adds 4 per number.
struct CallEntryBar: View {
    let entry: String
    var body: some View {
        let kinds: [(String, Color, CGFloat)] = [("coordinator", .orange, 20), ("make", .blue, 40), ("update", .green, 60), ("dismantle", .red, 80)]
        let kind = kinds.first { entry.hasPrefix($0.0) } ?? ("?", .black, 10)
        let number = CGFloat(Int(entry.dropFirst(kind.0.count)) ?? 0)
        kind.1.frame(width: kind.2 + 4 * number, height: 6)
    }
}

@Observable final class RepresentableModel {
    var text = "Hello"
    var isOn = true
}

public enum RepresentableFixtures {
    /// A view without an intrinsic size: in a 200 × 60 container, at its ideal size, and in a
    /// row next to a text.
    public static let plain = Fixture("ios/representable/plain", size: CGSize(width: 320, height: 200)) {
        VStack(alignment: .leading, spacing: 8) {
            VStack { PlainBox().probe("fill") }.frame(width: 200, height: 60).probe("fillBox")
            PlainBox().fixedSize().probe("ideal")
            HStack { Text("Hg").probe("hText"); PlainBox().probe("hBox") }.frame(height: 30).probe("hRow")
        }
        .probe("stack")
    }.platform(.iOS)

    /// A label (an intrinsic size on both axes, UILabel's default priorities 251 / 750) under a
    /// proposal larger than it, one smaller, at its ideal size, and a wrapping label in a
    /// narrow container.
    public static let label = Fixture("ios/representable/label", size: CGSize(width: 320, height: 260)) {
        VStack(alignment: .leading, spacing: 4) {
            VStack { LabelBox().probe("large") }.frame(width: 200, height: 60)
            VStack { LabelBox().probe("small") }.frame(width: 30, height: 10)
            LabelBox().fixedSize().probe("ideal")
            VStack { LabelBox(text: "The quick brown fox jumps over the lazy dog", lines: 0).probe("wrap") }.frame(width: 120, height: 100)
        }
        .probe("stack")
    }.platform(.iOS)

    /// The priorities that decide between the intrinsic size and the proposal: content hugging
    /// from 252 to 1000 under a larger proposal, compression resistance from 250 to 1000 under
    /// a smaller one.
    public static let priorities = Fixture("ios/representable/priorities", size: CGSize(width: 320, height: 520)) {
        VStack(alignment: .leading, spacing: 4) {
            VStack { LabelBox(hugging: 252).probe("hug252") }.frame(width: 200, height: 60)
            VStack { LabelBox(hugging: 500).probe("hug500") }.frame(width: 200, height: 60)
            VStack { LabelBox(hugging: 749).probe("hug749") }.frame(width: 200, height: 60)
            VStack { LabelBox(hugging: 750).probe("hug750") }.frame(width: 200, height: 60)
            VStack { LabelBox(hugging: 751).probe("hug751") }.frame(width: 200, height: 60)
            VStack { LabelBox(hugging: 1000).probe("hug1000") }.frame(width: 200, height: 60)
            VStack { LabelBox(resistance: 250).probe("squeeze250") }.frame(width: 30, height: 10)
            VStack { LabelBox(resistance: 500).probe("squeeze500") }.frame(width: 30, height: 10)
            VStack { LabelBox(resistance: 749).probe("squeeze749") }.frame(width: 30, height: 10)
            VStack { LabelBox(resistance: 751).probe("squeeze751") }.frame(width: 30, height: 10)
            VStack { LabelBox(resistance: 1000).probe("squeeze1000") }.frame(width: 30, height: 10)
        }
        .probe("stack")
    }.platform(.iOS)

    /// Controls: a switch and a system button (intrinsic sizes on both axes) in a large
    /// container and at their ideal sizes, a text field (an intrinsic height only).
    public static let controls = Fixture("ios/representable/controls", size: CGSize(width: 320, height: 320)) {
        controlsContent()
    }.platform(.iOS)

    /// The controls in the dark appearance: the environment's colour scheme reaches the hosted
    /// views as their user interface style.
    public static let darkControls = Fixture("ios/dark/representable-controls", size: CGSize(width: 320, height: 320)) {
        controlsContent()
    }.platform(.iOS).colorScheme(.dark)

    @MainActor private static func controlsContent() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack { SwitchBox().probe("switchLarge") }.frame(width: 200, height: 60)
            SwitchBox().fixedSize().probe("switchIdeal")
            VStack { FieldBox().probe("field") }.frame(width: 200, height: 60)
            VStack { ButtonBox().probe("button") }.frame(width: 200, height: 60)
            ButtonBox().fixedSize().probe("buttonIdeal")
        }
        .probe("stack")
    }

    /// The representable's own `sizeThatFits`: a fixed size, the proposal's width, the ideal
    /// size when nothing is proposed, and how a representable aligns to a text baseline.
    public static let sizing = Fixture("ios/representable/sizing", size: CGSize(width: 320, height: 340)) {
        VStack(alignment: .leading, spacing: 8) {
            VStack { FixedBox().probe("fixed") }.frame(width: 200, height: 60)
            VStack { ProposalBox().probe("proposal") }.frame(width: 200, height: 60)
            ProposalBox().fixedSize().probe("proposalIdeal")
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Hg").probe("baselineText")
                FixedBox().probe("baselineBox")
            }
            .probe("baselineRow")
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text("Hg").probe("lastText")
                FixedBox().probe("lastBox")
            }
            .probe("lastRow")
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Hg").probe("labelText")
                LabelBox(hugging: 1000).probe("labelBox")
            }
            .probe("labelRow")
        }
        .probe("stack")
    }.platform(.iOS)

    /// Stack spacing around representables: a label between texts in a column, a switch between
    /// texts in a row.
    public static let spacing = Fixture("ios/representable/spacing", size: CGSize(width: 320, height: 200)) {
        VStack(alignment: .leading, spacing: 12) {
            VStack {
                Text("Hg").probe("above")
                LabelBox(hugging: 1000).probe("mid")
                Text("Hg").probe("below")
            }
            .probe("column")
            HStack {
                Text("Hg").probe("left")
                SwitchBox().fixedSize().probe("rowSwitch")
                Text("Hg").probe("right")
            }
            .probe("row")
        }
        .probe("stack")
    }.platform(.iOS)

    /// A view controller: in a 200 × 60 container and at its ideal size (its view has no
    /// intrinsic size; `preferredContentSize` is 80 × 40).
    public static let controller = Fixture("ios/representable/controller", size: CGSize(width: 320, height: 200)) {
        VStack(alignment: .leading, spacing: 8) {
            VStack { ControllerBox().probe("controller") }.frame(width: 200, height: 60)
            ControllerBox().fixedSize().probe("controllerIdeal")
        }
        .probe("stack")
    }.platform(.iOS)

    /// Updates reach the UIKit views: a longer text widens the label, the switch turns off.
    public static let update = Fixture("ios/representable/update", size: CGSize(width: 320, height: 200),
                                       model: { RepresentableModel() },
                                       steps: [FixtureStep("longer") { $0.text = "Hello, world" }, FixtureStep("off") { $0.isOn = false }]) { model in
        VStack(alignment: .leading, spacing: 8) {
            LabelBox(text: model.text, hugging: 1000).probe("label")
            SwitchBox(isOn: model.isOn).fixedSize().probe("switch")
        }
        .probe("stack")
    }.platform(.iOS)

    public static let all: [Fixture] = [plain, label, priorities, controls, darkControls, sizing, spacing, controller, update, hostingCells,
                                        safeArea, safeAreaLarge, safeAreaIgnored, safeAreaScroll,
                                        hostingSafeArea, hostingSafeAreaNone, hostingSafeAreaTabs, traits,
                                        safeAreaColor, safeAreaInset, safeAreaScrollIgnored, safeAreaRule, lifecycle]

    /// The order of a representable's calls: at first sight, after its identity changes (a new
    /// coordinator and view, the old view dismantled) and after it leaves the tree. A step
    /// mutates the model, the next copies the log into the view, which draws one bar per entry.
    public static let lifecycle = Fixture("ios/representable/lifecycle", size: CGSize(width: 320, height: 200),
                                          model: { RepresentableLifecycleModel() },
                                          steps: [FixtureStep("read") { $0.shown = $0.log.entries },
                                                  FixtureStep("swap") { $0.identity = 1 },
                                                  FixtureStep("readSwap") { $0.shown = $0.log.entries },
                                                  FixtureStep("remove") { $0.shows = false },
                                                  FixtureStep("readRemove") { $0.shown = $0.log.entries }]) { model in
        VStack(alignment: .leading, spacing: 2) {
            if model.shows {
                LoggingBox(log: model.log).id(model.identity).frame(width: 100, height: 20).probe("box")
            }
            ForEach(Array(model.shown.enumerated()), id: \.offset) { index, entry in
                CallEntryBar(entry: entry).probe("e\(index)")
            }
        }
        .probe("stack")
    }.platform(.iOS)

    /// The rule for views away from the safe edge: a colour padded 10 from the top that ignores
    /// the safe area, one 10 below the top in a stack, and a scroll view in a row.
    public static let safeAreaRule = Fixture("ios/representable/safearea-rule", size: CGSize(width: 320, height: 300)) {
        NavigationStack {
            ZStack(alignment: .top) {
                Color.green
                HStack(alignment: .top, spacing: 0) {
                    Color.blue.ignoresSafeArea().padding(.top, 10).frame(width: 60).probe("padded")
                    VStack(spacing: 0) {
                        Color.clear.frame(height: 10)
                        Color.red.ignoresSafeArea().probe("offsetColor")
                    }
                    .frame(width: 60)
                    .probe("offset")
                    ScrollView { Color.orange.frame(height: 400).probe("scrollContent") }.frame(width: 80).probe("scroll")
                    Color.purple.ignoresSafeArea().frame(width: 60).probe("framed")
                    Color.pink.ignoresSafeArea().padding(.horizontal, 5).frame(width: 60).probe("hpadded")
                }
                .probe("row")
            }
            .probe("zstack")
            .navigationTitle("Settings")
            #if canImport(SwiftUIWebCore) || os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        .probe("nav")
    }.platform(.iOS)

    /// The control: a SwiftUI colour ignoring the safe area under the same bar, and one in a
    /// stack that does not.
    public static let safeAreaColor = Fixture("ios/representable/safearea-color", size: CGSize(width: 320, height: 300)) {
        NavigationStack {
            ZStack {
                Color.blue.ignoresSafeArea().probe("ignoring")
                Color.green.probe("plain")
            }
            .probe("zstack")
            .navigationTitle("Settings")
            #if canImport(SwiftUIWebCore) || os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        .probe("nav")
    }.platform(.iOS)

    /// A safe area SwiftUI makes (`safeAreaInset` at the bottom) around a representable: whether
    /// the UIKit view extends into it and sees it as an inset.
    public static let safeAreaInset = Fixture("ios/representable/safearea-inset", size: CGSize(width: 320, height: 300)) {
        NavigationStack {
            SafeAreaBox()
                .safeAreaInset(edge: .bottom) { Color.red.frame(height: 40).probe("inset") }
                .probe("box")
                .navigationTitle("Settings")
                #if canImport(SwiftUIWebCore) || os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
        }
        .probe("nav")
    }.platform(.iOS)

    /// A UIScrollView ignoring the safe area under the bar: the automatic content inset.
    public static let safeAreaScrollIgnored = Fixture("ios/representable/safearea-scroll-ignored", size: CGSize(width: 320, height: 300)) {
        NavigationStack {
            StripesScrollBox().ignoresSafeArea().probe("scroll")
                .navigationTitle("Settings")
                #if canImport(SwiftUIWebCore) || os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
        }
        .probe("nav")
    }.platform(.iOS)

    /// A representable under an inline navigation bar: where SwiftUI places it and what safe
    /// area the UIKit view sees (green over the safe area, blue elsewhere).
    public static let safeArea = Fixture("ios/representable/safearea", size: CGSize(width: 320, height: 300)) {
        NavigationStack {
            SafeAreaBox().probe("box")
                .navigationTitle("Settings")
                #if canImport(SwiftUIWebCore) || os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
        }
        .probe("nav")
    }.platform(.iOS)

    /// The same under a large title.
    public static let safeAreaLarge = Fixture("ios/representable/safearea-large", size: CGSize(width: 320, height: 300)) {
        NavigationStack {
            SafeAreaBox().probe("box")
                .navigationTitle("Settings")
        }
        .probe("nav")
    }.platform(.iOS)

    /// The representable told to ignore the safe area: it extends under the bar, and the safe
    /// area the view sees says whether the bar's inset still reaches it.
    public static let safeAreaIgnored = Fixture("ios/representable/safearea-ignored", size: CGSize(width: 320, height: 300)) {
        NavigationStack {
            SafeAreaBox().ignoresSafeArea().probe("box")
                .navigationTitle("Settings")
                #if canImport(SwiftUIWebCore) || os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
        }
        .probe("nav")
    }.platform(.iOS)

    /// A UIScrollView under the bar: whether it extends under it and where its content starts
    /// (the automatic content inset adjustment).
    public static let safeAreaScroll = Fixture("ios/representable/safearea-scroll", size: CGSize(width: 320, height: 300)) {
        NavigationStack {
            StripesScrollBox().probe("scroll")
                .navigationTitle("Settings")
                #if canImport(SwiftUIWebCore) || os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
        }
        .probe("nav")
    }.platform(.iOS)

    /// A hosting controller as a navigation controller's screen: the hosted SwiftUI content sees
    /// the bar's safe area (green below the bar, yellow under it).
    public static let hostingSafeArea = Fixture("ios/representable/hostingsafearea", size: CGSize(width: 320, height: 300)) {
        HostingNavBox().probe("host")
    }.platform(.iOS)

    /// The same with `safeAreaRegions` empty: the content ignores the bar.
    public static let hostingSafeAreaNone = Fixture("ios/representable/hostingsafearea-none", size: CGSize(width: 320, height: 300)) {
        HostingNavBox(regions: []).probe("host")
    }.platform(.iOS)

    /// A hosting controller as a tab: the tab bar's safe area at the bottom.
    public static let hostingSafeAreaTabs = Fixture("ios/representable/hostingsafearea-tabs", size: CGSize(width: 320, height: 300)) {
        HostingNavBox(tabs: true).probe("host")
    }.platform(.iOS)

    /// The environment as the hosted view's trait collection: the colour scheme, the dynamic
    /// type size, the layout direction and the size classes, each drawn as bar widths.
    public static let traits = Fixture("ios/representable/traits", size: CGSize(width: 320, height: 420)) {
        VStack(alignment: .leading, spacing: 8) {
            TraitBox().probe("plain")
            TraitBox().environment(\.colorScheme, .dark).probe("dark")
            TraitBox().dynamicTypeSize(.xxxLarge).probe("xxxLarge")
            TraitBox().environment(\.layoutDirection, .rightToLeft).probe("rtl")
            TraitBox().environment(\.horizontalSizeClass, .regular).probe("regular")
        }
        .probe("stack")
    }.platform(.iOS)

    /// A table whose rows host SwiftUI through `UIHostingConfiguration`: default margins, custom
    /// margins with a background, and a minimum height.
    public static let hostingCells = Fixture("ios/representable/hostingcells", size: CGSize(width: 320, height: 300)) {
        HostingCellsTable().probe("table")
    }.platform(.iOS)
}
#else
/// The representable fixtures need UIKit: none on a plain macOS build of the harness.
public enum RepresentableFixtures {
    public static let all: [Fixture] = []
}
#endif
