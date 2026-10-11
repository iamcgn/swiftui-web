# Gradient, LinearGradient, RadialGradient, AngularGradient, EllipticalGradient, MeshGradient

Apple docs: [Gradient](https://developer.apple.com/documentation/swiftui/gradient),
[LinearGradient](https://developer.apple.com/documentation/swiftui/lineargradient),
[RadialGradient](https://developer.apple.com/documentation/swiftui/radialgradient),
[AngularGradient](https://developer.apple.com/documentation/swiftui/angulargradient),
[EllipticalGradient](https://developer.apple.com/documentation/swiftui/ellipticalgradient),
[MeshGradient](https://developer.apple.com/documentation/swiftui/meshgradient).

## API surface

| API | Notes |
|---|---|
| `Gradient(colors:)`, `Gradient(stops:)`, `Gradient.Stop` | implemented |
| `LinearGradient(gradient:/colors:/stops:, startPoint:endPoint:)`, `RadialGradient(…, center:startRadius:endRadius:)`, `AngularGradient(…, center:startAngle:endAngle:)`, `AngularGradient(…, center:angle:)` | implemented; `.linearGradient/.radialGradient/.angularGradient/.conicGradient` shorthands too |
| Gradients as fills, strokes, `strokeBorder` and `background(_:)` of shapes | implemented |
| `foregroundStyle(gradient)` on text | implemented 2026-09-04: the text's runs without a colour of their own draw through `drawTextGradient` (op 17: the painter draws the text into an offscreen the size of its ink and fills the gradient through it with `source-in`); the gradient spans the text's frame |
| `GraphicsContext.Shading.linearGradient/radialGradient/conicGradient/style(_:)`, `GradientOptions` | implemented 2026-09-04: points and radii follow the context's transform, a gradient style resolves against the path's bounds; options accepted, no repeat/mirror |
| `HierarchicalShapeStyle` (`.primary` … `.quinary`) in `foregroundStyle` | implemented 2026-09-04: `.primary` keeps the inherited style (a red text stays red under `.primary`, `gradient/text` `hierarchical`), lower levels fade the inherited colour to 50/35/25/18 % (approximate) |
| `EllipticalGradient(gradient:/colors:/stops:, center:startRadiusFraction:endRadiusFraction:)`, `.ellipticalGradient` shorthands | implemented 2026-10-11: the radii are fractions of the bounds' width and height (display kind `elliptical`: a radial gradient in a space squashed about the centre; Canvas2D strokes and text take the circle of the horizontal radius) |
| `MeshGradient(width:height:points:/bezierPoints:/locations:, colors:, background:smoothsColors:colorSpace:)`, `MeshGradient.BezierPoint`, `.Locations`, `.Colors`, `Gradient.ColorSpace` (`.device`, `.perceptual`) | implemented 2026-10-11: rasterised at the paint scale (`MeshRasterizer`) and drawn as a bitmap inside the shape's clip (display op `drawBitmap`); Bézier points use their positions (control points derived); not animatable yet; in text it falls back to a linear gradient of the first row |
| `ShapeStyle.in(_:)`, `ShapeStyle.opacity(_:)`, `.secondary` … `.quinary` on a gradient, `AnyShapeStyle` | implemented 2026-10-11 (`_ModifiedGradientStyle`): `in` resolves the gradient against the rect in the view's space, the others multiply the stops' alpha (0.5 / 0.25 / 0.18 / 0.18, measured) |
| Gradients on symbols and template images | implemented 2026-10-11: a symbol's paths fill and stroke with the foreground gradient over its frame; a template image's `ImageDraw.tintGradient` fills its alpha through the gradient (painters: Canvas2D `source-in`, CoreGraphics transparency layer) |
| `GradientOptions.repeat` / `.mirror` / `.linearColor` on Canvas shadings | accepted, no effect |

## Behaviour

A gradient style conforms to `_GradientStyle` and resolves, for the shape's absolute bounds, to
a `DisplayGradient` (linear start/end points, radial centre and radii, angular centre and start
angle, plus stops). The shape paint paths (`_ShapeView`, `FillShapeView`, `StrokeShapeView`,
`StrokeBorderShapeView`) check for a gradient style before resolving a colour and emit
`fillGradient`/`strokeGradient` (display ops 15 and 16), which Canvas2D paints with
`createLinearGradient`, `createRadialGradient` and `createConicGradient` (whose start angle and
clockwise direction match SwiftUI's angular gradient: red at the trailing edge, then down).

Blending: Apple's pixels put the midpoint of a red → blue gradient at (170, 121, 168); sRGB
blending gives (128, 96, 158) and Oklab (172, 121, 168), so `Gradient.resolvedStops` expands
every pair of stops into eight sub-stops interpolated in Oklab (`_Oklab`, with series
`_log`/`_pow`/`_cbrt` on wasm) that the painter joins with short sRGB segments. A partial angular
sweep compresses its stops into the sweep and holds the end colour to a full turn.

## Measured (macOS 26.2, `gradient/basic`, 2026-09-03)

| Property | Value | Probe |
|---|---|---|
| Layout | gradients do not affect frames (the shapes keep their frames) | all probes |
| Blend space | Oklab: red → blue samples at 0.075…0.925 within a few units of Apple's (sRGB blending was 3.2 % of pixels off) | pixels of `linear` |
| Angular start | at the trailing edge, clockwise (red right, yellow bottom, green left, blue top) | pixels of `angular` |
| Stops | a 0/0.25/1 yellow–green–black gradient keeps its knee at a quarter | pixels of `stops` |

## Verification (2026-09-03)

Tier A: `gradient/basic` and `gradient/text` exact. Tier B 2/2 in all three browsers (`basic` ≤ 0.08 %;
`text` 0.63 % Chromium, 0.01 % WebKit, 0.54 % Firefox: the text's own anti-aliasing under the gradient). `GradientTests` cover the gradient geometry of fills and strokes, the Oklab
midpoint, evenly spaced colours and partial sweeps. wasm js tests pass.

## Corners (sw-gradients, macOS 26.6, 2026-10-11)

Measured on `NSHostingView` renders and pinned by `gradient/corners`:

| Property | Value |
|---|---|
| `EllipticalGradient` radii | `endRadiusFraction` 0.5 touches all four edges of a 200 × 100 box (rx = 100, ry = 50); `startRadiusFraction` 0.25 holds the first colour to x 50…150; the blend is perceptual like the other gradients (the midpoint matches the linear gradient's) |
| `MeshGradient` colours | blended in device sRGB by default: a 2 × 2 red / blue / yellow / green mesh is (153, 128, 75) at the diagonal's midpoint, (127, 97, 157) along the top edge; `.perceptual` blends in Oklab |
| `MeshGradient` shape | a 3 × 3 mesh with its centre point at (0.8, 0.3) bends the colour boundaries smoothly (bicubic Hermite patches with Catmull-Rom tangents from the neighbouring points, zero twist; colours bicubic when `smoothsColors`, bilinear otherwise): Tier C 0.83 %, Tier B 0.84 % against SwiftUI's render |
| `gradient.opacity(0.5)` | every stop at alpha 0.5 |
| `gradient.secondary` / `.tertiary` / `.quaternary` / `.quinary` | alpha 0.5 / 0.25 / 0.18 / 0.18; `.secondary.opacity(0.5)` is 0.25 |
| `gradient.in(CGRect(x: 50, y: 0, width: 100, height: 20))` in a 200 wide view | the first colour to x 50, the last from x 150: the rect is the gradient's frame, in the view's coordinates |
| `foregroundStyle(gradient)` on `Image(systemName:)` and a template image | the gradient spans the image's frame (the midpoint colour at the frame's centre) |

The mesh raster: each cell is split into two-pixel steps, the surface and colours evaluated on
the lattice, every small quad drawn as two Gouraud triangles into a straight-alpha RGBA bitmap
of the shape's bounds at the paint scale; the bitmap crosses to the Canvas2D painter as a
`Uint8ClampedArray` side table (`ImageData` → `OffscreenCanvas` → `drawImage`, so clips and
transforms apply) and to CoreGraphics as a `CGImage`. The last eight rasters are cached by
their description, size and scale.

## Not yet covered

Animating a mesh's points or colours, Bézier control points on mesh vertices (positions only),
mesh gradients in text (a linear fallback), elliptical gradients on Canvas2D strokes and text
(the horizontal circle), repeating/mirrored canvas gradients, the exact perceptual space Apple
uses (Oklab is within a few units, not identical).
