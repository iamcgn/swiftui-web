# Charts (sw-frameworks, 2026-10-12)

Swift Charts for SwiftUIWeb: `import Charts` unchanged, a `Chart` of marks painted into a
canvas over the display list (`Sources/Charts`, product `Charts`; decision 0018). The look is
measured from Apple's Charts on macOS 27 (`charts/bar`, `charts/line`, `charts/area`,
`charts/scales`; the goldens come from the real framework through the harness). Native Tier C
agrees to 0.1–1.5 %, the browser's Tier B to 0.3–1.7 %, both within the approximate bound: the
glyphs are the same, the axis and mark geometry follows the measurements below.

## What is there

| API | Status |
|---|---|
| `Chart { }`, `Chart(data) { }`, `Chart(data, id:) { }`, `ChartContentBuilder` (conditionals, arrays, `ForEach`) | implemented |
| `BarMark` (x/y, ranges, a single axis), `LineMark`, `PointMark`, `AreaMark` (y or a range), `RuleMark` (x, y, ranges), `RectangleMark` | implemented |
| `PlottableValue.value(_:_:)`, `Plottable` (numbers, strings, dates, raw-representable enums), `.value(_:_:unit:)` for dates | implemented |
| `foregroundStyle(by:)` with the palette and a legend, `foregroundStyle(_:)` (colours, gradients through the canvas), `opacity`, `cornerRadius`, `lineStyle`, `interpolationMethod` (linear, steps, Catmull-Rom; monotone and cardinal as Catmull-Rom), `symbol`, `symbolSize`, `position(by:)` (dodged bars), `offset`, `zIndex` | implemented |
| `annotation(position:alignment:spacing:content:)` | implemented: the view is a canvas symbol placed against the mark's frame (overflow resolution accepted) |
| Stacking: bars and areas sharing a position stack by their series (positives up, negatives down) | implemented |
| `chartXAxis` / `chartYAxis` (`.hidden`, `AxisMarks` with `values:` automatic, `.stride(by:)`, explicit values, calendar strides; `AxisGridLine`, `AxisTick`, `AxisValueLabel` plain, fixed text, `format:`, custom content; `position: .leading`; marks per value) | implemented (ticks are not drawn: Swift Charts' default ticks are invisible on macOS; custom tick strokes are ignored) |
| `chartXScale` / `chartYScale(domain:)` (numbers, dates, categories), `chartForegroundStyleScale` (mapping, range, domain + range), `chartSymbolScale` | implemented |
| `chartLegend(.hidden)`, `chartLegend(position:)` (bottom, top, leading, trailing) | implemented |
| `chartXAxisLabel` / `chartYAxisLabel` | implemented (approximate: the x title centred below the labels, the y title above the axis column) |
| `chartPlotStyle`, `chartOverlay`, `chartBackground` with `ChartProxy` (`plotSize`, `plotFrame` as a `CGRect`, `position(forX:)`, `position(forY:)`, `value(atX:)`, `value(atY:)`) | implemented (the proxy's geometry estimates label widths at 0.56 em; `plotFrame` is a rectangle, not an `Anchor`) |
| Temporal axes: the domain is the data's extent; ticks at years, months, days or hours by the span, labelled "2026", "Jan", "12", "3 PM" | implemented (approximate: Swift Charts' label formats vary with the span) |
| `chartScrollableAxes`, `chartXSelection`, `chartGesture`, `chartXVisibleDomain`, the accessibility modifiers, `clipShape`, `shadow`, `blur` on marks | accepted, no effect |
| `SectorMark` (pies), `MapKit`-style `chartPlotStyle` gestures, log scales, `AxisTick` rendering, `MarkStackingMethod` other than standard, label collision handling beyond dropping the one past the plot's end | missing |

## The measurements (macOS 27, `charts/*` goldens)

- The chart fills its proposal; axis labels are 11 pt (`subheadline`; 12 on iOS) secondary
  text. The y axis sits trailing: a column `ceil(widest label) + 4` wide, each label 4 pt after
  the plot's edge, centred on its tick (the top one spills above the plot). The x axis takes
  the label's line height (14 in the engines) + 6 below the plot, the label's top 5 below it.
- A nominal x axis is bands in order of appearance: labels centred under the band, dashed
  vertical grid lines (1 pt primary at 13 %, 3 on 3 off from the plot's top) at every band
  edge; bars are 70 % of the band, centred; lines, points and areas use the band centres.
- A quantitative axis includes zero, takes four intervals (one per 60 pt past 240) and a step
  of 1, 2, 2.5 or 5 × 10ⁿ, the smallest at least the raw interval (0…90 → 0, 25, 50, 75, 100);
  horizontal grid lines are solid. Quantitative x labels are leading-aligned 4 pt after their
  tick and a label past the plot's end is dropped.
- A nominal y axis runs top to bottom. With `AxisMarks(position: .leading)` its labels sit
  inside the band (4 in, 5 down) and the bar takes 70 % of what is left below a 20 pt block.
- Marks without a series paint Swift Charts' blue (0, 122, 255); series take the system
  colours in order (blue, green, orange, purple, red, cyan, yellow, pink, brown, indigo, mint,
  teal). Lines are 2 pt with round caps and joins, points 8 pt circles (symbol area 16π),
  rules 2 pt with round caps, areas solid. `cornerRadius` rounds the value end only.
- The legend is a row 8 below the chart: 8 pt swatches, 5 before their text, entries 8 apart.
- An annotation at `.top` sits 4 above the mark's frame (a rule's stroke bounds), aligned by
  its alignment.

## How

`Chart` collects its content into `_MarkRecord`s (`ChartContent._collect`), `_ChartModel`
resolves series, stacking and the scales, and `_ChartPainter` paints grid, marks, labels and
annotations into a `Canvas` that is not clipped to its bounds (`Canvas._unclipped`, so the top
label and round caps spill as Apple's do). Annotations and axis titles are the canvas's
symbols. `ChartsTests` (10 tests) holds the records, scales, stacking, the measured geometry
and the proxy; `charts/*` the pixels in Tiers B and C.
