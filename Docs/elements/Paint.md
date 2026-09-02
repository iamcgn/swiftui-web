# Painting: Color, shapes, background/overlay, opacity, clipping, display list

Apple docs: [Color](https://developer.apple.com/documentation/swiftui/color),
[Shape](https://developer.apple.com/documentation/swiftui/shape),
[background(_:alignment:)](https://developer.apple.com/documentation/swiftui/view/background(_:alignment:)),
[clipShape](https://developer.apple.com/documentation/swiftui/view/clipshape(_:style:)).

## Display list

`Runtime.render(scale:)` walks the laid-out tree and emits `DisplayCommand`s in absolute points:
`save/restore`, `clipRect/clipRRect/clipPath`, `beginGroup(opacity)/endGroup`,
`fillRect/fillRRect/fillPath/strokePath`, `drawText(line, font, baseline origin, colour)`.
Frame edges are rounded to `1/scale` independently (`PaintContext.absoluteRect`), so a view at
y = 40.75 paints at 41 at 2× while its 84.5 x stays on the half-pixel grid. Canvas and native
painters consume the same list (decision 0002); the flat `Float64` encoding for JS is step 10.

## Measured constants (macOS 26.2 light appearance, `paint/system-colors`, 2026-09-02)

| Colour | sRGB |
|---|---|
| red | 255, 56, 60 |
| orange | 255, 141, 40 |
| yellow | 255, 204, 0 |
| green | 52, 199, 89 |
| mint | 0, 200, 179 |
| teal | 0, 195, 208 |
| cyan | 0, 192, 232 |
| blue / accentColor | 0, 136, 255 |
| indigo | 97, 85, 245 |
| purple | 203, 48, 224 |
| pink | 255, 45, 85 |
| brown | 172, 127, 94 |
| gray | 142, 142, 147 |
| primary (text, shape default) | black at 85 % (216/255) |
| secondary | black at 50 % (127/255) |
| `Color(red:green:blue:)` | component × 255, rounded |
| `.opacity(x)` | multiplies alpha (`red.opacity(0.5)` → alpha 128/255) |

## Confirmed layout behaviours

- `background`/`overlay` propose the content's size to the layer and align it inside the
  content's frame; they never change the content's size (`paint/background-overlay`).
- Shapes are flexible with a 10 × 10 ideal; `Circle` takes the smaller proposed dimension
  (`paint/shapes`). `clipShape`, `cornerRadius`, `opacity` are layout-transparent (`paint/clipping`).

## Not yet covered

Gradients, materials, `shadow`, `border`, `stroke(style:)`, `InsettableShape`, dark appearance,
`blendMode`, `mask`, `ImageRenderer`-style pixel comparison (Tier B, step 13).
