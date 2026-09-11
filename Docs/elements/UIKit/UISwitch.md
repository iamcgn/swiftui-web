# UISwitch

`Packages/UIKitWeb/Sources/UIKitWebCore/Controls/UISwitch.swift`. Fixture `uikit/controls/basic`
(off, on, disabled on).

## API

`isOn`, `setOn(_:animated:)`, `onTintColor`, `thumbTintColor`, `isEnabled`, `preferredStyle`,
`valueChanged` through `UIAction`; a tap or a horizontal pan toggles it; the semantics tree
exposes it as a switch.

## Measured

The iOS 26 switch is 68 × 30: `sizeToFit` (`uikit/controls/basic`: off, on, disabled) and
`intrinsicContentSize` (`uikit/controls/intrinsic`) agree, with `alignmentRectInsets` of 2 on the
right (so Auto Layout and SwiftUI align a 66 × 30 rectangle from the frame's origin;
`Docs/elements/Representable.md`) and content hugging of 750 on both axes. UIKitWeb draws the
capsule to the frame with a 38 × 25 white knob 2.5 in (scaled with the height at other sizes),
the track green (`systemGreen`) when on and `(120, 120, 128, 16 %)` when off, at 50 % when
disabled. An earlier simulator run had measured 51 × 31 for `sizeToFit`; the current one gives
68 × 30 in the same fixture.

Mac Catalyst draws the Mac switch instead, 63 × 28 with a 37 × 24 knob (the macOS 26 look), and
the first goldens came from there with the switch probes carved out; the simulator goldens
(decision 0015) compare them exactly. SwiftUI's `Toggle` on iOS 26 is a different control: a
66 × 30 switch with a 38 × 25 pill knob (`Docs/elements/iOS.md`), which the iOS profile draws.
