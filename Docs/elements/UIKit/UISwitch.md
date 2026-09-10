# UISwitch

`Packages/UIKitWeb/Sources/UIKitWebCore/Controls/UISwitch.swift`. Fixture `uikit/controls/basic`
(off, on, disabled on).

## API

`isOn`, `setOn(_:animated:)`, `onTintColor`, `thumbTintColor`, `isEnabled`, `preferredStyle`,
`valueChanged` through `UIAction`; a tap or a horizontal pan toggles it; the semantics tree
exposes it as a switch.

## Measured, and a Catalyst artefact

UIKitWeb draws the iPhone switch: 51 × 31, a 27 pt white knob 2 pt in, the track green
(`systemGreen`) when on and `(120, 120, 128, 16 %)` when off, at 50 % when disabled.

Catalyst draws the Mac switch instead: 63 × 28 with a 37 × 24 knob (`UISwitchModernVisualElement`
with a `_UILiquidLensView`, the macOS 26 look), tinted grey. `UIKitGoldenFrameTests` therefore
compares only the switch probes' origins (`originOnlyProbes`), and the goldens' pixels are not
the iPhone's. The iOS SwiftUI profile pinned its toggle to Catalyst's 61 × 28
(`Docs/elements/iOS.md`); the two disagree by design until a simulator host records iPhone
goldens for both.
