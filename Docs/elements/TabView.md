# TabView

Apple docs: [TabView](https://developer.apple.com/documentation/swiftui/tabview),
[tabItem](https://developer.apple.com/documentation/swiftui/view/tabitem(_:)).

## API surface

| API | Notes |
|---|---|
| `TabView(content:)`, `TabView(selection:content:)`, `tabItem(_:)`, `tag(_:)` on tabs | implemented: the macOS tab view; without a binding the view keeps its own selection by index |
| `TabViewStyle`, `.automatic`, `tabViewStyle(_:)` | accepted; only the macOS look exists |
| `Tab(...)` (the iOS 18 tab API), `tabViewStyle(.page)`, `tabViewStyle(.sidebarAdaptable)`, badges, tab item images in the bar | missing (macOS ignores tab item images in its segments too) |

## Behaviour

`TabViewNode` collects the content's leaves (a `ForEach` id or the index stands in for a missing
tag) and titles each from the texts of the `tabItem` on the way down. The bar is a segmented
control of those titles: a segment is its title + 24 with 1 pt dividers between segments (none
next to the selected one), the whole centred at the top, 24 tall, filled black 20/255 with 6 pt
corners; the selected segment is filled black 50/255 inset 0.5 with 5.5 corners; titles use the
segmented control's text alphas. Only the selected tab's content is laid out, centred in the
area under the bar (the full width, from 24 to the bottom); a press on a segment or the arrow
keys on the focused bar select. The box behind everything starts 10 pt down: black 8/255 with
4.5 corners and a faint 1 pt border. The tab view fills what it is proposed.

## Measured (macOS 26.2, `tabview/basic`, `tabview/sized`, 2026-09-04)

| Property | Value | Probe |
|---|---|---|
| Frame | fills the window (360 × 260) or its frame (240 × 160) | `tabs` |
| Bar | 100…260 (160 for "One"/"Two"/"Three": 49 + 49 + 59.5 + 2 dividers, rounded to the half point), 24 tall, fill 235; the selected segment 100.5…148.5 at 205; the divider at 199.5 | pixels |
| Box | from y 10 to the bottom, fill 247, corner radius 4.5 (from the corner ramp), edge 245 | pixels |
| Content | centred under the bar: "First" 27 × 16 at (166.5, 134) in 360 × 260, "Alpha" at (162.75, 134) in a 240 × 160 frame at (60, 50) | `first`, `alpha` |
| Hidden tabs | AppKit keeps a hidden tab's view alive without updating it and reports its stale frame (163.5, 107); Tier A/B/C ignore that probe (`ignoredProbes`) | step `second` |

## Verification (2026-09-04)

Tier A: both fixtures exact (the `second` step included, the hidden tab's probe ignored). Tier B:
Chromium ≤ 0.41 %, WebKit ≤ 0.37 %, Firefox ≤ 0.46 % with its hinting-class shift of "First"
(26.5 wide at 166.75 against 27 at 166.5) in `tabview/basic`; `tabview/sized` exact everywhere.
Tier C: `tabview/basic` 0.37 % (0.36 % after the step), `tabview/sized` 0.17 %. `TabViewTests` cover the bar geometry and painting, content
placement, selection by press and keys, and the own-state variant.

## Not yet covered

Tab item images and badges, the iOS `Tab` API and styles, disabled tabs, the bar's focus ring,
keyboard access to the bar without focusing it, the hidden tabs' retained state.
