# ColorPicker

Apple docs: [ColorPicker](https://developer.apple.com/documentation/swiftui/colorpicker),
[NSColorWell](https://developer.apple.com/documentation/appkit/nscolorwell).

## API surface

| API | Notes |
|---|---|
| `ColorPicker(_:selection:supportsOpacity:)` (`LocalizedStringKey` and `StringProtocol` titles), `ColorPicker(selection:supportsOpacity:label:)` | implemented |
| `labelsHidden`, `disabled` | implemented (the hidden label leaves the bare well; disabled paints at half opacity) |
| Form rows | implemented: the label on the well's baseline in a columns form, trailing well in a grouped form |
| The panel | implemented 2026-10-11: a press asks the host for its system colour chooser (`HostedScene.colorPanelHandler`): the browser host opens its `<input type="color">` (kept under the well, opened inside the press; `input` events feed the well, `change` closes it; the input has no alpha, so the well's opacity stays), the AppKit host the shared `NSColorPanel` (continuous, `showsAlpha` from `supportsOpacity`, closing deactivates). Apple opens `NSColorPanel` straight from the well (probed on macOS 27: a 266 × 454 panel with the wheel, opacity slider and favourites). Without a host chooser (headless, a host without one) the popover of 16 preset swatches and the opacity slider stands in |
| The active well | implemented 2026-10-11: while a chooser targets the well its 3 pt frame is the keyboard-focus blue (71, 145, 248; probed) instead of the grey; a targeted drop shows the same |
| `CGColor` selection binding (`ColorPicker(_:selection: Binding<CGColor>)` ×2, `ColorPicker(selection:supportsOpacity:label:)`), `Color(cgColor:)`, `Color.cgColor` (nil for system, named and dynamic colours, as SwiftUI's) | implemented 2026-10-11 |
| Keyboard activation | implemented: Space or Return on the focused well asks for the chooser as a press does (`ColorPickerTests`, `colorpicker-probe.mjs`) |
| Drag and drop of colours | implemented 2026-10-11: `Color: Transferable` (the payload itself; the data form is the sRGB components as text under `UTType.color`); a dragged colour dropped on an enabled well becomes its selection (the opacity kept to 1 without opacity support) |
| `tint`, `controlSize` | missing |

## Behaviour

`ColorPicker` is a composite: `_FormLabeledRow` with `_ControlLabel` (the body font) and the
`_ColorWellHost` primitive (`ColorWellNode`). In a stack the label is centred on the 24 pt well at
fractional points (`_FormRowMode.centeredFractional`, 2.75 for the 18.5 pt body line); in a
columns form the label sits on the well's first text baseline, 22.5 from its top, so the row is
27 tall; a grouped form puts the well at the trailing edge. The picker never stretches: in a
wider frame the label and well stay together, centred. The well is 48 × 24: a 230-grey
(25/255 black) continuous rounded rectangle of radius 11 holding a concentric swatch inset 3 pt
(42 × 18, radius 8). The swatch shows white and, above the diagonal through its centre at
slope −½, black, then the colour with its own opacity, so translucent and clear colours show
the split; a 0.5 pt inner stroke at 10 % black and a 0.5 pt 15 % shade along the top finish it.
Disabled, every layer paints at half opacity (the grey becomes 242, red 249/149/151). The well
asks 8.15 pt on every side (rows of pickers sit 8.15 apart and a checkbox row 8.15 below one on
macOS 27; 26.2 put the checkbox 6 below). Its semantics are a button labelled "<title>, color" whose value names the colour.

## Measured (macOS 26.2, fixtures `colorpicker/*`, 2026-09-04)

| Property | Value | Probe |
|---|---|---|
| Size | "Accent" + 8 + 48 = 98.5 × 24; "Tint" 79.5; hidden label 48 × 24 | `red`, `opaque`, `hidden` |
| Label | body font centred: "Tint" 18.5 tall at y + 2.75; the picker's baseline is its label's (a sibling "Hg" aligns at +3.75 with the 16 pt system font) | `customText`, `baselineText` |
| Well | grey 230 with the corner profile of radius ≈ 11; swatch 3…45 × 3…21 with darker 0.5 pt edges (0.9 × the colour) and a 0.76 × top line | pixels of `hidden`, `baselinePicker` |
| Translucent | 50 % green (51, 153, 102): (25, 77, 51) over black up-left of the diagonal through (24, 12) at slope −½, (152, 204, 178) over white below it | pixels of `translucent` |
| Clear | black / white halves, no colour | `steps/clear` |
| Disabled | grey 242, red (249, 149, 151): each layer at 50 % | pixels of `disabled` |
| Sizing | `frame(width: 240)` centres the 98.5 pt row; a `Spacer` beside it leaves it 98.5 | `wide`, `leading`, `spaced` |
| Form | rows 27 tall (the well at the top, the label's baseline at 22.5), 8.15 apart; a checkbox row 8.15 below too (macOS 27, regenerated 2026-10-11; 26.2: 6); labels right-aligned in the label column | `form/accent`, `tint`, `toggle` |
| Model changes | the swatch repaints (red → blue → clear) | `colorpicker/steps` |

A label narrower than its text (`frame(width: 60)`) wraps Apple's label character by character
(113.5 pt tall); not reproduced, and dropped from the fixtures.

## Verification (2026-09-04)

Tier A: all 5 fixtures exact, the 2 `steps` steps included. Tier B: frames exact in Chromium
and WebKit; Firefox measures "Above" half a point wider and shifts `colorpicker/labels` by a
quarter point (the known hinting class). Pixels ≤ 0.96 % (Chromium), ≤ 0.90 % (WebKit),
≤ 0.96 % (Firefox); Tier C ≤ 0.90 %. `ColorPickerTests` cover the sizes, the painted layers and
their disabled opacity, translucent colours, form rows, semantics, and the preset panel.

## The chooser (macOS 27, probed 2026-10-11, Phase 9 item 18)

A synthesized click on the well of an `NSHostingView` opened `NSColorPanel` directly (no
popover: a 266 × 454 panel with `NSColorPickerWheelView`, the HDR and opacity sliders and the
favourites list); setting the panel's colour programmatically changed the binding at once (the
panel is continuous). While the panel targets the well, the well's 3 pt frame is painted in
the keyboard-focus blue (71, 145, 248) instead of the 25/255 grey (rows through the frame
before and after, over white: 255 → 71,145,248 for the full 3 pt; the swatch unchanged).

The runtime asks its host (`HostedScene.colorPanelHandler`, `ColorPanelRequest` with the
well's identifier, colour, opacity support and frame); the host answers `colorPanel(_:didPick:)`
while the chooser is open and `colorPanelDidClose(_:)` when it closes or another well takes it.
`Playwright/colorpicker-probe.mjs` drives the browser host: the input is created on the first
press with the well's colour (`#ff383c`) under the well, an `input` event recolours the swatch,
`change` restores the grey frame, Tab then Space activates the well again.

## Not yet covered

The exact corner curve (continuous radius 11 fits the profile within the pixel tolerance),
`controlSize`, `tint`; the dark appearance's active frame colour (the focus ring's dark blue is
used, unverified); the panel's own look is the host's.
