# ProgressView

Apple docs: [ProgressView](https://developer.apple.com/documentation/swiftui/progressview),
[ProgressViewStyle](https://developer.apple.com/documentation/swiftui/progressviewstyle),
[controlSize](https://developer.apple.com/documentation/swiftui/view/controlsize(_:)).

## API surface

| API | Notes |
|---|---|
| `ProgressView()`, `ProgressView(_ title)`, `ProgressView(label:)` | implemented: the indeterminate spinner (linear style: an indeterminate bar) |
| `ProgressView(value:total:)`, `ProgressView(_ title, value:total:)`, `ProgressView(value:total:label:)`, `ProgressView(value:total:label:currentValueLabel:)`, `ProgressView(_ configuration:)` | implemented; `nil` values are indeterminate, values clamp to 0…1 |
| `ProgressViewStyle`, `ProgressViewStyleConfiguration` (`fractionCompleted`, `label`, `currentValueLabel`), `.automatic`, `.linear`, `.circular`, `progressViewStyle(_:)` | implemented |
| `ControlSize`, `controlSize(_:)`, `EnvironmentValues.controlSize` | implemented: spinners and rings follow it (16 small, 32 regular measured; mini 12, large 32 unverified); other controls ignore it |
| `tint(_:)` | implemented (2026-10-04): the iOS bar's fill; on macOS the bar and ring of an active window (`Runtime.windowIsActive`, off by default: the measured looks are the inactive window's greys) |
| `ProgressView(timerInterval:countsDown:)` (with `label`, `currentValueLabel`) | implemented: the bar follows the clock through the animation timeline (filling, or emptying when counting down); the default current value label is the time left as m:ss, refreshed four times a second |
| `ProgressView(_ progress: Progress)` | implemented: wasm's `Progress` is `_WebProgress` (unit counts, a fraction, a description; observable); Apple platforms' Foundation `Progress` is re-read every frame (no key-value observing) |
| The spinner's rotation, the indeterminate bar's motion | implemented, approximate: the darkest spoke steps clockwise one spoke every eighth of a second; the bar's segment crosses the track once every 1.5 s and wraps (frame subscriptions while indeterminate; the goldens' first frames stay) |
| Animated values | implemented: a fraction changed under `withAnimation` tweens in the bar and the ring (`presentedFraction`) |
| `gaugeStyle` | see Docs/elements/Gauge.md |

## Behaviour

The default style is linear for a determinate task and circular otherwise. `_LinearProgress`
stacks the label, a `_ProgressBar` row and the current value label (secondary colour) with no
spacing, leading-aligned; `_CircularProgress` stacks a `_ProgressRing` and the labels (secondary)
with the stack's default spacing. `ProgressBarNode` is as wide as proposed (100 unproposed,
unverified) and 20 tall, painting an 8 pt pill track at black 15/255 and a pill of the fraction's
width at black 85/255 (an indeterminate bar an 8 pt segment at the start). `ProgressRingNode` is
a square of the control size's diameter: a 5 pt ring at black 13/255 with the fraction's arc
from the top, clockwise, round-capped, at black 70/255; without a fraction, eight round 3 pt
spokes from radius 6.5 to 14 fading clockwise from the darkest one on the left (black 53/255 to
17/255; the spinner's animation phase is fixed, so its pixels are approximate).

## Measured (macOS 26.2, `progress/basic`, `progress/indeterminate`, 2026-09-04)

| Property | Value | Probe |
|---|---|---|
| Bar row | 20 tall, full width; the pill 8 tall centred, track black 15/255, fill black 85/255, rounded both ends | `bare` (280 × 20 in 280), pixels |
| Label above the bar, value label below | 16 + 20 = 36; 16 + 20 + 16 = 52, no spacing, leading | `labelled`, `valueLabel` |
| Frame | `frame(width: 120)` narrows the bar | `narrow` |
| `total` | 25 of 50 fills half | `total` |
| Ring | 32 × 32, 5 pt stroke, track black 13/255, fill black 70/255 clockwise from the top | `ring`, `ringFull`, pixels |
| Ring label | under the ring at the stack's default spacing: 32 + 4.74 + 16 = 52.74 | `ringLabelled` |
| Spinner | 32 × 32 regular, 16 × 16 `.small`; label under it like the ring's | `spinner`, `small`, `spinnerLabelled` |
| Indeterminate bar | the 20 pt row with an 8 pt segment at the start (the animation's first frame) | `bar` |
| `tint(.red)` | the inactive golden window keeps the grey fill | `tinted` |

## Verification (2026-09-04)

Tier A: both fixtures exact. Tier B and Tier C: see the roadmap row (`progress/indeterminate` is
approximate in both: the spinner's spokes and the bar segment animate). `ProgressViewTests` cover
the bar and ring commands, labels, `total`, the spinner and control sizes.

## Not yet covered

The real motion of the spinner and the indeterminate bar (unmeasured: the goldens hold their
first frames), the active window's accent fill against an active window, key-value observing of
Foundation's `Progress`, `gauge`-like value labels, mini/large sizes. `ProgressAnimationTests`
cover the spinner phase, the travelling segment, animated values, timer intervals, `Progress`
objects and tint.
