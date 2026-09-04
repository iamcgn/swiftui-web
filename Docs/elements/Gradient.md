# Gradient, LinearGradient, RadialGradient, AngularGradient

Apple docs: [Gradient](https://developer.apple.com/documentation/swiftui/gradient),
[LinearGradient](https://developer.apple.com/documentation/swiftui/lineargradient),
[RadialGradient](https://developer.apple.com/documentation/swiftui/radialgradient),
[AngularGradient](https://developer.apple.com/documentation/swiftui/angulargradient).

## API surface

| API | Notes |
|---|---|
| `Gradient(colors:)`, `Gradient(stops:)`, `Gradient.Stop` | implemented |
| `LinearGradient(gradient:/colors:/stops:, startPoint:endPoint:)`, `RadialGradient(…, center:startRadius:endRadius:)`, `AngularGradient(…, center:startAngle:endAngle:)`, `AngularGradient(…, center:angle:)` | implemented; `.linearGradient/.radialGradient/.angularGradient/.conicGradient` shorthands too |
| Gradients as fills, strokes, `strokeBorder` and `background(_:)` of shapes | implemented |
| `foregroundStyle(gradient)` on text | implemented 2026-09-04: the text's runs without a colour of their own draw through `drawTextGradient` (op 17: the painter draws the text into an offscreen the size of its ink and fills the gradient through it with `source-in`); the gradient spans the text's frame |
| `GraphicsContext.Shading.linearGradient/radialGradient/conicGradient/style(_:)`, `GradientOptions` | implemented 2026-09-04: points and radii follow the context's transform, a gradient style resolves against the path's bounds; options accepted, no repeat/mirror |
| `HierarchicalShapeStyle` (`.primary` … `.quinary`) in `foregroundStyle` | implemented 2026-09-04: `.primary` keeps the inherited style (a red text stays red under `.primary`, `gradient/text` `hierarchical`), lower levels fade the inherited colour to 50/35/25/18 % (approximate) |
| `EllipticalGradient`, `MeshGradient`, `ShapeStyle.in(_:)`, gradient `opacity`, gradients on images and symbols, fading a gradient with `.secondary` | missing |

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

## Not yet covered

Image and symbol foreground gradients, elliptical and mesh gradients, repeating/mirrored
canvas gradients, gradients in `Color.opacity`-style modifiers, the exact perceptual space Apple uses
(Oklab is within a few units, not identical).
