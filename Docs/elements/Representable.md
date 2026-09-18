# UIViewRepresentable, UIViewControllerRepresentable and UIHostingController

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
- `static func _layoutOptions(_:) -> _PlatformViewRepresentableLayoutOptions` on both, the
  default `[.propagatesSafeArea]` (SwiftUI's SPI, as on iOS 17).
- `Color(uiColor:)` (and `Color(_ uiColor:)`), `Image(uiImage:)`, `Font(_ uiFont:)`.
  `Image(uiImage:)` of an image an image context drew (`UIGraphicsImageRenderer`,
  2026-09-18, `ios/representable/renderedimage`) shows the recording at its size, scaled when
  resizable, and its silhouette in the foreground colour as a template (UIKit's
  `withRenderingMode(.alwaysTemplate)` or SwiftUI's `renderingMode(.template)`); a tint set
  with `withTintColor` alone keeps the drawing's colours, as measured. `UIImage.pngData()`
  rasterises the recording through the host (`ImageRasterizer`: a canvas of its own in the
  browser, the CoreGraphics painter natively; nil headless and for catalog images and symbols).
- `import SwiftUI` re-exports `UIKit` (UIKitWeb's) on every platform, as Apple's does on iOS, so
  a file that names `UIColor` or declares a representable compiles unchanged. The `SwiftUI`
  module depends on `SwiftUIWebUIKit`, which depends on `SwiftUIWebCore` and `UIKitWebCore`.

## UIHostingController

`Sources/SwiftUIWebUIKit/UIHostingController.swift`: `init(rootView:)`, `rootView` (setting it
re-mounts), `sizeThatFits(in:)`, `sizingOptions` (`preferredContentSize` sets the controller's
preferred size from the ideal size), `safeAreaRegions` (with `.container` the view's safe area,
a navigation or tab bar's, is the content's: `Runtime.safeAreaInsets`; see below). The controller's view is a
`_UIHostingView` running its own `Runtime` in the iOS profile on a `systemBackground` ground:
`layoutSubviews` lays the runtime out in the bounds, `sizeThatFits` proposes the size (a fitting
size or nothing counts as unspecified, so the intrinsic size is the content's ideal size),
painting appends the runtime's display list at the view's origin, UIKit touches become the
runtime's pointer, and the runtime's semantics tree joins the scene's through UIKitWeb's
hosting SPI (`UIView._hosted*`: paint, semantics, routing by identifier, focus, text input,
the frame clock, wheel scrolling). The scene registers hosting views so it can advance their
clocks and route the identifiers they own. Tests: `UIHostingControllerTests`.

In containers (2026-09-18, `ios/representable/hostingnav`, `hostingsizing`): the content's
`navigationTitle` and `toolbar` drive the controller's `navigationItem` as SwiftUI bridges them
for a hosting controller in a navigation controller: the title, and one titled bar button per
toolbar item (leading placements on the left, the rest on the right, a `Button("Save")` as a
"Save" platter), whose tap runs the SwiftUI action (each item keeps a runtime of its own that
answers through its semantics). `sizingOptions`: `.preferredContentSize` keeps the controller's
preferred size at the content's ideal size as the content changes, `.intrinsicContentSize`
invalidates the view's intrinsic size, so a stack view around it re-lays out; setting `rootView`
inside `withAnimation` tweens the change. A hosting view measured by UIKit before its layout
(`systemLayoutSizeFitting` of a stack holding it) flushes its pending changes and still lays out
on the next pass (`Runtime.flushForMeasurement`).

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
SwiftUI measures a representable again only when its value (member by member: `Equatable`
members by `==`, class references by identity), its environment or the proposal changes, not
when the platform view's own content does: `ios/representable/hostingsizing` grows a hosted
view inside a stack view and the representable keeps its 70 pt frame while the stack compresses
the hosting view (the content, 80 tall, centred and overflowing it); `_PlatformViewHostNode`
keeps the measured sizes until then (`RepresentableTests`).

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
`uikit/controls/intrinsic`), the label baseline at other sizes, hover.

Wheel scrolling (2026-09-18, `ios/representable/wheel`, `Playwright/wheel-probe.mjs`): a wheel
over a `UIScrollView` in a representable moves that scroll view by the delta (its stripes shift
by the 100 pt wheeled) while the SwiftUI scroll view around it holds; once the inner one is at
its end the outer takes the rest (`Runtime.scrollWheel` asks the hosted tree first and falls
through to the SwiftUI scroll views when nothing inside moved). The golden is the rest state;
the probe runs against the served gallery (`node wheel-probe.mjs http://127.0.0.1:8767/index.html`).

## Safe areas through the seam (2026-09-12, `ios/representable/safearea*`, `hostingsafearea*`)

Measured under an inline navigation bar (64 pt) on the SE simulator, pixels of a view that
paints its `safeAreaInsets` (`SafeAreaView`: blue, green over the safe area):

- A representable is laid out like any view, inside the safe area: under the bar its frame
  starts at 64 (116.5 under a large title) and the UIKit view sees zero insets (`safearea`,
  `safearea-large`). Under a `safeAreaInset(edge: .bottom)` it is shrunk like plain content
  (64 to 252 for a 40 pt inset with the 8 pt spacing) and sees no inset (`safearea-inset`).
- With `ignoresSafeArea()` the UIKit view is laid out under the bar (0 to 300) and sees the bar
  as its top inset, 64: that is `propagatesSafeArea`, the default `_layoutOptions`
  (`safearea-ignored`; a `UIScrollView` there starts its content at 64 through its automatic
  content inset adjustment, `safearea-scroll-ignored`; without `ignoresSafeArea` it sits below
  the bar with its content at 64, `safearea-scroll`). The probe on the ignoring modifier still
  reports 64 to 300: the modifier's frame is the safe one and its content extends.
- The same holds for SwiftUI's own views (`safearea-color`, `safearea-rule`; Position.md has the
  rule): a colour extends under the bar when its frame touches the safe edge, through a
  `frame(width:)` or a horizontal padding, and not at all 10 pt below it.
- A `UIHostingController` under a UIKit navigation bar lays its content out below the bar
  (green from 64) while `ignoresSafeArea` content extends under it (yellow, `hostingsafearea`);
  `safeAreaRegions = []` lets the content fill the view (`hostingsafearea-none`); under a tab
  bar the content stops at the bar's top (`hostingsafearea-tabs`, approximate in the pixel
  tiers: UIKitWeb's tab bar pill is opaque where iOS 26's glass tints the yellow beneath it).

Runtime: `_PlatformViewHostNode` hands the tree `platformSafeAreaOverlap`, the part of its frame
under a bar or inset by geometry (zero unless it extended into one), and `UIKitHostedTree` makes
it the window's `safeAreaInsets`, so `safeAreaInsets`, `safeAreaLayoutGuide` and
`safeAreaInsetsDidChange` work inside as in a UIKit app. `_UIHostingView` reads its own UIKit
`safeAreaInsets` and sets `Runtime.safeAreaInsets`, which lays the root view out inside them
(an extending root, a scroll view, keeps the frame and insets its content).

## Lifecycle (2026-09-12, `ios/representable/lifecycle`)

The fixture draws the calls a representable received as bars (one per entry, the kind as a
colour and width, the coordinator's number added), copied into the view by a step after each
change, so the goldens pin the order:

- At first sight: `makeCoordinator`, `makeUIView`, `updateUIView`, in that order.
- Every evaluation of the parent's body updates the view again, whether or not the
  representable's value changed (a step that changed an unrelated property of the model logged
  another `update1`): `_PlatformViewHostNode.update` runs `updateUIView` on every update from
  its parent, and only skips when nothing above it re-evaluated.
- A new identity (`.id()`): the new coordinator, view and update come first, then the old
  view's `dismantleUIView`, with the old coordinator (`IDNode` makes the new content before it
  unmounts the old).
