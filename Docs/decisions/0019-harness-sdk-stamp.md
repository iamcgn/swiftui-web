# 0019 — The golden harness is linked against the SDK it says it is

Date: 2026-10-11
Status: accepted

## Context

Since the Mac moved to Xcode 27 (Swift 6.4), the macOS goldens regenerated for Phase 9 items
11, 15 and 16 showed controls of another era: 20 × 109 buttons where 26.2 drew 24.08 × 117,
14 pt checkboxes, 57 × 20 pop-ups, a 44 × 23 colour well, lists insetting a lone row 14 above
and 6.5 below. They were taken for macOS 27 changes, recorded as such and their probes ignored
("the control model is 26.2's"), to be addressed by `sw-mac-presentation-looks`.

They were not macOS 27. Swift 6.4's `swift build` (the Swift Build backend, `.build/out`)
links executables through clang with `--sysroot` rather than `-isysroot`; clang reads the SDK
version for ld's `-platform_version` from `-isysroot` or `SDKROOT`, and Swift Build passes a
clean environment, so the harness binaries were stamped with the deployment target as their SDK
(`LC_BUILD_VERSION` `minos 15.4 sdk 15.4`; the simulator harness `minos 26.0 sdk 26.0`).
AppKit and UIKit gate their current looks on the SDK a binary was linked against: a binary
"linked before 26" gets the pre-26 controls on macOS 27, and the iOS harness ran as an iOS 26
app on iOS 27. Plain `swiftc`, Xcode and the earlier SwiftPM backend stamp the real SDK, which
is why every probe written by hand (`xcrun swiftc`) showed the 24 pt controls the runtime models.

## Decision

- `scripts/gen-goldens.sh` and `scripts/gen-goldens-sim.sh` pass
  `-Xswiftc -Xclang-linker -Xswiftc -isysroot -Xswiftc -Xclang-linker -Xswiftc "$SDK"` so the
  link stamps the SDK's version (`sdk 27.0`); the iOS harness adopts the scene lifecycle
  (`SceneDelegate`, `UIApplicationSceneManifest` in the generated Info.plist), which iOS 27
  requires of an app linked against its SDK.
- The 47 macOS goldens generated under the wrong stamp were regenerated. Four changed:
  `colorpicker/form` (a checkbox row 8.15 below a well, not 6), `label/corners`, `symbol/basic`
  (the button back at 24.08 × 117) and `unavailable/*`. The ignores recorded for "macOS 27
  control sizes" are gone; what remained is modelled: `LabeledContent` grouped rows align
  their content on the label's baseline and sit 0.125 lower (`_FormRowMode.groupedBaseline`,
  `_formRowTop`), `ContentUnavailableView` is a column of its own height that the holder
  centres, drops its icon under height pressure and shows catalog images, gradients mirror
  their unit points in right-to-left layout, the grouped form's stepper row aligns on the
  stepper's baseline (21.5 tall) and its footer is the subheadline font, secondary, leading
  (the last two from `form/grouped`, regenerated to confirm).
- `Docs/ELEMENT_WORKFLOW.md` says to check the stamp (`otool -l`) before believing a golden
  shows an OS change in the controls.

## Consequences

The "macOS 27 control sizes" the roadmap rows for items 11, 15 and 16 mention were artefacts;
the rows are annotated. `sw-mac-presentation-looks` no longer carries a control-size question.
The 26.6 goldens of 2026-10-08/09 (`uk-*`) were made before the Xcode 27 upgrade and keep their
stamp-independent values; the iOS goldens regenerated for item 16 under the 26.0 stamp are
pixel-identical under the 27.0 one (`ios/unavailable/basic`), so nothing there changes. The
iOS text metrics merged for item 16 came from the same harness and stand.
