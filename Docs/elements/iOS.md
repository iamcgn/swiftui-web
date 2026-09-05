# iOS platform profile

The runtime reproduces the macOS look by default. `PlatformProfile.iOS`, selected through the
`platformProfile` environment (fixtures marked `.platform(.iOS)`, the landing page's phone
frame), switches text styles, control geometry and colours to the iOS look. Goldens come from a
UIKit window on Mac Catalyst (decision 0013, `scripts/gen-goldens-ios.sh`), whose iPad idiom
shares text styles and controls with iPhone; the metrics live in `PlatformMetricsIOS.swift`
and `SystemFontMetricsTableIOS.swift`.

## What switches

| Piece | macOS | iOS |
|---|---|---|
| Default text font | 13 pt system font | `.body` (17 pt, 24.5 pt line, baseline 18) |
| Text styles | HIG macOS table | HIG iOS table: largeTitle 34 (48.5 line), title 28 (41), title2 22 (32), title3 20 (28), headline 17 semibold, subheadline 15 (21), body 17, callout 16 (24), footnote 13 (18.5), caption 12 (17.5), caption2 11 (16) |
| Bold trait | per style (`text/bold-trait`) | bold for largeTitle, title and title2; semibold for every other style, headline included (`ios/text/bold-trait`: the widths of the w600 faces) |
| Default padding, stack spacing | 16, 8 | 16, 8 (text-to-text 2 for body, 8 sideways); controls keep the plain 8 and let a text's own distances win: 14.54 from a body text (or a borderless button) down to a control, 8.04 from a control up to a text; a toggle or stepper row spaces like a control, not like its label (`ios/layout/controls`) |
| Button (automatic) | bordered | borderless: body label in the accent colour, red for a destructive role |
| Bordered / prominent button | 24 pt rounded rect, 13 pt label | 38.5 pt capsule: body label, 12 pt sideways and 7 pt vertical padding; fill black 41/255 (prominent: the accent, white label) |
| Toggle (automatic) | checkbox | a row filling the proposed width: label leading, switch in a 61 × 28 frame trailing, text baselines at the row's top; hidden label = the switch alone |
| Slider | 16 pt row, label before the track | 31 pt row filling the width, no label outside a form, accent fill; disabled: accent at 50 % |
| Stepper | 20 × 26 arrows after the label | a row filling the width: label leading, a 94 × 32 control trailing (93 × 28 capsule, black 11/255, a 1 pt divider at 75/255, − and + of 13 pt / 2 pt strokes at 218/255); text baselines at the row's top; − left decrements |
| TextField | 24 pt bezel | 34 pt rounded border (0.5 pt black 20 % inside, 4 pt corners, text 7.5 in, baseline 23.5 down), 26 pt plain with the text at the top; automatic = plain; placeholder (189, 189, 190); secure bullets 7 pt at a 10.5 pitch |
| Picker (menu) | pop-up button with the label | the selected value in the accent colour with two chevrons, no box or label: 40.5 tall, 13.5 in each side, chevrons 9 wide 4 after the text |
| Picker (segmented) | equal segments of the widest option + 21 | fills the proposed width, 31 tall, capsule black 31/255; the selected segment a white capsule inset 7 × 2; titles 13 pt medium (selected semibold), 7 pt down |
| Disabled labels | 30 % | 24 % (52 over 215) |
| Plain text field, empty | — | 25 pt while only the placeholder shows, 26 with text (`ios/dark/controls` `emptyField`) |
| List (automatic) | inset rows on white | inset grouped: a (235, 236, 236) ground, each section a white card 16 in with 26 pt continuous corners; rows max(56, content + 30) with content 16 in and centred, 1 pt separators from the content's leading edge to the card's inner edge, none under a card's last row; 35 above a first card without a header; headers in body medium, secondary, 27.5 below the previous card (10 at the top) and 10 above their card; navigation link rows fill the row and end in a 7 × 12 chevron at 30 % |
| Section footer | 12 pt text | footnote in the secondary colour, 8 below its card in a 21 pt slot (UIKit's label height around the 18.5 pt line, so the footer probes are ignored while the rows around them are checked), the next card 23.5 below the slot (`ios/list/footer`) |
| ProgressView (linear) | a 20 pt row with an 8 pt pill | a 4 pt accent pill on a (120, 120, 125) 20 % track, no indeterminate segment; a label sits 4 above it in the primary colour (`ios/progress/basic`) |
| ProgressView (circular) | a 32 pt ring or spinner | always the 20 pt spinner, a value included: eight spokes from 38 % to 12 % black, the darkest pointing left; a label below it in the secondary colour |
| List (plain) | 8 pt margins | white, rows 56 with content 16 in, separators 16 in; headers 32 below the previous row, 10 above the next |
| Form | columns | an inset grouped list; a menu picker row keeps its label and puts the value and chevron, in the secondary colour, at the trailing edge; sliders lose their label; text fields are plain |
| NavigationStack | content-sized; no bar (the window's title) | fills its proposal (`ios/nav/sizing`: 320 × 267.5 above a text in a 300 pt column); each screen under its own bar: 117 pt with the large title (34 pt bold, 20 in, its line 65.5 down) or 64 pt inline (headline, centred), none for an untitled root or a pushed screen with neither title nor back button (`ios/nav/push-noback` fills the stack); a large title takes the list's 35 pt top inset, an inline one does not; `.automatic` on a pushed screen inherits the previous screen's large title (`ios/nav/push`: 117 over the detail) |
| Large title on scroll | — | the title scrolls up with the screen's content, clipped under the 64 pt inline zone; once the content has scrolled its full 53 pt the bar is the inline one, the content frame grows by 53 and its offset shrinks by 53 so what is on screen stays put (`ios/nav/scroll`: a 40 pt scroll leaves the bar large, a far one collapses it); back at the top it expands again (UIKit leaves a programmatic scroll to the top collapsed; a drag expands it) |
| Back button | none | a pushed screen's bar (unless `navigationBarBackButtonHidden`): a 44 pt circle at (10, 10) filled (246, 246, 246) at 66 % (white behind it reads 249.5, the grey ground 243), a chevron 8 × 16 between its tips of a 3 pt round stroke, its centre 1.5 left and 0.5 below the circle's, in the accent colour; the large title keeps its place below it; pressing pops |
| Push, pop | instant | a 0.35 s ease-in-out slide: the pushed screen arrives from the trailing edge over the old one, which travels 30 % of the width the other way under a black dimming that reaches 10 %; the bars cross-fade; a pop reverses it and keeps the popped screen mounted until it is out. Inferred from iOS, not measurable from goldens |

## Measured (Mac Catalyst on macOS 26.2, `ios/*` fixtures, 2026-09-05)

Every row above comes from `Fixtures/Goldens/ios/<fixture>/frames.json` and pixels sampled from
`image@2x.png`: `ios/text/styles`, `ios/layout/basics`, `ios/toggle/basic`, `ios/button/basic`,
`ios/slider/basic`, `ios/stepper/basic`, `ios/textfield/basic`, `ios/picker/basic`,
`ios/controls/settings` (the landing page's screen), `ios/progress/basic`, `ios/text/bold-trait`,
`ios/layout/controls`, `ios/list/footer`, `ios/nav/scroll` (a `ScrollViewReader` step; UIKit's
`List` ignores `scrollTo` on Catalyst, so the fixture scrolls a plain scroll view), and
2026-09-05 later `ios/form/basic`,
`ios/list/basic`, `ios/list/plain`, `ios/nav/basic`, `ios/nav/inline`, `ios/nav/sizing` and the
behaviour fixtures `ios/nav/push`, `ios/nav/push-inline`, `ios/nav/push-noback` (a push and a pop
through the path binding; the Catalyst host waits a second after each step so the goldens hold
the settled screen). The first nine are exact in Tier A; the list-backed ones are within 2 pt:
Catalyst lays list rows out with UIKit cells, whose text measures about 1.5 pt narrower than
SwiftUI's `Text` of the same string.

## Colours and the dark appearance

`ios/color/system` and `ios/dark/system-colors` read macOS 26's palette through the Catalyst
pipeline (every value within ±6 of the macOS goldens: blue (6, 136, 255) for (0, 136, 255)), so
the iOS profile shares both palettes with macOS (`PlatformProfile.iOSLightColors`,
`iOSDarkColors` in `Display/ColorTable.swift`); labels keep the alphas those goldens show
(216/255 black or white). The backgrounds are iOS's own: a white window with the (235, 236, 236)
grouped ground and white cards in the light appearance; in the dark one a black window, black
text fields and plain lists (`ios/dark/controls` `roundedField`: black inside a white 20 %
border), and the documented grouped values, a black ground with (28, 28, 30) cards. Measured
in `ios/dark/controls`: the bordered button (118, 121, 128) at 32 % (the light one is black at
16 %), the slider's unfilled track and the stepper's pill at the light alphas in white, the
placeholder white at 25 % (painted as the documented (235, 235, 245) at 30 %), the selected
segment (191, 191, 204) at 47 % over a (117, 117, 130) 24 % fill. Unmeasured: the switch's off
track (white at 22 %, for iOS's (57, 57, 60)) and the back button's dark fill.

Catalyst renders its dark appearance in a Mac window: a translucent (53, 53, 53) backing behind
plain content, a (29, 30, 30) ground with (50, 50, 50) cards and (70, 70, 70) separators in
grouped lists, and premultiplied PNGs. The runtime paints iOS's blacks instead, so `ios/dark/*`
and `ios/color/*` are frames-only in Tier B and C (`Playwright/tier-b.mjs`, `NativePixelTests`).

## Catalyst deviations painted the iOS way

Catalyst draws two AppKit-backed controls in a Mac shape: the switch (a 61 × 24 grey capsule
with a 37 × 20 pill knob, and grey rather than green when on) and the slider knob (a 37 × 24
pill). The runtime keeps their measured frames (the toggle row's 61 × 28, the slider's 31) and
paints the iOS controls inside them: a 51 × 31 green (52, 199, 89) or black-9 % capsule with a
27 pt white round knob, and a 4 pt track with a 27 pt round knob. `ios/toggle/*` and
`ios/slider/*` are therefore frames-only in Tier B and C. The back button's chevron is grey
(164) in the goldens, the inactive look of a Catalyst window; the runtime paints it in the
accent colour as iOS does (within Tier B's pixel tolerance). Catalyst's text line heights are its
own (body 24.5 where an iPhone lays out 22); a simulator run can replace the goldens
(`GoldenHost` in the harness) when Xcode is available.

## The host's default

`Runtime.hostPlatformProfile` is the profile the root starts in. The canvas host picks iOS on a
touch device (the `(pointer: coarse)` media query: the primary pointer is a finger, an iPad
with a trackpad included; `maxTouchPoints` stays 0 in emulated WebKit and Firefox) and macOS
elsewhere; a page forces either with
`data-platform="ios"` / `"macos"` on the `#app` container or `?platform=ios` in its URL
(`Playwright/counter.mjs` checks all three). Changing it while mounted re-applies the tree. The
native and headless hosts stay on macOS. A subtree keeps its own choice through the
`platformProfile` environment value: the landing page pins its prose to macOS and opts the
phone frame into iOS.

## Not yet covered

Sheets, date pickers, the `Menu` button, tab bars, list selection looks, a footer followed by
a header, the swipe back and the title/back button crossfade of a push, the large title's
snap at the end of a short drag (it tracks the content continuously here).
