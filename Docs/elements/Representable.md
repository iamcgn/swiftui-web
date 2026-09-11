# UIViewRepresentable and UIViewControllerRepresentable

`Sources/SwiftUIWebUIKit` (decision 0014, Phase 2), over `Packages/UIKitWeb`. Fixtures
`ios/representable/*` (`Fixtures/Sources/Representable`), rendered by Apple's SwiftUI hosting
Apple's UIKit on the iPhone SE simulator (`scripts/gen-goldens-sim.sh ios ios/representable/`);
the UIKit labels' strings are measured by a real `UILabel` into `uikit/text-metrics.json`
(`Fixtures/UIKit/TextMetrics`), which Tier A merges with the iOS text metrics for these fixtures.

## API

- `UIViewRepresentable` (`Body == Never`): `UIViewType`, `Coordinator` (defaults to `Void` with a
  default `makeCoordinator`), `makeUIView(context:)`, `updateUIView(_:context:)`,
  `dismantleUIView(_:coordinator:)` (default empty), `sizeThatFits(_:uiView:context:)` (default
  nil). `UIViewRepresentableContext`: `coordinator`, `transaction`, `environment`.
- `UIViewControllerRepresentable` with the same shape over `UIViewControllerType`.
- `Color(uiColor:)` (and `Color(_ uiColor:)`), `Image(uiImage:)`, `Font(_ uiFont:)`.
- `import SwiftUI` re-exports `UIKit` (UIKitWeb's) on every platform, as Apple's does on iOS, so
  a file that names `UIColor` or declares a representable compiles unchanged. The `SwiftUI`
  module depends on `SwiftUIWebUIKit`, which depends on `SwiftUIWebCore` and `UIKitWebCore`.

## How it works

A representable is a leaf of the SwiftUI tree, `_PlatformViewHostNode`
(`SwiftUIWebCore/Runtime/PlatformViewNodes.swift`), over a `_PlatformViewTree`: the SwiftUI
side owns the slot in the layout, the frame, the memoised size, the painting position, the
press routed to it and its place in the semantics walk; the UIKit side
(`UIKitWebCore/App/UIKitHostedTree.swift`) owns what is inside. The hosted tree gives the views
a window the scene never shows, so `window`, `convert(_:to: nil)`, first responders and a
controller's appearance callbacks work as in a UIKit app. UIKit views paint into the same
display list (their `CALayer` tree at the node's origin), presses become `UITouch`es through the
same `TouchRouter` the scene uses, the tree's accessibility elements join the runtime's
semantics tree with the frames they have inside the node, and the runtime's routing by
semantics identifier (activate, adjust, text input, focus) falls through to the tree that owns
an identifier (UIKit identifiers start at 20 000 000, above every range SwiftUIWeb uses). The
scene's `setNeedsFrame` (a `setNeedsLayout` or `setNeedsDisplay` anywhere) asks the runtime for a
layout, except while the tree is laying out or painting for it. `updateUIView` runs under
observation tracking like a body: the `@Observable` properties it reads invalidate the node.

## Measured (iOS 26, iPhone SE simulator)

Sizing with `sizeThatFits` returning nil, per axis, from the view's `intrinsicContentSize` less
its `alignmentRectInsets` and its layout priorities (`ios/representable/label`, `priorities`,
`controls`, `plain`):

- Nothing proposed (`fixedSize()`): the intrinsic size; a view without one is 0 × 0 (`plain`
  `ideal`: 0 × 0; `label` `ideal`: the label's 39 × 20.5).
- A proposal larger than the intrinsic size is kept (the view fills it) unless the content
  hugging priority is at least 750 (`.defaultHigh`): `priorities` hug 252, 500 and 749 fill
  200 × 60; 750, 751 and 1000 stay 39 × 20.5, centred. UILabel's default 251 fills.
- A proposal smaller than the intrinsic size is kept unless the compression resistance is at
  least 750: resistance 250, 500 and 749 squeeze to 30 × 10; 751 and 1000 (and UILabel's default
  750) stay 39 × 20.5, overflowing the 30 × 10 container centred (x = 55.5 for a container at 60).
- A view without an intrinsic metric takes the proposal on that axis, infinite included: a plain
  `UIView` fills 200 × 60 and takes the rest of an `HStack` row next to a text (289.5 of 320).
- A wrapping label (`numberOfLines = 0`, no `preferredMaxLayoutWidth`) has a one-line intrinsic
  size: in a 120 × 100 container it keeps its 339 pt line (resistance 750) and fills the 100 pt
  height (hugging 251), centred at x = −49.5.
- A view controller's view without an intrinsic size falls back to the controller's
  `preferredContentSize` (`controller`: 80 × 40 at the ideal size, 200 × 60 when proposed).
- The representable's own `sizeThatFits` is taken as is (`sizing`: 44 × 22 centred; a size from
  `proposal.width` gets 200 in a 200 × 60 container and its own 100 under `fixedSize()`).

Controls (`ios/representable/controls`, `uikit/controls/intrinsic`):

- `UISwitch` on iOS 26 is 68 × 30 (`sizeToFit` and `intrinsicContentSize` alike) with
  `alignmentRectInsets` of 2 on the right, and hugs on both axes: SwiftUI lays it out as
  66 × 30 (in a 200 × 60 container and under `fixedSize()`) and sets the view's frame 68 wide
  from the same origin; the capsule fills the 68 × 30 frame with a 38 × 25 knob 2.5 in.
- `UITextField` (rounded rect, "Field"): intrinsic width text + 28, height 34, hugging 250 on
  both axes: it fills a 200 × 60 container. A system `UIButton` ("Tap") is 30 × 30 and fills
  too (hugging 250); under `fixedSize()` it is 30 × 30.

Alignment and spacing (`ios/representable/sizing`, `spacing`):

- A representable's `firstTextBaseline` guide is its top and `lastTextBaseline` its bottom
  (`baselineRow`: a 44 × 22 view's top meets the text's baseline; `lastRow`: its bottom does).
  A `UILabel`'s baselines are its lines': the text rect's rounded top plus the ascender rounded
  to the point (16 for the 17 pt system font's 16.43; `labelRow`, one measurement).
- In stacks a representable spaces like a plain view: 14.81 below a body text and 8.43 above one
  in a `VStack`, 8 to texts in an `HStack` (`spacing`).

Updates (`ios/representable/update`): a longer text through `updateUIView` widens a hugging
label from 39 to 90 and the stack follows; a switch turns off.

Not verified: `sizeThatFits` returning nil on one axis only (impossible: it returns a `CGSize`),
`alignmentRectInsets` on other controls (zero for labels, fields, buttons and plain views:
`uikit/controls/intrinsic`), the label baseline at other sizes, `layoutOptions`
(`_PlatformViewRepresentableLayoutOptions`), `UIHostingController` (Phase 3), wheel scrolling of
a `UIScrollView` inside a representable (routed, not measured), hover.
