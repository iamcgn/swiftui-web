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
- Flexible frame: with a proposal, the result is the clamped proposal when a `max` is given,
  otherwise the child size clamped by `min`; with no proposal, `ideal` wins (`layout/frame-flex`).
- Modifiers applied to a `Group` apply to every element (`layout/group-modifier`).
- Alignment guides: a stack's cross extent is the union of children aligned on the guide; the
  stack reports that guide as explicit (`layout/alignment-guide`).

## Not yet covered

`layoutDirection` (RTL), `Layout.updateCache` reuse across passes, `ViewThatFits`,
`GeometryReader`, text spacing categories (step 6).
