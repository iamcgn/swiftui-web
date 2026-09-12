// The hosted UIKit tree behind a representable's node, and the sizing rule SwiftUI applies to a
// UIKit view that does not size itself (Docs/elements/Representable.md).
import SwiftUIWebCore
import UIKitWebCore

/// A `UIKitHostedTree` as the node's `_PlatformViewTree`: the scene's services follow the
/// runtime's, and the calls forward one to one.
@MainActor
final class RepresentableTree: _PlatformViewTree {
    let hosted = UIKitHostedTree()
    var onNeedsFrame: (@MainActor () -> Void)? {
        didSet { hosted.onNeedsFrame = onNeedsFrame }
    }
    var onFocusedTextFieldChange: (@MainActor (Int?) -> Void)? {
        didSet { hosted.onFocusedTextFieldChange = onFocusedTextFieldChange }
    }
    /// The representable's `dismantle` step.
    var dismantleContent: (@MainActor () -> Void)?

    /// The scene measures with the runtime's engine and reads the runtime's catalog.
    func prepare(textEngine: any TextEngine, assetCatalog: AssetCatalog) {
        let scene = UIKitScene.shared
        if let current = scene.textEngine as AnyObject?, let engine = textEngine as AnyObject?, current === engine {
            // Already installed.
        } else {
            scene.textEngine = textEngine
        }
        if scene.assetCatalog != assetCatalog { scene.assetCatalog = assetCatalog }
    }

    /// The environment becomes the tree's traits (ios/representable/traits: the colour scheme
    /// is the appearance, the dynamic type size the content size category, the layout direction
    /// and the size classes theirs) and the safe area its window's insets.
    func layout(size: CGSize, safeAreaInsets: EdgeInsets, environment: EnvironmentValues) {
        var traits = UITraitOverrides()
        traits.userInterfaceStyle = environment.colorScheme == .dark ? .dark : .light
        traits.preferredContentSizeCategory = Self.contentSizeCategory(for: environment.dynamicTypeSize)
        traits.layoutDirection = environment.layoutDirection == .rightToLeft ? .rightToLeft : .leftToRight
        traits.horizontalSizeClass = environment.horizontalSizeClass.map { $0 == .compact ? .compact : .regular }
        traits.verticalSizeClass = environment.verticalSizeClass.map { $0 == .compact ? .compact : .regular }
        hosted.traitOverrides = traits
        hosted.safeAreaInsets = UIEdgeInsets(top: safeAreaInsets.top, left: safeAreaInsets.leading, bottom: safeAreaInsets.bottom, right: safeAreaInsets.trailing)
        hosted.layout(size: size)
    }

    static func contentSizeCategory(for size: DynamicTypeSize) -> UIContentSizeCategory {
        switch size {
        case .xSmall: return .extraSmall
        case .small: return .small
        case .medium: return .medium
        case .large: return .large
        case .xLarge: return .extraLarge
        case .xxLarge: return .extraExtraLarge
        case .xxxLarge: return .extraExtraExtraLarge
        case .accessibility1: return .accessibilityMedium
        case .accessibility2: return .accessibilityLarge
        case .accessibility3: return .accessibilityExtraLarge
        case .accessibility4: return .accessibilityExtraExtraLarge
        case .accessibility5: return .accessibilityExtraExtraExtraLarge
        }
    }

    func baselines(in size: CGSize) -> (first: CGFloat, last: CGFloat) { hosted.baselines(in: size) }

    func paint(into list: inout DisplayList, context: PaintContext) { hosted.paint(into: &list, context: context) }
    func advanceFrame(elapsed: Double) -> Bool { hosted.advanceFrame(elapsed: elapsed) }

    func pointerDown(at point: CGPoint, type: PointerType, time: Double) { hosted.pointerDown(at: point, type: type, time: time) }
    func pointerMoved(to point: CGPoint, time: Double) { hosted.pointerMoved(to: point, time: time) }
    func pointerUp(at point: CGPoint, time: Double) { hosted.pointerUp(at: point, time: time) }
    func pointerCancelled(at point: CGPoint, time: Double) { hosted.pointerCancelled(at: point, time: time) }
    func dragAxes(at point: CGPoint) -> Axis.Set {
        let axes = hosted.scrollAxes(at: point)
        var set = Axis.Set()
        if axes.horizontal { set.insert(.horizontal) }
        if axes.vertical { set.insert(.vertical) }
        return set
    }
    func scrollWheel(by delta: CGSize, at point: CGPoint) -> Bool { hosted.scrollWheel(by: delta, at: point) }

