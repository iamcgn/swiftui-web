# Shape, Path, stroke, fill, border

Apple docs: [Shape](https://developer.apple.com/documentation/swiftui/shape),
[Path](https://developer.apple.com/documentation/swiftui/path),
[InsettableShape](https://developer.apple.com/documentation/swiftui/insettableshape),
[ShapeView](https://developer.apple.com/documentation/swiftui/shapeview),
[StrokeStyle](https://developer.apple.com/documentation/swiftui/strokestyle),
[RoundedRectangle](https://developer.apple.com/documentation/swiftui/roundedrectangle),
[UnevenRoundedRectangle](https://developer.apple.com/documentation/swiftui/unevenroundedrectangle),
[border(_:width:)](https://developer.apple.com/documentation/swiftui/view/border(_:width:)).

Geometry is checked against Apple's own `Path.description` output: `Fixtures/Sources/Shape/PathRequests.swift`
lists 74 paths that `scripts/gen-goldens.sh shape/` records from real SwiftUI into
`Fixtures/Goldens/shape/paths.json`, and `PathGoldenTests` compares ours element by element
(1e-3; stroked outlines by bounding box). Pixels are compared in Tier B.

## API surface

| API | Notes |
|---|---|
| `Shape` (`path(in:)`, `sizeThatFits(_:)`, `role`), `ShapeRole` | implemented; `layoutDirectionBehavior` missing |
| `Rectangle`, `RoundedRectangle(cornerRadius:style:)`, `RoundedRectangle(cornerSize:style:)`, `RoundedCornerStyle` (`.circular`, `.continuous`, the default) | implemented, paths identical to Apple's |
| `UnevenRoundedRectangle(cornerRadii:style:)`, `UnevenRoundedRectangle(topLeadingRadius:…)`, `RectangleCornerRadii` | implemented, incl. the per-corner radius limit |
| `Circle`, `Ellipse`, `Capsule(style:)` | implemented |
| `ContainerRelativeShape` | approximate: a rectangle (no container shapes) |
| `AnyShape` | implemented |
| `Path`: `init()`, `init(_ rect:)`, `init(roundedRect:cornerRadius:style:)`, `init(roundedRect:cornerSize:style:)`, `init(roundedRect:cornerRadii:style:)`, `init(ellipseIn:)`, `init(_ callback:)`, `init?(_ string:)` | implemented; `init(_ cgPath:)`, `cgPath` missing (no CoreGraphics on wasm) |
| `Path`: `move`, `addLine`, `addQuadCurve`, `addCurve`, `closeSubpath`, `addRect(_:transform:)`, `addRects`, `addLines`, `addEllipse(in:transform:)`, `addRoundedRect(in:cornerSize:style:transform:)`, `addRoundedRect(in:cornerRadii:style:transform:)`, `addArc(center:radius:startAngle:endAngle:clockwise:transform:)`, `addRelativeArc`, `addPath(_:transform:)` | implemented, element for element as Apple |
| `Path.addArc(tangent1End:tangent2End:radius:transform:)` | implemented from `CGPathAddArcToPoint`'s definition, not verified against SwiftUI |
| `Path`: `isEmpty`, `boundingRect`, `currentPoint`, `description`, `forEach`, `applying(_:)`, `offsetBy(dx:dy:)`, `contains(_:eoFill:)`, `trimmedPath(from:to:)` | implemented |
| `Path.strokedPath(_:)` | approximate: oriented polygons per segment, join and cap that a nonzero fill unions (Apple computes the offset outline); dashes honoured |
| `Path: Shape` (a `Path` is a view in local coordinates), `Path: LosslessStringConvertible` | implemented |
| `Shape.fill(_:style:)` → `FillShapeView`, `fill(style:)`, `stroke(_:style:antialiased:)` / `stroke(_:lineWidth:antialiased:)` → `StrokeShapeView`, `stroke(style:)` / `stroke(lineWidth:)` → `_StrokedShape` (a `Shape`) | implemented; `antialiased` stored, no effect (canvas always antialiases) |
| `ShapeView` chaining: `.fill`, `.stroke`, `.strokeBorder` on a shape view draw over the earlier view | implemented (`shape/stroke` `fillStroke`, `strokeFill`) |
| `StrokeStyle` (`lineWidth`, `lineCap`, `lineJoin`, `miterLimit`, `dash`, `dashPhase`), `FillStyle` (`eoFill`, `antialiased`) | implemented; `CGLineCap`/`CGLineJoin` declared on wasm |
| `InsettableShape`, `inset(by:)` on every built-in, `strokeBorder(_:style:antialiased:)`, `strokeBorder(_:lineWidth:antialiased:)`, `strokeBorder(style:)`, `strokeBorder(lineWidth:)` → `StrokeBorderShapeView` | implemented |
| `Shape.trim(from:to:)`, `offset(_:)`/`offset(x:y:)` → `OffsetShape`, `scale(_:anchor:)`/`scale(x:y:anchor:)` → `ScaledShape`, `rotation(_:anchor:)` → `RotatedShape`, `transform(_:)` → `TransformedShape`, `size(_:)`/`size(width:height:)` | implemented; `OffsetShape`/`ScaledShape`/`RotatedShape`/`TransformedShape` are `InsettableShape` when their content is |
| `Shape.union`, `intersection`, `subtracting`, `symmetricDifference`, `lineIntersection`, `lineSubtraction` (iOS 17 boolean operations) | implemented (flattened geometry, pixel-identical on `shapebool/*`) |
| `View.border(_:width:)` | implemented: an inset rectangle stroke overlaid on the content |
| `Angle` (`radians`, `degrees`, `.zero`, `Comparable`, `Animatable`) | implemented |
| `Shape.role`, `.separator` / `.stroke` roles affecting styles | stub (no effect) |

## Corner geometry (from Apple's paths, macOS 26.2, 2026-09-02)

Rounded rectangles start at the middle of the trailing edge's straight part, between the two
trailing radii (`(maxX, minY + (rTopTrailing + h − rBottomTrailing) / 2)`), and run clockwise on
screen: bottom-trailing, bottom-leading, top-leading, top-trailing, then close. Each corner is a
line to the corner's start followed by its curves. Ellipses start at `(maxX, midY)` and run the
same way. Rectangles start top-leading.

- **Limits.** `RoundedRectangle` limits both radii to half the smaller side (`cornerSize 60 × 8`
  in `100 × 60` → `30 × 8`); a zero or negative radius is a plain rectangle. `UnevenRoundedRectangle`
  limits every corner to `max(edge / 2, edge − neighbouring radius)` on each adjacent edge
  (radii `20, 90` on a 100 edge → `20, 80`; `50, 70` → `50, 50`; `40` alone in 60 → `40`) and
  emits every corner even when its radius is 0 (degenerate curves).
- **Circular.** One cubic per corner with kappa 0.5522847 (`RoundedRectangle(…, style: .circular)`,
  `Capsule(style: .circular)`, the `paint/*` fixtures).
- **Continuous** (the default). Three cubics per corner. Measured from the corner along each
  edge, in units of that axis's radius: the corner starts at 1.528665, control points 1.08849
  and 0.868407, then (0.631494, 0.0749114), (0.372824, 0.169060) → (0.169060, 0.372824) →
  (0.0749114, 0.631494), and the mirror of the first curve into the other edge. When the
  edge has no room for 1.528665 r (two corners share `edge · r / (r + rNeighbour)`), the start
  moves to that share and the two control points move linearly towards 0.96 r and 0.82 r as the
  share shrinks from 1.528665 r to r (`r = 100` in `2000 × 240`: 1.00861 r and 0.838313 r;
  `Capsule` in `30 × 80`: 0.96 r, 0.82 r). Elliptical corners scale each axis by its own radius.
- **Inset.** `RoundedRectangle`/`UnevenRoundedRectangle.inset(by:)` shrink the radii by the
  inset (12 − 5 = 7; never below 0); `Circle`, `Ellipse`, `Capsule`, `Rectangle` inset the rect.

## Arcs, trimming, strokes

- `addArc(center:radius:startAngle:endAngle:clockwise:)`: with `d = end − start`, `|d| < 1e-9`
  adds only the start point; counter-clockwise (`clockwise: false`, increasing angles, clockwise
  on screen) sweeps `d` when `d > 0` and `2π − (−d mod 2π)` when `d < 0` (`0 → −90` is 270°);
  `clockwise: true` sweeps `−d` when `d < 0` and `2π − (d mod 2π)` when `d > 0` (`0 → 45` is 315°,
  `0 → 720` one turn). Only `d ≈ +2π` closes the subpath. The sweep is emitted as full quarter
  cubics then the remainder (`kappa = 4/3 · tan(θ/4)`), preceded by a line from the current point
  (a move when the path is empty). `addRelativeArc` sweeps exactly `delta`, never closes.
- `trimmedPath(from:to:)` measures arc length over every segment including closing segments,
  clamps to 0…1, and returns an empty path when `to ≤ from`; a partially included subpath gets a
  move, a fully included closing segment stays a close (`rect 0…1`), a clipped one becomes a line
  (`rect 0…0.999` ends with `0 0.32 l`). Curves are split by parameter at the matching chord length
  (Apple's split differs by under 0.1 pt on a 100 pt circle).
- `Path(string)` parses Apple's postfix format (`x y m`, `x y l`, `cx cy x y q`, `c1 c2 x y c`,
  `h`); trailing coordinates are ignored, anything else is `nil`. `description` prints six
  significant digits like `%g`.
- Stroking: painters stroke the base path natively (`strokePath` carries the full `StrokeStyle`,
  Canvas2D `lineCap`/`lineJoin`/`miterLimit`/`setLineDash`/`lineDashOffset`); `strokeBorder`
  strokes the shape inset by half the width. `Path.strokedPath` and a `_StrokedShape` used for
  clipping or `contains` get the polygon approximation.

## Measured layout rules (macOS 26.2, `shape/*` fixtures, 2026-09-02)

| Rule | Fixture / probe |
|---|---|
| Shapes take the proposal; `Circle` the smaller dimension; the ideal size is 10 × 10 for every shape and `Path` (`fixedSize`) | `shape/layout` `c1`, `e1`, `ideal`, `circleIdeal`; `shape/modifiers` `pathIdeal` |
| In an `HStack` a circle takes its square (40) and the flexible shapes share the rest equally (110 each); a `VStack` 60 × 100 gives the circle 50 × 50 and the rectangle 60 × 50 | `shape/layout` `row1`, `vCircle`, `vRect` |
| `trim` and `stroke(style:)`/`stroke(lineWidth:)` lay out like the base shape (a trimmed or stroked circle stays square: 40 × 40 in 60 × 40) | `shape/modifiers` `trimmed`; `shape/layout` `strokedFlex`; `shape/stroke` `stroke`, `strokeShape`, `fillStroke` |
| `offset`, `scale`, `rotation`, `transform`, `size`, `inset(by:)` and `strokeBorder` take the proposal (60 × 40 for a circle) | `shape/modifiers` `scaled`, `offset`, `anchored`; `shape/stroke` `strokeBorder`; probe sweep in the session |
| `size(width:height:)` draws the base in a rect of that size at the frame's origin and changes no layout (10 × 10 ideal) | `shape/modifiers` `sized`, `sizedIdeal` |
| A `Path` view draws its coordinates from the frame's origin, unclipped (a 24 × 16 rect in a 10 × 10 frame overflows) | `shape/modifiers` `pathIdeal` |
| Strokes centre on the outline and overflow the frame; frames are unchanged | `shape/stroke` `stroke` (50 × 50) vs its pixels |
| `border` changes no frame or spacing: `Text("Hello")` stays 31 × 16, a width-8 border draws inside the text's frame, width 0 draws nothing | `shape/border` `text`, `textInner`, `thick`, `zero` |

## Verification (2026-09-02)

Tier A: 7 fixtures exact (`shape/steps` steps included); 74/74 Apple paths matched (68 element
for element, 6 stroked outlines by bounds). Tier B, all frames exact: Chromium ≤ 0.9 % pixels
(`shape/steps/thicker` 1.4 %, anti-aliasing of a 6 pt dashed stroke), WebKit ≤ 0.11 % (continuous
corners and strokes are pixel-identical to CoreGraphics), Firefox ≤ 1.2 %. The wasm build
carries its own `sin`/`cos`/`tan`/`atan2`/`acos` (`Geometry/Math.swift`): wasi-libc's trap.

## Boolean operations (2026-09-05)

`union`, `intersection`, `subtracting`, `symmetricDifference` (fills) and `lineIntersection`,
`lineSubtraction` (outlines) combine two shapes into one whose `path(in:)` is the combined
geometry, so fills, strokes, clips and hit tests all see it (`Shapes/PathBoolean.swift`). Both
paths are flattened (16 segments per curve), every edge is cut at the crossings with the other
path, each fragment is classified by whether its middle lies inside the other path (winding, or
even-odd with `eoFill`), the operation keeps the fragments it needs (a subtracted or
symmetric-difference inside fragment reversed), and the kept fragments chain into loops with
holes oriented against their containers for a non-zero fill. Input loops are oriented by
nesting depth first, so shapes drawn either way combine. The line operations cut the first
shape's outline at the crossings and keep the pieces inside (or outside) the other.

A circle against an offset square, filled and stroked, in all six operations
(`shapebool/fills`, `shapebool/strokes`) is pixel-identical to SwiftUI's in Tier B and C, and
`PathBooleanTests` checks rectangles exactly, holes, nested and disjoint shapes, curves within
1 % of the analytic areas, and the outline lengths of the line operations.

Limits: curved boundaries are polygons at 1/16 of a curve; coincident edges are kept once from
the first shape; two pieces that touch at a corner may chain into one loop.

## Not yet covered

`strokedPath` as a true offset outline, `addArc(tangent1End:…)`
verification, `ContainerRelativeShape` inside container shapes, `layoutDirectionBehavior`,
gradients and materials as shape styles, `contentShape`/hit testing on shapes, animated shape
data (`Animatable` is declared, nothing interpolates yet), `Path(cgPath:)`.
