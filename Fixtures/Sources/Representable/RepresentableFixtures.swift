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
        VStack(alignment: .leading, spacing: 8) {
            VStack { SwitchBox().probe("switchLarge") }.frame(width: 200, height: 60)
            SwitchBox().fixedSize().probe("switchIdeal")
            VStack { FieldBox().probe("field") }.frame(width: 200, height: 60)
            VStack { ButtonBox().probe("button") }.frame(width: 200, height: 60)
            ButtonBox().fixedSize().probe("buttonIdeal")
        }
        .probe("stack")
    }.platform(.iOS)

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

    public static let all: [Fixture] = [plain, label, priorities, controls, sizing, spacing, controller, update]
}
#else
/// The representable fixtures need UIKit: none on a plain macOS build of the harness.
public enum RepresentableFixtures {
    public static let all: [Fixture] = []
}
#endif