    func semantics() -> [SemanticsNode] { hosted.semantics() }
    func contains(semanticsIdentifier: Int) -> Bool { hosted.contains(semanticsIdentifier: semanticsIdentifier) }
    func activate(semanticsIdentifier: Int) { hosted.activate(semanticsIdentifier: semanticsIdentifier) }
    func adjust(semanticsIdentifier: Int, increment: Bool) { hosted.adjust(semanticsIdentifier: semanticsIdentifier, increment: increment) }
    func setValue(semanticsIdentifier: Int, value: Double) { hosted.setValue(semanticsIdentifier: semanticsIdentifier, value: value) }
    func focus(semanticsIdentifier: Int) { hosted.focus(semanticsIdentifier: semanticsIdentifier) }
    func blur(semanticsIdentifier: Int) { hosted.blur(semanticsIdentifier: semanticsIdentifier) }
    var focusedTextFieldIdentifier: Int? { hosted.focusedTextFieldIdentifier }
    func resignFocus() { hosted.resignFocus() }
    func textField(_ semanticsIdentifier: Int, didChange text: String) { hosted.textField(semanticsIdentifier, didChange: text) }
    func textFieldDidSubmit(_ semanticsIdentifier: Int) { hosted.textFieldDidSubmit(semanticsIdentifier) }
    func textField(_ semanticsIdentifier: Int, focused: Bool) { hosted.textField(semanticsIdentifier, focused: focused) }

    func dismantle() {
        dismantleContent?()
        dismantleContent = nil
        hosted.dismantle()
    }
}

/// How SwiftUI sizes a representable whose `sizeThatFits` returns nil, measured on the iPhone
/// simulator (`ios/representable/label`, `priorities`, `controls`, `controller`;
/// Docs/elements/Representable.md). Per axis: with nothing proposed the view is its intrinsic
/// size (zero without one); a proposal larger than the intrinsic size is kept unless the
/// content hugging priority is at least `.defaultHigh`; a smaller one is kept unless the
/// compression resistance is at least `.defaultHigh`; a view without an intrinsic metric takes
/// the proposal. A view controller's view without an intrinsic size falls back to the
/// controller's `preferredContentSize`.
@MainActor
enum RepresentableSizing {
    /// The priority from which the intrinsic size beats the proposal.
    static let threshold = UILayoutPriority.defaultHigh

    static func size(for proposal: ProposedViewSize, of view: UIView, fallback: CGSize = .zero) -> CGSize {
        // Layout works on the alignment rect: the intrinsic size less the alignment insets.
        let insets = view.alignmentRectInsets
        var intrinsic = view.intrinsicContentSize
        if intrinsic.width >= 0 { intrinsic.width -= insets.left + insets.right }
        if intrinsic.height >= 0 { intrinsic.height -= insets.top + insets.bottom }
        func axis(_ proposed: CGFloat?, intrinsic: CGFloat, fallback: CGFloat, hugging: UILayoutPriority, resistance: UILayoutPriority) -> CGFloat {
            let natural: CGFloat? = intrinsic >= 0 ? intrinsic : (fallback > 0 ? fallback : nil)
            // Nothing proposed: the intrinsic size, or nothing.
            guard let proposed else { return natural ?? 0 }
            // No intrinsic size: the proposal, infinite included (a flexible view, like Color).
            guard let natural else { return proposed }
            if proposed > natural, hugging >= threshold { return natural }
            if proposed < natural, resistance >= threshold { return natural }
            return proposed
        }
        return CGSize(width: axis(proposal.width, intrinsic: intrinsic.width, fallback: fallback.width,
                                  hugging: view.contentHuggingPriority(for: .horizontal), resistance: view.contentCompressionResistancePriority(for: .horizontal)),
                      height: axis(proposal.height, intrinsic: intrinsic.height, fallback: fallback.height,
                                   hugging: view.contentHuggingPriority(for: .vertical), resistance: view.contentCompressionResistancePriority(for: .vertical)))
    }

    static func size(for proposal: ProposedViewSize, of controller: UIViewController) -> CGSize {
        size(for: proposal, of: controller.view, fallback: controller.preferredContentSize)
    }
}
