# TabView

Apple docs: [TabView](https://developer.apple.com/documentation/swiftui/tabview),
[tabItem](https://developer.apple.com/documentation/swiftui/view/tabitem(_:)).

## API surface

| API | Notes |
|---|---|
| `TabView(content:)`, `TabView(selection:content:)`, `tabItem(_:)`, `tag(_:)` on tabs | implemented: the macOS tab view; without a binding the view keeps its own selection by index |
| `TabViewStyle`, `.automatic`, `tabViewStyle(_:)` | accepted; only the macOS look exists |
| `Tab(_:systemImage:value:content:)`, `Tab(_:image:value:content:)`, `Tab(value:content:label:)`, the value-less forms, `TabContent`, `TabContentBuilder` | implemented (2026-10-04): a tab is a view that wraps its content in `tabItem` and `tag`; `tabview/tab-api`, `ios/tabs/badges` |
| `badge(_:)` (count, text, key, string) | implemented: the iOS bar paints a red capsule on the symbol (`ios/tabs/badges`); the macOS bar shows none, as SwiftUI's segments do not; lists do not show badges yet |
| `disabled` on a tab | implemented: the segment takes no press and the arrow keys skip it; the title dims by half (SwiftUI 7.6's segment keeps its full alpha: approximate) |
| `tabViewStyle(.page)`, `PageTabViewStyle(indexDisplayMode:)`, `IndexDisplayMode` (`automatic`, `always`, `never`) | implemented (`ios/tabs/page`): the tabs are pages the tab view's size side by side, the selected one in view, a horizontal swipe past 40 pt turns the page; the indicator's dots as measured; no slide animation yet. iOS-only in SwiftUI (the macOS harness cannot measure it) |
| `tabViewStyle(.sidebarAdaptable)`, `.tabBarOnly`, `.grouped`, `TabViewStyle._isPaged` | accepted: the platform's bar |
| Tab item images in the macOS bar | the segments show titles only, as SwiftUI's do |

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

## iOS (iPhone SE simulator, `ios/tabs/basic`, `ios/tabs/second`, 2026-09-18)

The bar is iOS 26's floating capsule at the window's bottom (`tabBarAtBottom`): 270 wide and
58 tall on a 375 pt window, 23 above the bottom, a symbol and a 10 pt label per tab, the
selected tab on a 93.5 × 53.5 pill; the content fills the window less 83 at the bottom. Numbers
and colours in `Docs/elements/iOS.md`; `TabItemNode` reads the label's first system image for
the symbol.

## The Tab API, badges and the page style (macOS 26.6 `tabview/tab-api`; iPhone SE simulator `ios/tabs/badges`, `ios/tabs/page`; 2026-10-04)

| Behaviour | Value | Fixture |
|---|---|---|
| macOS bar with the Tab API | the same segments and content placement as the `tabItem` form ("Home content" 86 × 16 at (137, 134), exact in Tier A); SwiftUI 7.6 paints the selected segment raised in white where 7.2 (the older goldens) filled it darker, shows no badge and does not dim the disabled title | `tabview/tab-api` |
| iOS badges | a red (255, 59, 48) capsule 20 pt tall, at least 19.5 wide ("3"), 34.5 for "New"; its left edge 7.5 right of the symbol's centre, its top 4.5 above the symbol; the text 13 pt white centred; five tabs share the bar in 54 pt slots | `ios/tabs/badges` |
| iOS page style | the selected page centred in the window (the 120 × 80 colour at (127.5, 293.5)); three 7 pt dots 18 apart on a row 21.5 above the bottom, the current one white and the others white at 45 % (the window behind them is clear, so over a white ground they do not show) | `ios/tabs/page` |

## Not yet covered

The page style's slide animation and the dots' background, badges on list rows, the bar's focus
ring, keyboard access to the bar without focusing it, the hidden tabs' retained state, the
macOS 26.6 segment look (the raised white selection; the 26.2 goldens stay).
