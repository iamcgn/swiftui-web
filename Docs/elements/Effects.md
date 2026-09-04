# shadow, zIndex, hidden

Apple docs: [shadow(color:radius:x:y:)](https://developer.apple.com/documentation/swiftui/view/shadow(color:radius:x:y:)),
[zIndex(_:)](https://developer.apple.com/documentation/swiftui/view/zindex(_:)),
[hidden()](https://developer.apple.com/documentation/swiftui/view/hidden()).

## API surface

| API | Notes |
|---|---|
| `shadow(color:radius:x:y:)` | implemented; the default colour is `Color(.sRGBLinear, white: 0, opacity: 0.33)` |
| `Color(_:red:green:blue:opacity:)`, `Color(_:white:opacity:)` with `Color.RGBColorSpace` | implemented; linear components go through the sRGB transfer function, Display P3 components are used as sRGB |
| `zIndex(_:)` | implemented (paint order and hit testing among the siblings of one container) |
| `hidden()` | implemented (layout kept; not painted, hit tested or in the semantics tree) |
| `blur`, `brightness`, `contrast`, `saturation`, `hueRotation`, `grayscale`, `colorInvert`, `colorMultiply`, `luminanceToAlpha`, `blendMode`, `compositingGroup`, `drawingGroup`, `mask`, `position` | missing |

## Behaviour

`shadow` is a `UnaryLayoutModifierNode` whose `paintTarget` wraps the target in
`DisplayCommand.beginShadow(color, radius:, offset:)` … `endGroup` (op 18): the painters render the
group offscreen and composite it with a shadow of its alpha. The browser painter sets
`shadowColor`/`shadowBlur`/`shadowOffset` on the compositing `drawImage`; the CoreGraphics painter
sets `setShadow` before `beginTransparencyLayer`. Both take the blur and offset in device pixels
(CoreGraphics in base space, y up), so the painter scales them by its transform. A clear shadow
colour paints the content plainly. The node reports `paintsOutsideFrame`, so scroll views never cull
a shadow whose content is just outside the viewport.

`zIndex` is the `ViewNode.zIndex` trait: `ZIndexNode` surfaces the value through every unary
modifier above it (`_UnaryLayoutModifier.zIndex(of:)`, as `layoutPriority` does) and
`ViewNode.paintOrderedChildren` stable-sorts a container's painted children by it; `hitTest` walks
that order backwards, so the front-most view takes the pointer.

`hidden` is `HiddenNode`: `hidesTargets` empties `paintedChildren` (and the proxies' when the
content is a list), which removes the target from painting, hit testing and the semantics walk
while the layout still measures and places it.

## Measured (macOS 26.2, `effects/shadow-profile`, 2026-09-04)

| Property | Value | Probe |
|---|---|---|
| Blur profile | the shadow's alpha across an edge is a Gaussian whose sigma is `radius` in points: half the colour's alpha at the edge, 16 % one radius out, nothing beyond about two radii | `blur10` (alpha 0.49 at the edge, 0.16 at 10 pt, 0 at 21 pt) |
| Offsets | `x` moves the shadow right by that many points; the hard case (`radius: 0`) is an exact copy of the alpha | `blur4`, `sharp` |
| Layout | every probe frame equals the layout without shadows | all probes |
| Vertical offsets | the harness's offscreen window draws `y` upwards (SwiftUI hands CoreGraphics a base-space offset there, unlike a layer-backed window on screen), so `effects/shadow-offset` is frames-only; the painters move the shadow down for a positive `y` as the documentation describes | `effects/shadow-offset` |

`effects/zindex`: within a `ZStack`, values 2, 0, 1, −1 paint back to front −1, 0, 1, 2 regardless of
declaration order; in an `HStack` with negative spacing the middle view with `zIndex(1)` covers both
neighbours. `effects/hidden`: hidden views keep their frames (the 80 × 30 colour and the button
still occupy their slots), and nothing of them is painted.

## Verification (2026-09-04)

Tier A: 5 fixtures exact. Tier C: `effects/shadow`, `effects/shadow-profile`, `effects/zindex`,
`effects/hidden` pixel-identical (0.00 %). `EffectsTests` cover the shadow command, its encoding,
the colour spaces, z-ordering with ties and hit testing, and hidden views in layout, painting, hit
testing and semantics.

## Not yet covered

Colour effects (`blur`, `brightness`, …), `blendMode`, `mask`, `compositingGroup`/`drawingGroup`,
`position`, and shadows of views inside a transformed or clipped ancestor (the group is composited
in the ancestor's space, as Apple does; the clip then also clips the shadow).
