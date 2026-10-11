# Slider

Apple docs: [Slider](https://developer.apple.com/documentation/swiftui/slider).

## API surface

| API | Notes |
|---|---|
| `Slider(value:in:onEditingChanged:)`, `Slider(value:in:step:onEditingChanged:)` | implemented (`V: BinaryFloatingPoint`) |
| `Slider(value:in:label:…)`, `Slider(value:in:step:label:…)` | implemented; on macOS the label is shown before the track |
| `Slider(value:in:label:minimumValueLabel:maximumValueLabel:…)` and the stepped form | implemented |
| `onEditingChanged` | implemented: `true` when a press starts, `false` when it ends |
| `labelsHidden()`, `disabled(_:)` | implemented |
| Knob shadow | implemented (2026-10-11): a blurred shadow, black 25/255, radius 2, 1 pt down (measured below) |
| `sliderStyle`, tick labels, vertical sliders | not SwiftUI API: SwiftUI has no `sliderStyle`, tick labels or vertical sliders on any platform (those are `NSSlider`/`UISlider` features); nothing to implement |
| Keyboard control | missing |

## Behaviour

`Slider` is a composite: its body reads the value (so observation tracks it) and lays the label
(`_ControlLabel`, body font), the footnote value labels and the `_SliderTrack` primitive out in an
`HStack` with 8 pt spacing; each child is `_pixelAligned`, which snaps its origin to the 2 ×
pixel grid (halves up) as the AppKit-backed control rows do. `SliderTrackNode` is a flexible
16 pt leaf: it paints the track, the filled part up to the knob, the ticks and the knob from the
live binding value, and on `pressBegan(at:)`/`pressMoved(to:)` (new on `_Interactive`, forwarded
by `Runtime.pointerDown/pointerMoved`) sets the value for the pointer's x, snapped to the step.
Inside a scroll view a touch that sets off sideways, or rests on the track first, stays with the
slider instead of becoming a pan (`dragAxes`, see ScrollView.md, 2026-09-05).

## Measured (macOS 26.2, `slider/basic`, `slider/steps`, 2026-09-02)

| Property | Value | Probe |
|---|---|---|
| Row | 16 pt tall, flexible width (fills 320, a `frame(width: 120)`, the rest of an `HStack`); 18.5 tall with a body label | `half`, `narrow`, `rowSlider`, `labelled` |
| Track | 5 pt tall, centred (y + 5.5), round ends, full width; black 25/255, the part before the knob 58/255 (disabled 42/255) | pixels rows 33…38 of `half` |
| Knob | a 22 × 16 white pill whose centre travels from 11 to width − 11 (148…172 at 0.5 of 320, 0…22 at 0, 298…320 at 1), with a blurred shadow (below) | pixels of `half`, `zero`, `full`, `slider/steps` |
| Ticks | 2 pt dots at y + 14, one per step from the first to the last knob position (21 for 0…100 by 5, 14.9 apart) | pixels of `stepped` |
| Label | body font, 8 pt before the track ("Volume" 45: the track starts at 53) | `labelled`, `minMax` |
| Value labels | footnote font (10 pt, 15 line) in the secondary colour, 8 pt from the track on each side; "Min" 17.5 × 15 at (53, 172) in a row at 170: 1.75 down, pixel-aligned to 2 | `min`, `max` |
| Pixel alignment | children of the row snap to the 2 × grid: the 16 pt track in an 18.5 row sits at +1.5 (not 1.25), the labels at +2 | pixels of `labelled`, `minMax`; `min` |
| Value changes | the knob follows the model; the echo text re-lays out the row | `slider/steps` steps |

## Verification (2026-09-02)

Tier A: 2 fixtures exact (`slider/steps` steps included). Tier B, frames exact in all three
browsers: Chromium ≤ 1.36 % pixels, WebKit ≤ 1.25 %, Firefox ≤ 1.38 % (`slider/basic`, the
knob shadow approximation). wasm js tests pass.

## Knob shadow (macOS 27, 2026-10-11, Phase 9 item 17)

The knob's shadow was a 1 pt ring; Apple's is a blur. Scanning an `NSHostingView` of a
`Slider(value: .constant(0.5))` over white (`cacheDisplay`, alpha printed) gives this darkening
profile below and above the knob, in 255ths per pixel at 2 ×:

| | row 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 |
|---|---|---|---|---|---|---|---|---|---|
| Apple, below the knob | 17 | 14 | 11 | 9 | 6 | 4 | 3 | 2 | 1 |
| Ours (`beginShadow`, black 25/255, σ 2, +1) | 16 | 14 | 11 | 9 | 6 | 5 | 3 | 2 | 1 |
| Apple, above the knob | 0 | 1 | 2 | 3 | 4 | 6 | | | |
| Ours | 0 | 1 | 2 | 3 | 5 | 6 | | | |

`SliderTrackNode` paints the knob inside a shadow group (`beginShadow`/`endGroup`,
`PlatformMetrics.sliderKnobShadow{Alpha,Radius,Offset}`); the disabled knob has no shadow.
Tier C `slider/basic` 1.25 %, `slider/steps` ≤ 0.90 %; Tier B Chromium ≤ 1.36 %.

`sliderStyle`, tick labels and vertical sliders were listed as missing: SwiftUI has none of them
(there is no `SliderStyle` protocol; ticks and vertical orientation are `NSSlider`/`UISlider`
features reached through representables), so the row is closed as not applicable.

## Not yet covered

The focused (accent) fill, keyboard control and `onEditingChanged` for keyboard changes, ideal
width without a proposal (100, unverified).
