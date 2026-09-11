# iOS platform profile

The runtime reproduces the macOS look by default. `PlatformProfile.iOS`, selected through the
`platformProfile` environment (fixtures marked `.platform(.iOS)`, the landing page's phone
frame), switches text styles, control geometry and colours to the iOS look. Goldens come from
an iPhone SE simulator on iOS 26 (decision 0015, `scripts/gen-goldens-sim.sh ios`; the Mac
Catalyst route of decision 0013 remains as a comparison tool); the metrics live in
`PlatformMetricsIOS.swift` and `SystemFontMetricsTableIOS.swift`.

## What switches

| Piece | macOS | iOS |
|---|---|---|
| Default text font | 13 pt system font | `.body` (17 pt, 24.5 pt line, baseline 18.5) |
| Text styles | HIG macOS table | HIG iOS table: largeTitle 34 (48.5 line), title 28 (41), title2 22 (32), title3 20 (28), headline 17 semibold, subheadline 15 (21), body 17, callout 16 (24), footnote 13 (18.5), caption 12 (17.5), caption2 11 (16) |
| Bold trait | per style (`text/bold-trait`) | bold for largeTitle, title and title2; semibold for every other style, headline included (`ios/text/bold-trait`: the widths of the w600 faces) |
| Default padding, stack spacing | 16, 8 | 16, 8 (text-to-text 2 for body, 8 sideways); controls keep the plain 8 and let a text's own distances win: 14.81 from a body text down to a control, 8.43 from a control up to a text; a borderless button takes its label's distance above and the plain 8 below; a toggle or stepper row spaces like a control, not like its label (`ios/layout/controls`) |
| Button (automatic) | bordered | borderless: body label in the accent colour, red for a destructive role |
| Bordered / prominent button | 24 pt rounded rect, 13 pt label | 38.5 pt capsule: body label, 12 pt sideways and 7 pt vertical padding; fill black 41/255 (prominent: the accent, white label) |
| Toggle (automatic) | checkbox | a row filling the proposed width: label leading, the iOS 26 switch (66 × 30: a green (52, 199, 89) or (118, 118, 124) 16 % capsule filling its frame, a 38 × 25 white pill knob 2.5 in, 0.5 from the on end) trailing, text baselines at the row's top; hidden label = the switch alone; disabled: the track at half strength, the knob and the label as they are; in a list row the toggle is its label's 24.5 pt line and the switch overflows it |
| Slider | 16 pt row, label before the track | 31 pt row filling the width, no label outside a form, accent fill; disabled: accent at 50 % |
| Stepper | 20 × 26 arrows after the label | a row filling the width: label leading, a 94 × 32 control trailing (93 × 28 capsule, black 11/255, a 1 pt divider at 75/255, − and + of 13 pt / 2 pt strokes at 218/255); text baselines at the row's top; − left decrements |
| TextField | 24 pt bezel | 34 pt rounded border (0.5 pt black 20 % inside, 4 pt corners, text 7.5 in, baseline 23.5 down), 26 pt plain with the text at the top, empty or not; automatic = plain; placeholder (189, 189, 190); secure bullets 7 pt at a 10.5 pitch |
| Picker (menu) | pop-up button with the label | the selected value in the accent colour with two chevrons, no box or label: 40.5 tall, 13.5 in each side, chevrons 9 wide 4 after the text |
| Picker (segmented) | equal segments of the widest option + 21 | fills the proposed width, 31 tall, capsule black 31/255; the selected segment a white capsule inset 7 × 2; titles 13 pt medium (selected semibold), 7 pt down |
| Disabled labels | 30 % | buttons 24 % (52 over 215); a toggle's or stepper's label is not dimmed |
| Divider | 1 pt | 0.5 pt, a hairline (`ios/layout/basics`) |
| Plain text field, empty | — | 26 pt, like one with text (`ios/dark/controls` `emptyField`) |
| List (automatic) | inset rows on white | inset grouped: a (235, 236, 236) ground, each section a white card 16 in with 26 pt continuous corners; rows max(56, content + 30) with content 16 in and centred, 1 pt separators from the content's leading edge to the card's inner edge, none under a card's last row; 35 above a first card without a header; headers in body medium, secondary, 27.5 below the previous card (10 at the top) and 10 above their card; navigation link rows fill the row and end in a 7 × 12 chevron at 30 % |
| SF Symbols | the metrics table's sizes | the same table by point size, weight and scale (`ios/symbol/basic`: star 22 × 20 at body, 36 × 34 at title); iOS's 28 and 34 pt styles are extrapolated from the macOS sizes, within 1.5 pt, so `ios/symbol/` and `ios/label/` are checked within 3 pt |
| Label | icon + 8 + title; in a list a 16 pt slot, 6 to the title | icon + 8 + title outside lists (`ios/label/basic`); in a list row the icon at the large image scale (star 28 × 27), centred in a 24 pt slot it may overflow, 16 to the title, the accent tint (`ios/label/list`; the row grows to the icon's 27) |
| Menu button | a pull-down button | its label in the body font and the accent colour, nothing else: no fill, no chevron (`menuIndicator` has nothing to hide); black at 67/255 when disabled; it lines up with text on the baseline (`ios/menu/basic`); the menu itself opens as the runtime's presentation |
| Section footer | 12 pt text | footnote in the secondary colour, 8 below its card in a 21 pt slot (UIKit's label height around the 18.5 pt line, so the footer probes are ignored while the rows around them are checked), the next card 23.5 below the slot (`ios/list/footer`); a header that follows a footer sits 16 below the slot (`ios/list/footer-header`) |
| ProgressView (linear) | a 20 pt row with an 8 pt pill | a 4 pt accent pill on a (120, 120, 125) 20 % track, no indeterminate segment; a label sits 4 above it in the primary colour (`ios/progress/basic`) |
| ProgressView (circular) | a 32 pt ring or spinner | always the 20 pt spinner, a value included: eight spokes from 38 % to 12 % black, the darkest pointing left; a label below it in the secondary colour |
| List (plain) | 8 pt margins | white, rows 56 with content 16 in, separators 16 in; headers 32 below the previous row, 10 above the next |
| Form | columns | an inset grouped list; a menu picker row keeps its label and puts the value and chevron, in the secondary colour, at the trailing edge; sliders lose their label; text fields are plain; a toggle, stepper or menu picker row is its label's 24.5 pt line and the control overflows it (rows stay 56) |
| NavigationStack | content-sized; no bar (the window's title) | fills its proposal (`ios/nav/sizing`: 320 × 267.5 above a text in a 300 pt column); each screen under its own bar: 117 pt with the large title (34 pt bold, 20 in, its line 65.5 down) or 64 pt inline (headline, centred), none for an untitled root or a pushed screen with neither title nor back button (`ios/nav/push-noback` fills the stack); a large title takes the list's 35 pt top inset, an inline one does not; `.automatic` on a pushed screen inherits the previous screen's large title (`ios/nav/push`: 117 over the detail) |
| Large title on scroll | — | the title scrolls up with the screen's content, clipped under the 64 pt inline zone; once the content has scrolled its full 53 pt the bar is the inline one, the content frame grows by 53 and its offset shrinks by 53 so what is on screen stays put (`ios/nav/scroll`: a 40 pt scroll leaves the bar large, a far one collapses it); back at the top it expands again (UIKit leaves a programmatic scroll to the top collapsed; a drag expands it) |
| Back button | none | a pushed screen's bar (unless `navigationBarBackButtonHidden`): a 44 pt circle at (10, 10) filled (246, 246, 246) at 66 % (white behind it reads 249.5, the grey ground 243), a chevron 8 × 16 between its tips of a 3 pt round stroke, its centre 1.5 left and 0.5 below the circle's, in the accent colour; the large title keeps its place below it; pressing pops |
| Push, pop | instant | a 0.35 s ease-in-out slide: the pushed screen arrives from the trailing edge over the old one, which travels 30 % of the width the other way under a black dimming that reaches 10 %; the bars cross-fade; a pop reverses it and keeps the popped screen mounted until it is out. Inferred from iOS, not measurable from goldens |

## Measured (iPhone SE simulator, iOS 26.0, `ios/*` fixtures, 2026-09-10)

Every row above comes from `Fixtures/Goldens/ios/<fixture>/frames.json` and pixels sampled from
`image@2x.png`, all 36 `ios/` fixtures regenerated on the simulator with `scripts/gen-goldens-sim.sh ios`
(decision 0015). Tier A holds every one exact; the only allowances are the symbol table's
extrapolation (`ios/symbol/`, `ios/label/` within 3 pt), UIKit's footer slot (21 around a 19 pt
footnote line: the footer probes are ignored) and its header label ("Header" measures 37 for
SwiftUI's 36). Tier B and C compare pixels within the base 3 % everywhere (dark fixtures over the
black window the iPhone draws).

What the iPhone changed against the Catalyst goldens of 2026-09-05: text 2 to 4 % narrower and
the text styles' own metrics (body's baseline at 18.5, callout's line 23.5, footnote's 19); the
0.5 pt divider; the 66 × 30 iOS 26 switch; list rows whose toggle, stepper and menu picker are
their label's line; a borderless button spacing plainly below; navigation bars of 116.5 (large)
and 64 (inline) with the title 16 in; a scrolled large title fading under the bar's glass with the
content showing through; opaque screens; a plain list painting black only behind its rows in the
dark appearance; the palette below.

The first nine fixtures had been exact on Catalyst too; the list-backed ones were within 3 pt
there because Catalyst's UIKit cells measured text 1.5 to 2.5 pt narrower than SwiftUI's. That
allowance is gone: the iPhone's cells and text agree.

## Colours and the dark appearance

`ios/color/system` and `ios/dark/system-colors` on the iPhone: the tints match macOS 26's except
in the dark appearance, where grey is (142, 142, 147), indigo (107, 93, 255) and the accent
(0, 145, 255) (`PlatformProfile.iOSLightColors`, `iOSDarkColors` in `Display/ColorTable.swift`).
Labels are opaque black or white; the secondary label is (60, 60, 67) at 60 % (dark:
(235, 235, 245)), the tertiary and quaternary the secondary at half and 0.3 (30 % and 18 %),
which is how `.tertiary` and `.quaternary` resolve on iOS as fills and foreground styles. The
backgrounds: a white window with the (242, 242, 247) grouped ground and white cards in the
light appearance; in the dark one a black window, black text fields, a plain list black behind
its rows only, and the grouped values, a black ground with (28, 28, 30) cards. A navigation
screen is opaque: the list's ground, else the window's colour (`ios/nav/push-noback`,
`ios/dark/nav`). Measured in `ios/dark/controls`: the bordered button's fill (118, 121, 128) at
32 % (the light one (118, 118, 124) at 16 %), the slider's unfilled track and the stepper's pill
at the light alphas in white, the placeholder white at 25 %, the selected segment (191, 191, 204)
at 47 % over a (117, 117, 130) 24 % fill.

## The navigation bar's glass (iOS 26)

At rest the bar is transparent over the screen's ground (`ios/nav/basic`, `ios/nav/inline`).
Once content has scrolled under it (`ios/nav/scroll` `row1`, `row8`) a tint of the ink at 37/255
sits at the window's top and eases out over 80 pt (218 at the top, 231 at 40 pt, 246 at 60, 253
at 80 over white), full after a quarter of the collapse; the large title travels with the content
and fades over the collapse instead of being clipped, and the scroll view keeps painting up to the
window's top (`_navigationBarOverhang`), so the rows show through the glass.

## Open on the simulator

The compact `DatePicker` (iOS's tinted pills), tab bars and sheets have no `ios/` fixtures yet;
the simulator can render them now. The blur inside the bar's glass is approximated by the tint
alone. Dark-appearance switch and slider tracks are painted with the light alphas in white.

## The Catalyst route (decision 0013), kept for comparison

`scripts/gen-goldens-ios.sh` still renders the same fixtures in a UIKit window on Mac Catalyst
(iPad idiom). Its text measures 2 to 4 % wider than the iPhone's, its `UIFont` metrics differ
(`Docs/elements/UIKit/UIFont.md`), it draws the Mac switch and slider knob, a Mac window's greys
in the dark appearance with premultiplied PNGs, and the compact date picker, tab bars and sheets
as an iPad would. Nothing from it is committed; `meta.json`'s `host` names the producer.
