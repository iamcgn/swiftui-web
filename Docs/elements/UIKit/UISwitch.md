# UISwitch

`Packages/UIKitWeb/Sources/UIKitWebCore/Controls/UISwitch.swift`. Fixture `uikit/controls/basic`
(off, on, disabled on).

## API

`isOn`, `setOn(_:animated:)`, `onTintColor`, `thumbTintColor`, `isEnabled`, `preferredStyle`,
`valueChanged` through `UIAction`; a tap or a horizontal pan toggles it; the semantics tree
exposes it as a switch.

## Measured

The iPhone switch sizes to fit at 51 × 31 (`uikit/controls/basic`: off, on, disabled), which is
what UIKitWeb draws: a 27 pt white knob 2 pt in, the track green (`systemGreen`) when on and
`(120, 120, 128, 16 %)` when off, at 50 % when disabled.

Mac Catalyst draws the Mac switch instead, 63 × 28 with a 37 × 24 knob (the macOS 26 look), and
the first goldens came from there with the switch probes carved out; the simulator goldens
(decision 0015) compare them exactly. The iOS SwiftUI profile still carries Catalyst's 61 × 28
toggle (`Docs/elements/iOS.md`) until its goldens are regenerated on the simulator.
