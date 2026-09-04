# Gauge

Apple docs: [Gauge](https://developer.apple.com/documentation/swiftui/gauge),
[GaugeStyle](https://developer.apple.com/documentation/swiftui/gaugestyle),
[GaugeStyleConfiguration](https://developer.apple.com/documentation/swiftui/gaugestyleconfiguration),
[gaugeStyle(_:)](https://developer.apple.com/documentation/swiftui/view/gaugestyle(_:)).

## API surface

| API | Notes |
|---|---|
| `Gauge(value:in:label:)`, `Gauge(value:in:label:currentValueLabel:)`, `Gauge(value:in:label:currentValueLabel:minimumValueLabel:maximumValueLabel:)` | implemented; the value is normalised into the bounds and clamped |
| `Gauge(value:in:label:currentValueLabel:markedValueLabels:)`, the six-label form | accepted; marked value labels are not drawn (macOS draws none either) |
| `GaugeStyle`, `GaugeStyleConfiguration` (`value`, `label`, `currentValueLabel`, `minimumValueLabel`, `maximumValueLabel`), `gaugeStyle(_:)` | implemented; custom styles receive the configuration |
| `.automatic` (= `.linearCapacity` on macOS), `.linearCapacity`, `.accessoryLinear`, `.accessoryLinearCapacity`, `.accessoryCircular`, `.accessoryCircularCapacity` | implemented |
| `tint(_:)` | the linear capacity bar's fill (green by default); the accessory styles are monochrome as on macOS |
| `labelsHidden()` | no effect (macOS keeps the gauge's label) |
| Animated value changes, the accessory styles' tinted variants (watchOS), `GaugeStyleConfiguration.MarkedValueLabel` | missing |

## Behaviour

Every style is a composite of the existing stacks and two leaves (`GaugeBarNode`,
`GaugeRingNode`). Linear capacity: a `VStack` at the default spacing of the label, the bar row
and the current value label (all centred); the row is an `HStack(spacing: 8)` of the minimum
label, the 16 pt bar and the maximum label. Accessory linear capacity: the bounds labels flank a
leading-aligned column of the label, the 8 pt capsule and the 12 pt secondary value, 6 pt apart.
Accessory linear: `_AccessoryLinearLayout`, a `Layout` that is as tall as the 8 pt track whatever
its labels, places the minimum (or current) value label before the track and the maximum after
it 8 pt apart in the 17 pt semibold font, centred on the track. Accessory circular: a `ZStack` of
the 58 pt ring, the 24 pt medium current value label lifted 1 pt, and, for the open style, the
11 pt label (or the bounds labels, the minimum starting and the maximum ending at the arc's
ends) offset 26/√2 under the centre.

## Measured (macOS 26.2, `gauge/basic`, `gauge/accessory`, 2026-09-04)

| Property | Value | Probe |
|---|---|---|
| Linear capacity | 280 × 40.1509: a 13 pt label (16) 8.1509 over a 16 pt bar; a current value label adds 4.7422 + 16 (60.8931); everything centred | `bare`, `value`, `total`, `capacity`, `hidden` |
| Bar | corner radius 1.5 (the corner ramp at 2×), track black 18/255 (237), the fill the tint (green 52/199/89 by default, red 255/56/60 for `tint(.red)`) as a rounded rect of the fraction's width (112 for 0.4 × 280); a `frame(width: 120)` narrows it | `narrow`, `tinted`, pixels |
| Bounds labels | "0" (8.5) and "100" (22.5) in 13 pt 8 pt from the bar (36.5…269.5) on its row; the labels above and below stay centred on the whole width | `bounds` |
| Accessory circular | 58 × 58: a 6 pt ring at radius 26 in the primary black (216/255); the open arc spans 270° centred on the bottom with round caps, 242° (14° less at each end) when bounds labels are shown; the marker at the fraction along the arc is a 2.5 pt dot in a ≈ 4.5 pt white halo | `circular`, `circularBare`, `circularBounds`, pixels |
| Accessory circular capacity | a full ring at black 76/255 (179) under the primary arc from the top, clockwise, round caps; no label under it | `circularCapacity`, pixels |
| Ring labels | the current value in 24 pt medium (pixel-identical against candidates) centred, 1 pt above the centre; the label in 11 pt with its line 18.4 under the centre; bounds labels in 11 pt from x = centre − 18.4 to centre + 18.4 | pixels |
| Accessory linear | 280 × 8: a capsule track in the primary black; the knob a 4 pt-radius dot in an 8 pt white halo at 4 + fraction × (track − 8); the minimum (or current) value label before and the maximum after the track in 17 pt semibold, 8 pt apart, centred on the track and overflowing the 8 pt row (the current value is not shown when bounds labels are) | `linear`, `linearBounds`, `linearBare`, pixels |
| Accessory linear capacity | 280 × 52: the 13 pt label, a 6 pt gap, the 8 pt capsule (track black 15/255, fill black 85/255 of the fraction's width), a 6 pt gap, the 12 pt secondary value; leading-aligned, the 13 pt bounds labels 8 pt beside the column, vertically centred on it | `linearCapacity`, `linearCapacityBounds`, pixels |

## Verification (2026-09-04)

Tier A: both fixtures exact (every gauge's frame, the 8 pt accessory linear rows included).
Tier B, frames exact in Chromium, WebKit and Firefox; pixels `gauge/basic` ≤ 0.32 % and
`gauge/accessory` ≤ 1.12 % (Chromium 1.12, WebKit 0.92, Firefox 1.07: the browsers' fallback
digits in the 17 pt labels, half-pixel edges of the ring, the marker halo). Tier C: 0.14 % and
0.92 %. `GaugeTests` cover the linear capacity layout and fills, the tint and normalisation, the
accessory row (labels centred on the 8 pt track, the knob), the capsule capacity column, the
rings' arcs, trim and marker, and a custom style.

## Not yet covered

Animated value changes, marked value labels, the watchOS tinted accessory looks, the exact
marker halo radius and the sub-pixel snapping of the ring labels.
