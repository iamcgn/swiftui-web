# Canvas, GraphicsContext

Apple docs: [Canvas](https://developer.apple.com/documentation/swiftui/canvas),
[GraphicsContext](https://developer.apple.com/documentation/swiftui/graphicscontext).

## API surface

| API | Notes |
|---|---|
| `Canvas(opaque:colorMode:rendersAsynchronously:renderer:)`, with `symbols:` | implemented (the flags are stored; symbols are not resolvable yet) |
| `GraphicsContext.fill(_:with:style:)`, `stroke(_:with:lineWidth:)`, `stroke(_:with:style:)` | implemented |
| `draw(Text, at:anchor:)`, `draw(Text, in:)`, `resolve(Text)`, `ResolvedText.measure(in:)`/`firstBaseline(in:)` | implemented (text uses the environment's font and colour; `draw(in:)` wraps at the rect's width from its top leading corner, as Apple does) |
| `transform`, `translateBy`, `scaleBy`, `rotate(by:)`, `concatenate` | implemented (paths are transformed before recording; text rotation uses the display list's new `concat` op) |
| `opacity`, `clip(to:style:options:)`, `clipBoundingRect`, `drawLayer` | implemented (`ClipOptions.inverse` ignored; `blendMode` stored, only `.normal` painted) |
| `Shading.color`, `.foreground`, `.backgroundStyle`, `.linearGradient`, `.radialGradient`, `.conicGradient`, `.style(_:)` | implemented (gradients since 2026-09-04, `Docs/elements/Gradient.md`); `tiledImage` missing |
| `draw(Image, …)`, `resolveSymbol`, `addFilter`, `withCGContext` | missing (images draw nothing) |

## Behaviour

`CanvasNode` is a `LeafNode` sized like `Color` (fills its proposal, 10 pt when unspecified).
At paint time it creates a `_GraphicsRecorder` (its own display list, the canvas's environment
and the runtime's text engine), a `GraphicsContext` translated to the canvas's absolute origin,
runs the renderer and splices the recorded commands into the frame's list between a
`save`/`clipRect(bounds)` and a `restore`. Copies of a `GraphicsContext` share the recorder but
carry their own transform, opacity and clips: a fill or stroke applies `path.applying(transform)`
(stroke widths scaled by the transform's scale), wraps itself in `beginGroup(opacity)` when
translucent and in `save`/`clipPath`/`restore` when clipped; text lays out through the engine
like `TextNode` and is offset by a translation-only transform, otherwise drawn inside
`save`/`concat(transform)`/`restore`. `DisplayCommand.concat` (op 14) is new: Canvas2D applies
it with `ctx.transform`.

## Measured (macOS 26.2, `canvas/basic`, `canvas/sizing`, 2026-09-03)

| Property | Value | Probe |
|---|---|---|
| Sizing | a canvas is flexible: it fills the width of its stack and takes the height its stack leaves (320 × 158 under a 16 pt text with 8 pt gaps); a frame sizes it | `fill` (0, 24, 320, 158), `framed` (120, 190, 80, 50) |
| Drawing | pixels within 0.11 % (Chromium) / 0.03 % (WebKit) of Apple's for fills, an ellipse, a 3 pt stroked path, text centred at a point, text from a rect's corner, a translated and rotated square, a 50 % fill and an ellipse clip | `canvas/basic` pixels |
| Text placement | `draw(_:at:anchor: .center)` centres the text's frame on the point; `draw(_:in:)` starts at the rect's top leading corner | pixels ("Canvas" centred at 40, 80; "Corner" at 100, 70) |

## Verification (2026-09-03)

Tier A: 2 fixtures exact. Tier B 2/2 in Chromium (≤ 0.11 %) and WebKit (≤ 0.03 %); Firefox 1/2
with the failure the 0.5 pt narrower "Above" (the known hinting class), canvas pixels ≤ 0.08 %.
`CanvasTests` cover canvas-space offsets and clipping, transforms, opacity, clips, rotated text
and flexibility. wasm js tests pass.

## Not yet covered

Images, `tiledImage` shading, blend modes and filters (`addFilter`, shadows,
blur), symbols, `withCGContext`, `rendersAsynchronously`, invalidation on state read inside the
renderer (the renderer runs at every paint), `Path` text outlines.
