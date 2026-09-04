# shadow, zIndex, hidden, colour effects, blur, blendMode

Apple docs: [shadow(color:radius:x:y:)](https://developer.apple.com/documentation/swiftui/view/shadow(color:radius:x:y:)),
[zIndex(_:)](https://developer.apple.com/documentation/swiftui/view/zindex(_:)),
[hidden()](https://developer.apple.com/documentation/swiftui/view/hidden()),
[brightness(_:)](https://developer.apple.com/documentation/swiftui/view/brightness(_:)),
[contrast(_:)](https://developer.apple.com/documentation/swiftui/view/contrast(_:)),
[saturation(_:)](https://developer.apple.com/documentation/swiftui/view/saturation(_:)),
[grayscale(_:)](https://developer.apple.com/documentation/swiftui/view/grayscale(_:)),
[hueRotation(_:)](https://developer.apple.com/documentation/swiftui/view/huerotation(_:)),
[colorInvert()](https://developer.apple.com/documentation/swiftui/view/colorinvert()),
[colorMultiply(_:)](https://developer.apple.com/documentation/swiftui/view/colormultiply(_:)),
[luminanceToAlpha()](https://developer.apple.com/documentation/swiftui/view/luminancetoalpha()),
[blur(radius:opaque:)](https://developer.apple.com/documentation/swiftui/view/blur(radius:opaque:)),
[blendMode(_:)](https://developer.apple.com/documentation/swiftui/view/blendmode(_:)).

## API surface

| API | Notes |
|---|---|
| `shadow(color:radius:x:y:)` | implemented; the default colour is `Color(.sRGBLinear, white: 0, opacity: 0.33)` |
| `Color(_:red:green:blue:opacity:)`, `Color(_:white:opacity:)` with `Color.RGBColorSpace` | implemented; linear components go through the sRGB transfer function, Display P3 components are used as sRGB |
| `zIndex(_:)` | implemented (paint order and hit testing among the siblings of one container) |
| `hidden()` | implemented (layout kept; not painted, hit tested or in the semantics tree) |
| `brightness`, `contrast`, `saturation`, `grayscale`, `hueRotation`, `colorInvert`, `colorMultiply`, `luminanceToAlpha` | implemented (colour-matrix filter groups; not animated) |
| `blur(radius:opaque:)` | implemented (Gaussian, sigma = radius; `opaque` keeps the edges) |
| `blendMode(_:)` with every `BlendMode` | implemented (`plusDarker` is composited by hand in the browser) |
| `compositingGroup`, `drawingGroup`, `mask`, `position` | missing |

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

Colour effects are `ColorMatrixNode`: the target paints inside `DisplayCommand.beginFilter(.colorMatrix(m),
bounds:)` … `endGroup` (op 19), where `m` is a 4 × 5 matrix over straight-alpha sRGB components
(`ColorMatrix`, the SVG `feColorMatrix` convention: red, green, blue and alpha rows of four factors
and an offset; results clamp to 0…1). `blur` is `BlurNode` with `.beginFilter(.blur(radius:opaque:),
bounds:)`; a soft blur reports `paintsOutsideFrame`. `blendMode` is `BlendModeNode` with
`.beginBlend(mode, bounds:)` (op 20). `bounds` is the target's absolute frame: the painters filter
only that box (a soft blur pads it by three sigma), so content a child paints outside its frame is
not filtered. Identity matrices, a zero radius and `.normal` paint no group. The values are
resolved once per paint; the effects do not animate yet.

The browser painter renders the group into an offscreen canvas and, at `endGroup`, applies the
matrix to the box's `ImageData` (un-premultiplied components, rounded per channel), or blurs with
`CanvasRenderingContext2D.filter = blur(sigma·scale px)` (a JS separable Gaussian where the context
has no `filter`, currently Firefox's OffscreenCanvas); an opaque blur copies the original alpha back
over the blurred pixels, which un-premultiplication has already edge-normalised. Blend modes map to
`globalCompositeOperation` (`plusLighter` = `lighter`; `plusDarker` has no canvas operation and is
computed as max(0, source + destination − 1) over the box). The CoreGraphics painter paints filter
groups into a bitmap context covering the box in device space, runs `ColorMatrix.apply(toPremultiplied:)`
or `PixelFilters.gaussianBlur` on it and draws the image back; blend groups are transparency layers
begun with the matching `CGBlendMode`.

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

## Measured (macOS 26.2, `effects/brightness`, `effects/saturation`, `effects/color-map`, `effects/blur`, `effects/blend`, 2026-09-04)

Colour effects, blur and blend modes are CoreAnimation layer filters: the render server applies them
on screen and an offscreen `cacheDisplay` capture (the harness's) draws the layers without them. The
harness therefore captures these fixtures through SwiftUI's own rasteriser (`Fixture.rasterized()`
wraps the root in `drawingGroup()`), which draws them in gamma-encoded sRGB, reproducibly. (A
window-server capture applies the same filters in the display's colour space, so the on-screen
result of `colorInvert` on a P3 display clips differently; it is not a usable golden.)

Every filter works on the un-premultiplied components in 0…1 and clamps; results on (204, 102, 51):

| Effect | Rule | Result |
|---|---|---|
| `brightness(a)` | adds `a` to red, green and blue | 0.2 → (255, 153, 102); −0.3 → (127, 25, 0) |
| `contrast(a)` | `(c − 0.5) · a + 0.5` | 0.5 → (166, 115, 89); 1.5 → (242, 89, 13); 2 → (255, 76, 0) |
| `saturation(a)` | the SVG `saturate` matrix with luminance weights 0.2126 / 0.7152 / 0.0722 | 0.5 → (162, 111, 85); 2 → (255, 84, 0) |
| `grayscale(a)` | `saturation(1 − a)` | 1 → (120, 120, 120); 0.5 → (162, 111, 85) |
| `hueRotation(θ)` | the SVG `hueRotate` matrix | 90° → (51, 149, 36); 200° → (65, 127, 213) |
| `colorInvert()` | `1 − c` | (51, 153, 204) |
| `colorMultiply(k)` | multiplies red, green, blue and alpha by `k`'s | (0, 0.5, 1) → (0, 51, 51); white at 0.5 → alpha halves, colours unchanged |
| `luminanceToAlpha()` | black with alpha = luminance of the un-premultiplied colour; the content's own alpha is replaced, not multiplied | (0, 0, 0, α 120) for both the opaque and the half-transparent swatch |
| chained | each effect filters the previous result, clamped between steps | `saturation(0).brightness(0.2).colorInvert()` → (84, 84, 84) |

Two harness artefacts: the rasteriser treats a lone `saturation(0)` and `contrast(0)` as identity
(both work when chained, and the window server applies them), so the fixtures use 0.25 and 2
instead; SwiftUIWeb applies the mathematical result. Exact halves round down in Apple's pixels
(0.5 → 127), SwiftUIWeb rounds to nearest; the unit tests allow one step.

`blur(radius:)`: a Gaussian whose sigma is the radius in points, spreading outside the frame (half
coverage at the edge, 16 % one radius out, nothing beyond three). `blur(radius:opaque: true)` keeps
the content's alpha (hard edges) and blurs the colours inside as if the outside were more of the
content: a uniform swatch stays uniform to its edge (an edge-normalised kernel). `blur(radius: 0)`
paints plainly. Frames are the layout without blur.

`blendMode`: the PDF / W3C compositing formulas on gamma-encoded sRGB, including the non-separable
`hue`/`saturation`/`color`/`luminosity` and the Porter–Duff `sourceAtop`/`destinationOver`/
`destinationOut`; `plusLighter` adds premultiplied components (clamped), `plusDarker` is
max(0, source + destination − 1). `softLight` is the Pegtop formula `(1 − 2s)·b² + 2s·b` for every
`s` (the W3C one differs for `s > 0.5`: 75 vs 89 on the fixture's red channel); CoreGraphics agrees
with Apple, the canvas `soft-light` follows W3C and lands within Tier B's tolerance.

## Verification (2026-09-04)

Tier A: 11 fixtures exact. Tier C: every effects fixture within tolerance; `effects/brightness`,
`effects/saturation`, `effects/color-map` and `effects/blend` pixel-identical (0.00 %),
`effects/blur` 0.28 %, `effects/color-text` 0.77 % (text antialiasing). Tier C now paints onto a
transparent bitmap and composites over white afterwards, like the goldens, so `destinationOut`
punches through as Apple's does. Tier B: Chromium and WebKit 11/11 (blend, brightness,
saturation and color-map 0.00 %; blur ≤ 1.1 %); Firefox 9/11, the two being the known 0.25 pt
glyph-hinting shifts ("Gray", "Above"). `EffectsTests` cover the shadow command, its encoding,
the colour spaces, z-ordering with ties and hit testing, hidden views, every colour matrix against
the measured pixels, the filter and blend groups (identity cases, chaining, layout untouched),
their encoding and the Gaussian blur.

## Not yet covered

`mask`, `compositingGroup`/`drawingGroup`, `position`, animated effect values, a Canvas context's
`blendMode`, filtering of content painted outside its frame, and shadows of views inside a
transformed or clipped ancestor (the group is composited in the ancestor's space, as Apple does;
the clip then also clips the shadow).
