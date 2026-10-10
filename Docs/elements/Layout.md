# Layout core (stacks, Spacer, Divider, frame, padding, fixedSize, layoutPriority, alignment guides)

Apple docs: [Layout](https://developer.apple.com/documentation/swiftui/layout),
[HStack](https://developer.apple.com/documentation/swiftui/hstack),
[frame(minWidth:…)](https://developer.apple.com/documentation/swiftui/view/frame(minwidth:idealwidth:maxwidth:minheight:idealheight:maxheight:alignment:)),
[Spacer](https://developer.apple.com/documentation/swiftui/spacer).

## Measured constants (macOS 26.2, SwiftUI 7.2.5, goldens 2026-09-02)

| Constant | Value | Fixture |
|---|---|---|
| `.padding()` default | 16 pt on every edge | `layout/padding-default` |
| Default stack spacing (non-text neighbours) | 8 pt | `layout/spacing-default`, `layout/vstack-spacing-default` |
| `Spacer` default `minLength` | 8 pt | `layout/spacer-min-length` |
| Spacing between a `Spacer` and its neighbours | 0 (no categories in common) | `layout/spacer` |
| `Divider` thickness | 1 pt; fills the cross axis | `layout/divider` |
| `Color` ideal size (`fixedSize`) | 10 × 10 | `layout/fixed-size` |

## Confirmed behaviours

- Frames reported by `GeometryReader` are **not** pixel-rounded (`text/hello` has y = 40.75).
  Layout keeps fractional positions; rounding happens at paint time.
- Stack distribution: least flexible child first, equal share of the remainder, priority groups
  sized highest first with lower groups reserved their minimum (`layout/hstack-distribution`,
  `layout/hstack-priority`). Overflowing content is centred (`layout/spacer-min-length`).
- Spacers in the distribution (measured 2026-09-05, `pressure/stack-spacer-*`,
  `pressure/spacer-min0/min30/roomy`): a `Spacer` (also one under painting modifiers or a probe)
  is set aside with its `minLength` reserved, the other children are sized against the rest, and
  the spacers then share whatever is left; a text in a tight stack with a spacer keeps
  `floor((available − minLength) / pitch)` lines (Docs/elements/Text.md, height pressure).
- Flexible frame: with a proposal, the result is the clamped proposal when a `max` is given,
  otherwise the child size clamped by `min`; with no proposal, `ideal` wins (`layout/frame-flex`).
- Modifiers applied to a `Group` apply to every element (`layout/group-modifier`).
- Alignment guides: a stack's cross extent is the union of children aligned on the guide; the
  stack reports that guide as explicit (`layout/alignment-guide`).

## Right-to-left layout (sw-rtl, measured 2026-10-09 on macOS 26.6, `layout/rtl-*`)

`environment(\.layoutDirection, .rightToLeft)` mirrors the subtree it is set on. The clone
keeps the layout math left-to-right and mirrors every child placement inside its parent once
per level (`ViewNode.place`: `x' = parentWidth − x − width` when the parent is right-to-left);
composing the mirrors down the tree gives the measured result. The root and the presenters
(sheets, popovers, menus placed in window coordinates) do not mirror.

| Behaviour | Measured | Fixture |
|---|---|---|
| `HStack`, `Spacer` | Children run from the right; the spacer still takes the slack | `layout/rtl-stacks` |
| `VStack(alignment: .leading)`, `.frame(alignment: .leading)`, `ZStack(alignment: .topLeading)` | Leading is the right edge | `layout/rtl-stacks` |
| `.padding(.leading, 30)` | The inset is on the right | `layout/rtl-stacks` |
| `alignmentGuide(.leading) { -10 }` | Mirrored: the view sits 10 in from the right | `layout/rtl-stacks` |
| A `.leftToRight` island inside | Placed mirrored as a whole; its own children run left to right | `layout/rtl-stacks` |
| `Grid`, `gridCellColumns`, `LazyVGrid` | Columns run from the right, spans with them | `layout/rtl-grid` |
| A custom `Layout` | Its `placeSubviews` placements are mirrored by the system | `layout/rtl-custom` |
| Text, `multilineTextAlignment(.leading/.trailing)` | Leading lines sit at the right edge, trailing at the left, centre unchanged | `layout/rtl-text` |
| `Label` | The icon is right of the title | `layout/rtl-text` |
| `Shape` (default `layoutDirectionBehavior = .mirrors`) | The path is mirrored horizontally in its frame | `layout/rtl-shapes` |
| `Shape` with `.fixed` | Drawn as in left-to-right | `layout/rtl-shapes` |
| `Image(systemName:)` | Not mirrored; `flipsForRightToLeftLayoutDirection(true)` mirrors it | `layout/rtl-shapes` |
| `LinearGradient(startPoint: .leading, …)` | Not mirrored: `UnitPoint.leading` stays the left | `layout/rtl-shapes` |
| `.offset(x: 40)`, `.position(x: 30, …)` | Mirrored (the offset moves left, the position counts from the right) | `layout/rtl-shapes` |
| Horizontal `ScrollView` | Starts at its trailing end (content x = viewport − content); a leftward swipe lowers the offset | `layout/rtl-scroll`, `RTLTests` |
| `ProgressView`, `Slider`, `Toggle` | The bar fills from the right, the slider's value grows leftward, the switch sits left of its label with the on knob at the left (measured on a 26.6 golden whose control sizes differ from the modelled 26.2 ones; held by `RTLTests`) | — |

Not mirrored, as SwiftUI does not: `UnitPoint`s in gradients and anchors, `GeometryReader`
coordinates. Open: the ellipsis of a truncated right-aligned line (placed as in left-to-right,
within 2 pt), bidirectional text (the layouter has no bidi; Arabic and Hebrew strings lay out
as given), the iOS navigation chrome in a right-to-left locale.

## Not yet covered

`Layout.updateCache` reuse across passes, `GeometryReader`, text spacing categories (step 6).

## ViewThatFits (macOS 26.6, `layout/view-that-fits`, 2026-10-04)

`ViewThatFits(in:content:)` is `ViewThatFitsNode`: the content's layout children are the
candidates; each is asked its ideal size (an unspecified proposal) and the first whose size
fits the proposal on the constrained axes (both by default; an unproposed axis always fits) is
the one laid out with the proposal, painted and reporting preferences; when none fits, the
last. The fixture: a three-text `HStack` (101.5 wide) over a `Text("One")` fallback in frames
200 (the stack), 60 and 10 (the fallback, overflowing the 10); `in: .vertical` a two-text
`VStack` (32 tall) over a text in frames 60 (the stack) and 20 (the text); `in: .horizontal`
the stack in a 100 × 8 frame (the height is not consulted). Tier A exact, Tier C 0.00 %;
`ViewThatFitsTests` cover the choice following a changing frame and the axes.
