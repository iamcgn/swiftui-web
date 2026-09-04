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
| `foregroundStyle(gradient)` on text, `EllipticalGradient`, `MeshGradient`, `ShapeStyle.in(_:)`, gradient `opacity`, `GraphicsContext.Shading.linearGradient` | missing (text keeps the primary colour; the canvas shading takes a colour) |

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

Tier A: `gradient/basic` exact. Tier B 1/1 in all three browsers (Chromium 0.08 %, WebKit and
Firefox 0.05 %). `GradientTests` cover the gradient geometry of fills and strokes, the Oklab
midpoint, evenly spaced colours and partial sweeps. wasm js tests pass.

## Not yet covered

Text and image foreground gradients, elliptical and mesh gradients, gradient shading in
`Canvas`, gradients in `Color.opacity`-style modifiers, the exact perceptual space Apple uses
(Oklab is within a few units, not identical).