- Leaving the tree: `dismantleUIView` alone.

`RepresentableTests` hold the same order headless, and that the coordinator is made once per
node, outlives every update and is released with the node.

## In containers (2026-09-18, `ios/representable/list`, `form`, `scroll`)

Representables as list rows, form rows and scroll content lay out by the containers' own rules,
exact on every tier: in a plain `List` a hugging label (39 × 20.5) sits at y 52.75, a switch
(66 × 30) at 106, a plain view with a 30 pt frame at 166 (256 wide, the row's content width), a
text at 226.75 and a rounded text field (34 tall) at 282, all 32 in; in a grouped `Form` the
first card's rows match those and the second, header-less card starts 35 below the first (a
gap the runtime lacked before this fixture: `ListNodes` now adds the top inset between a row and
the next section's first row); in a vertical `ScrollView` the content is 320 wide and the
representables take their intrinsic or framed sizes, centred by the stack (`scroll`). A
representable in a sheet waits for the iOS sheet look (Docs/todo.json `sw-ios-sheets`).

## Animations across the seam (2026-09-18, `RepresentableTests`)

`context.transaction.animation` in `updateUIView` is the animation of the state change being
flushed (`withAnimation`, or the nearest `animation(_:value:)` scope), nil otherwise; the
context made for `makeUIView` carries the transaction current at that moment. A `withAnimation`
that resizes a representable tweens the node's frame as it does any view's, and the UIKit view
is laid out at every interpolated size before it paints (`_PlatformViewHostNode.paintSelf`), as
SwiftUI animates a platform view's frame. A `UIView.animate` started inside `updateUIView` runs
on the host's frame clock: `UIKitHostedTree.advanceFrame` advances the shared UIKit scene's
timers, animation groups and scroll momentum once per host frame (`_HostFrame`), however many
representables the tree holds. Headless on the runtime's clock; no fixture (the goldens are
stills).

