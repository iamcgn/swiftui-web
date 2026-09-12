# position, safeAreaInset, safeAreaPadding, ignoresSafeArea

Apple docs: [position(x:y:)](https://developer.apple.com/documentation/swiftui/view/position(x:y:)),
[position(_:)](https://developer.apple.com/documentation/swiftui/view/position(_:)),
[safeAreaInset(edge:alignment:spacing:content:)](https://developer.apple.com/documentation/swiftui/view/safeareainset(edge:alignment:spacing:content:)-6gwby),
[safeAreaPadding(_:)](https://developer.apple.com/documentation/swiftui/view/safeareapadding(_:)-2qzs2),
[ignoresSafeArea(_:edges:)](https://developer.apple.com/documentation/swiftui/view/ignoressafearea(_:edges:)).

## API surface

| API | Notes |
|---|---|
| `position(x:y:)`, `position(_:)` | implemented |
| `safeAreaInset(edge:alignment:spacing:content:)` for vertical and horizontal edges | implemented (`HorizontalEdge` added) |
| `safeAreaPadding(_:)` (insets, edges + length, length) | implemented |
| `ignoresSafeArea(_:edges:)`, `edgesIgnoringSafeArea(_:)` | implemented (`SafeAreaRegions` added; the keyboard region does not exist in a browser) |
| `GeometryProxy.safeAreaInsets` | still zero: the created safe areas are not reported to geometry readers |

## Behaviour

`position` is `PositionNode`, a unary layout modifier: the modified view takes the proposed size
(the child's size where a dimension is unproposed) and places its child's centre at the point in
its own coordinate space. It reports `paintsOutsideFrame`, so a child moved out of the frame is
not culled by a scroll view.

A browser window has no safe area, but the safe-area modifiers create one for their content,
and a host may give the root one (`Runtime.safeAreaInsets`: a `UIHostingController` under a
navigation bar; the iOS profile's `NavigationStack` gives its screen its bar as one). The safe
area travels down by geometry, set on each node by its placer in `place(at:)` (2026-09-12,
measured on the simulator in `ios/representable/safearea-rule`, `safearea-color`):

- a node's `safeAreaOverlap` is how much of its frame lies in the unsafe region on each edge, and
  its `safeAreaExtension` how far beyond an edge that *touches* the safe boundary the unsafe
  region reaches; an edge inside the safe area gets neither (a colour padded 10 pt below a bar
  stays put; one touching the bar extends under it through a `frame(width:)` or a padding on
  the other edges);
- `SafeAreaNode` (`safeAreaInset` with an inset view, `safeAreaPadding` with fixed lengths) adds
  its insets: a plain child is measured and placed in the bounds minus the insets (with nothing
  proposed the insets add to the child's size); a child that *extends into the safe area*
  (`ViewNode.extendsIntoSafeArea`: scroll views, forwarded through wrappers that do not change
  their child's size) keeps the full bounds and its overlap is the insets. `ScrollNode` takes
  the overlap as content insets: the content starts at the top/leading inset, the scrollable
  range grows by the insets, the frame is unchanged; nested safe-area modifiers accumulate;
- `IgnoresSafeAreaNode` keeps the safe frame its parent gives it (a background or probe outside
  the modifier sees that frame) and proposes its content that frame grown by the extension on
  the ignored edges, placed in the grown rect and centred when smaller; the content gets no safe
  area on those edges (a scroll view ignoring it does not inset), while the geometry stays in
  `platformSafeAreaOverlap` for a hosted UIKit view (Representable.md).

The inset view is proposed the cross length and nothing along its edge's axis, placed at the edge
aligned by `alignment`, and paints (and is hit tested) over the content. Its length plus the
spacing (`spacing`, default 8) is the inset.

## Measured (macOS 26.2, `position/*`, 2026-09-04)

| Property | Value | Probe |
|---|---|---|
| `position` size | the full proposal: a 200 × 90 ZStack cell, the remaining 244 pt of an HStack row, the remaining 40 pt of a VStack column | `inZStack`, `inHStack`, `inVStack` |
| `position` child | centred at the point within that frame (pixels) | `position/basic` |
| `safeAreaInset(edge: .bottom)` on a VStack in a 100 × 200 box | the stack is laid out 162 pt tall: 200 − 30 (bar) − 8 (default spacing); the bar sits at the bottom | `plainContent`, `plainBar` |
| the same on a ScrollView | the scroll view stays 100 × 200 and its content (240 pt) starts at the top | `scroll`, `scrollContent` |
| `ignoresSafeArea()` under a top inset with `spacing: 0` | the content keeps 100 × 200 under the bar | `ignoringContent`, `ignoringBar` |
| `safeAreaPadding(.vertical, 20)` on a ScrollView | frame unchanged, content 20 pt lower | `paddedScroll`, `paddedScrollContent` |

## Verification (2026-09-04)

Tier A: 3 fixtures exact. Tier C: all three 0.00 %. Tier B: Chromium and WebKit 3/3 with exact
frames; Firefox 2/3 (`position/basic` carries the known 0.25 pt shift of "Above"). `PositionTests`
cover the proposal-sized frame and centring, insets on every edge with alignment and spacing, the
scroll view's content inset and scrollable range under nested insets, `safeAreaPadding`'s three
spellings, `ignoresSafeArea` (and the older spelling), the geometric rule through frames,
padding and stacks, the host's safe area, and unproposed sizes (2026-09-12: the earlier
assumption that a frame stops the safe area was refuted by `ios/representable/safearea-rule`).

## Not yet covered

`GeometryProxy.safeAreaInsets`, the keyboard region, `safeAreaInset` on a list content (the inset
is one view for the modifier, not one per element), and scroll indicators that should stop at the
inset.
