# Layout (custom layouts), AnyLayout

Apple docs: [Layout](https://developer.apple.com/documentation/swiftui/layout),
[LayoutSubview](https://developer.apple.com/documentation/swiftui/layoutsubview),
[LayoutValueKey](https://developer.apple.com/documentation/swiftui/layoutvaluekey),
[AnyLayout](https://developer.apple.com/documentation/swiftui/anylayout).

## API surface

| API | Notes |
|---|---|
| `Layout` (`sizeThatFits`, `placeSubviews`, `makeCache`/`updateCache`, `spacing`, `explicitAlignment`, `layoutProperties`), `callAsFunction` | implemented (the stacks, `_FormColumnsLayout` and the fixtures' layouts are `Layout`s) |
| `LayoutSubviews` (`RandomAccessCollection`, range and index-set subscripts, `layoutDirection`), `LayoutSubview` (`sizeThatFits`, `dimensions(in:)`, `place(at:anchor:proposal:)`, `priority`, `spacing`, `[LayoutValueKey]`) | implemented; `layoutDirection` is always left-to-right |
| `LayoutValueKey`, `layoutValue(key:value:)`, `layoutPriority(_:)` | implemented |
| `ProposedViewSize` (`.zero`, `.unspecified`, `.infinity`, `replacingUnspecifiedDimensions`), `ViewDimensions`, `ViewSpacing` (`distance(to:along:)`, `union`) | implemented |
| `AnyLayout` | implemented: a type-erased `Layout` whose cache remembers the erased type, so swapping the layout keeps the subviews and their state |
| `HStackLayout`, `VStackLayout`, `ZStackLayout` as `Layout` values | implemented |
| `Layout.Animatable` conformance (animating layout parameters), `layoutDirection` right-to-left, `GridLayout` as a `Layout` value | missing (`Grid` is the next element) |

## Behaviour

`LayoutContainerNode` hosts any `Layout`: it builds `LayoutSubviews` from the content's layout
children, keeps the layout's cache (remade when the content changes), answers `sizeThatFits`
and `dimensions` through the layout and places the subviews in `layoutContents`. `AnyLayout`
boxes the erased layout's methods in closures and stores `(cache value, erased type)`; a call
with a cache made for another type remakes it, and because the node's generic type is
`AnyLayout` throughout, switching from `HStackLayout` to `VStackLayout` updates the same node
and keeps every subview (a `@State` counter survives, `CustomLayoutTests`).

## Measured (macOS 26.2, `customlayout/flow`, `radial`, `values`, `any`, 2026-09-03)

| Property | Value | Probe |
|---|---|---|
| A layout is content-sized and centred by its parent | the 160-wide flow is 52 tall at (80, 54); the radial 160 × 160 at (40, 40); the values layout 48.5 × 70.89 centred | `flow`, `radial`, `values` |
| `sizeThatFits(.unspecified)` and `place(at:proposal:)` | rows wrap at the proposed width ("Four" starts row 2 at x = 189.5 − 80 = 109.5 … no: "Five" and the box open row 2 at y + 22), 8 pt apart, rows 6 pt apart, the box row 30 tall | `one`…`six`, `box` |
| `place(at:anchor: .center)` | the centres sit on the ring (A at the top, B right, C bottom, D left, E half-way up) | `a`, `b`, `c`, `d`, `e` |
| `priority`, layout values, `spacing.distance` | "High" (priority 1) first with its 20 pt indent, then "Low", the bar 8 pt in, "Last"; text-to-text 0 and text-to-colour distances come from the spacing preferences (70.89 tall in total) | `high`, `low`, `bar`, `last` |
| `AnyLayout` | horizontal: 106.5 × 20 row at (66.75, 50); vertical: 35.5 × 60 column at (102.25, 30); back again identical | `stack`, steps `vertical`, `horizontal` |

## Verification (2026-09-03)

Tier A: 4 fixtures exact (`customlayout/any` steps included). Tier B 6/6 renders in Chromium
(≤ 0.23 %), WebKit and Firefox. `CustomLayoutTests` cover state survival across `AnyLayout`
switches and the subview proxies' priority, layout value and spacing. wasm js tests pass.

## Corners (sw-custom-layout, macOS 26.6, `customlayout/grid-layout`, `grid/growing-spans`, 2026-10-11)

- **Animatable parameters**: a layout's `animatableData` tweens under `withAnimation` from the
  presented value to the new one, and the tree lays out again every frame of the tween
  (`LayoutContainerNode`, `_RelayoutWhileAnimating`); a change without a transaction snaps
  (`LayoutAnimationTests`). SwiftUI's own stack layouts expose no animatable data; `GridLayout`
  animates its two spacings (a `nil` spacing stays `nil`).
- **Caches**: one cache per layout node, made by `makeCache` on the first pass and kept; a new
  view value or a changed subview count runs `updateCache`; a new `AnyLayout` type remakes it
  (`LayoutAnimationTests`, `CustomLayoutTests`). SwiftUI's environment-change invalidation is not
  separately modelled: a changed environment re-applies the view, which updates the cache.
- **`GridLayout`** is the grid as a `Layout` value: `AnyLayout(GridLayout(horizontalSpacing:
  verticalSpacing:))` lays its rows out exactly as the `Grid` view does (`customlayout/grid-layout`:
  identical frames for the same rows, a lone view spanning both columns and widening them); the
  rows come from the `GridRow` each subview sits in, a subview outside any row being a row of
  its own. Both share `_GridPlanner`.
- **Rows growing past the widest earlier row, with spans** (`grid/growing-spans`): a span of two
  in row one over 30- and 20-point columns, four single cells in row two, a span of three in row
  three; the measured columns are 30 / 20 / 30 / 20 with 10 gaps, the grid 130 wide, every cell
  centred in its span — the existing algorithm matched without change.
- Right-to-left: a custom layout's placements mirror (sw-rtl, `layout/rtl-custom`).

## Not yet covered

`LayoutSubview.dimensions` for custom alignment guides in layouts other than the stacks.