## Traits (2026-09-12, `ios/representable/traits`, `ios/dark/representable-controls`)

The environment is the hosted tree's trait collection: `colorScheme` is `userInterfaceStyle`
(through `.environment(\.colorScheme, .dark)` too), `dynamicTypeSize` the
`preferredContentSizeCategory` (`.xxxLarge` is `extraExtraExtraLarge`), `layoutDirection` the
trait and `effectiveUserInterfaceLayoutDirection` (right to left both), `horizontalSizeClass`
and `verticalSizeClass` theirs (an iPhone: compact × regular; `.environment(\.horizontalSizeClass,
.regular)` reaches the view). Each variant drew its traits as bar widths and every one matched.
`RepresentableTree` sets them as the hosted window's `traitOverrides` (`UITraitOverrides`, new
in UIKitWeb with `UIContentSizeCategory`), so `traitCollectionDidChange` runs down the tree and
`updateUIView` runs when the environment changes (`RepresentableTests`). The dark twin of the
controls fixture renders the switch, field and button in the dark appearance (0.6 % of pixels
off). The environment values `dynamicTypeSize`, `layoutDirection` and the size classes are new
in the core; the runtime itself does not lay out by them yet (Docs/todo.json `sw-dynamic-type`,
`sw-rtl`).

## UIHostingConfiguration (2026-09-11, `ios/representable/hostingcells`; 2026-09-18, `hostingmargins`, `hostingcollection`, `hostingstate`)

`Sources/SwiftUIWebUIKit/UIHostingConfiguration.swift`. `UIHostingConfiguration { content }` as a
table or collection cell's `contentConfiguration`: the SwiftUI content is hosted by the runtime
`UIHostingController` uses, over `background(_:)` (a view or a shape style, spanning the whole
cell), inside `margins(_:_:)` / `margins(_:)`, with `minSize(width:height:)`. Measured:

- The default margins are 16 sideways and 15 above and below: a 60 pt colour makes a 90 pt
  cell; with `margins(.all, 0)` a 60 pt one, and a 20 pt colour a 56 pt one (the default
  minimum size, `minSize`'s default height); with `margins(.vertical, 30)` a 20 pt colour makes
  80 (`hostingmargins`).
- A table row adds its separator point to a hosted content's fit: 57, 61, 57 and 81 for those
  rows, 57 for a one-line text and 81 for `minSize(height: 80)` (`hostingcells`); a list content
  configuration's own fit already carries it (`uikit/table/configured`). Self-sizing collection
  list cells are exactly the fit: 56, 90 and 130 for 20, 60 and 100 pt colours
  (`hostingcollection`; a reused cell measures its new content, `Runtime.flushForMeasurement`).
- The cell's configuration state reaches the content through UIKit's own machinery, new in
  UIKitWeb: `configurationState`, `configurationUpdateHandler`, `setNeedsUpdateConfiguration`,
  `updateConfiguration(using:)` and the automatic `updated(for:)` on both cell classes, run
  before a cell's first layout and when its selection, highlight or editing changes; a content
  view that `supports` the new configuration takes it (a hosting content view re-mounts its
  root). `hostingstate` selects a row by a step: the handler rebuilds the hosted content as
  "Selected" on yellow, and back on deselection.

## Hosting inside a hosted tree (2026-09-11)

A representable's controller may host SwiftUI again with a `UIHostingController`: the inner
runtime lays out in the hosting view's bounds, its display list is concatenated at the view's
origin inside the outer list, and presses travel from the outer runtime through the
representable and the hosting view to the inner gestures (`NestedHostingTests`: a red and a blue
rectangle painted at the node, a tap on the blue one counted). No fixture: the geometry is the
outer node's and the colours the inner tree's.
