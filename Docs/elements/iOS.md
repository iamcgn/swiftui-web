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
| Bold trait on `.body` | semibold | semibold (`Bold` measures 37.5, the w600 face) |
| Default padding, stack spacing | 16, 8 | 16, 8 (text-to-text 2 for body, 8 sideways) |
| Button (automatic) | bordered | borderless: body label in the accent colour, red for a destructive role |
| Bordered / prominent button | 24 pt rounded rect, 13 pt label | 38.5 pt capsule: body label, 12 pt sideways and 7 pt vertical padding; fill black 41/255 (prominent: the accent, white label) |
| Toggle (automatic) | checkbox | a row filling the proposed width: label leading, switch in a 61 × 28 frame trailing, text baselines at the row's top; hidden label = the switch alone |
| Slider | 16 pt row, label before the track | 31 pt row filling the width, no label outside a form, accent fill; disabled: accent at 50 % |
| Stepper | 20 × 26 arrows after the label | a row filling the width: label leading, a 94 × 32 control trailing (93 × 28 capsule, black 11/255, a 1 pt divider at 75/255, − and + of 13 pt / 2 pt strokes at 218/255); text baselines at the row's top; − left decrements |
| TextField | 24 pt bezel | 34 pt rounded border (0.5 pt black 20 % inside, 4 pt corners, text 7.5 in, baseline 23.5 down), 26 pt plain with the text at the top; automatic = plain; placeholder (189, 189, 190); secure bullets 7 pt at a 10.5 pitch |
| Picker (menu) | pop-up button with the label | the selected value in the accent colour with two chevrons, no box or label: 40.5 tall, 13.5 in each side, chevrons 9 wide 4 after the text |
| Picker (segmented) | equal segments of the widest option + 21 | fills the proposed width, 31 tall, capsule black 31/255; the selected segment a white capsule inset 7 × 2; titles 13 pt medium (selected semibold), 7 pt down |
| Disabled labels | 30 % | 24 % (52 over 215) |
| List (automatic) | inset rows on white | inset grouped: a (235, 236, 236) ground, each section a white card 16 in with 26 pt continuous corners; rows max(56, content + 30) with content 16 in and centred, 1 pt separators from the content's leading edge to the card's inner edge, none under a card's last row; 35 above a first card without a header; headers in body medium, secondary, 27.5 below the previous card (10 at the top) and 10 above their card; navigation link rows fill the row and end in a 7 × 12 chevron at 30 % |
| List (plain) | 8 pt margins | white, rows 56 with content 16 in, separators 16 in; headers 32 below the previous row, 10 above the next |
| Form | columns | an inset grouped list; a menu picker row keeps its label and puts the value and chevron, in the secondary colour, at the trailing edge; sliders lose their label; text fields are plain |
| NavigationStack | no bar (the window's title) | a bar over the content: 117 pt with the large title (34 pt bold, 20 in, its line 65.5 down) or 64 pt inline (headline, centred); a large title takes the list's 35 pt top inset, an inline one does not |

## Measured (Mac Catalyst on macOS 26.2, `ios/*` fixtures, 2026-09-05)

Every row above comes from `Fixtures/Goldens/ios/<fixture>/frames.json` and pixels sampled from
`image@2x.png`: `ios/text/styles`, `ios/layout/basics`, `ios/toggle/basic`, `ios/button/basic`,
`ios/slider/basic`, `ios/stepper/basic`, `ios/textfield/basic`, `ios/picker/basic`,
`ios/controls/settings` (the landing page's screen), and 2026-09-05 later `ios/form/basic`,
`ios/list/basic`, `ios/list/plain`, `ios/nav/basic`, `ios/nav/inline`. The first nine are exact
in Tier A; the list-backed ones are within 2 pt: Catalyst lays list rows out with UIKit cells,
whose text measures about 1.5 pt narrower than SwiftUI's `Text` of the same string.

## Catalyst deviations painted the iOS way

Catalyst draws two AppKit-backed controls in a Mac shape: the switch (a 61 × 24 grey capsule
with a 37 × 20 pill knob, and grey rather than green when on) and the slider knob (a 37 × 24
pill). The runtime keeps their measured frames (the toggle row's 61 × 28, the slider's 31) and
paints the iOS controls inside them: a 51 × 31 green (52, 199, 89) or black-9 % capsule with a
27 pt white round knob, and a 4 pt track with a 27 pt round knob. `ios/toggle/*` and
`ios/slider/*` are therefore frames-only in Tier B and C. Catalyst's text line heights are its
own (body 24.5 where an iPhone lays out 22); a simulator run can replace the goldens
(`GoldenHost` in the harness) when Xcode is available.

## Not yet covered

Sheets, date pickers, the `Menu` button, progress views, tab bars, footers and list selection
looks, the back button and push transition, dark mode colours, the bold trait of the other text
styles, default control spacing in a `VStack`, and the touch-device default: hosts still start
in the macOS profile.
