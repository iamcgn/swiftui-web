# 0015 — iOS goldens from an iPhone simulator

Status: accepted (2026-09-10); UIKit and SwiftUI iOS goldens both moved

## Context

Decision 0013 took the iOS goldens from a UIKit window on Mac Catalyst because no Xcode was
installed: the Command Line Tools' SDK carries Catalyst's UIKit and SwiftUI. Catalyst is not an
iPhone. It runs the iPad idiom, measures text 2 to 4 % wider than SF drawn at size, reports its
own font metrics (`UIFont.ascender` 1980/2048 of the size where the iPhone says 1950/2048, a
rounded `lineHeight`, labels a point taller at some sizes), draws the Mac switch (63 × 28), the
Mac slider knob and Mac window greys in dark mode, and cannot show sheets, date pickers or tab
bars the way an iPhone does. The runtime carried carve-outs for each (frames-only fixtures, wider
tolerances, "documented, not copied" looks). Xcode 27 with the iOS 26 and 27 simulator runtimes
is installed now.

## Decision

- The iOS goldens come from an iPhone simulator: `scripts/gen-goldens-sim.sh ios|uikit [filter]`
  builds the harness executable with SwiftPM against the iPhoneSimulator SDK
  (`--triple arm64-apple-ios26.0-simulator`, `-Xswiftc -sdk`), wraps it in an app bundle, installs
  it on the device and launches it with the console attached; the app writes into the repository
  directly (simulator processes run as the user, unsandboxed on the host file system), and the
  script fails on any `FAILED` line.
- The device is an **iPhone SE (3rd generation) on iOS 26.0** ("SwiftUIWeb SE", created on
  demand). It is the one current iPhone with a 2× screen: frames land on the half-point grid the
  runtime, the browser on a Mac and the macOS goldens use. A 3× device would put every rounded
  frame on thirds. iOS 26 rather than 27 keeps the iOS goldens in the same SwiftUI generation as
  the macOS 26 goldens; switching the runtime is one constant in the script.
- The generators are shared with the Catalyst route: `GoldenGenIOS` (was `GoldenGenCatalyst`)
  and `UIKitGoldenGen` build for any `os(iOS)`; `meta.json`'s `host` names the producer
  (`iPhoneSimulator 26.0 SwiftUIWeb SE` or `macCatalyst`). The Catalyst scripts stay as a
  comparison tool for machines without Xcode and are never used to commit goldens.
- The swiftly toolchain keeps building against the Command Line Tools' macOS SDK
  (`SDKROOT` in `scripts/env.sh`): with Xcode selected, `xcrun` would hand it Xcode 27's SDK,
  whose interfaces a Swift 6.3 compiler cannot read (`unknown argument: '-target-arch-variant'`).
  The simulator scripts use Xcode's `/usr/bin/swift`.
- Fixtures wider than the SE's 375 × 667 screen (three `ios/` fixtures at 400) snapshot
  completely: `drawHierarchy` renders the window's whole extent, on screen or not.
- The window pins the regular vertical size class (`traitOverrides`): a window under 415 pt
  tall would otherwise be a landscape phone, with no large titles and shorter bars. The status
  bar is hidden (`UIStatusBarHidden`) so navigation bars sit at the window's top, as in a browser.

## Log

- 2026-09-10, UIKit: the seven `uikit/` fixtures, `text-metrics.json` and `font-metrics.json`
  regenerated on the simulator. Differences from Catalyst, all now in the runtime and
  `Docs/elements/UIKit`: text 2 to 4 % narrower; UIFont's ascender and descender are SF's hhea
  values, `lineHeight` their unrounded difference, and a label of n lines is n line heights plus
  n − 1 leadings rounded up to the pixel, for sized fonts and text styles alike (the generated
  table lost its exception list); `boldSystemFont` is SF Semibold on iOS; the 15 pt system button
  is 30 tall; a plain text field is line height plus 1.5 rounded up, its width rounded up to the
  point; the switch is 51 × 31, so the test's origin-only carve-out is gone. Tier A exact, no
  tolerances.
- 2026-09-10, SwiftUI: all 36 `ios/` fixtures and `ios/text-metrics.json` regenerated on the
  simulator, `SystemFontMetricsTableIOS.swift` from it. The runtime followed (`Docs/elements/iOS.md`
  has the numbers): the 66 × 30 iOS 26 switch, list rows whose controls are their label's line,
  the plain button's spacing, the 0.5 pt divider, bars of 116.5 and 64 with a 52.5 collapse and
  the title 16 in, the scrolled title fading under the bar's glass with the content showing
  through (`_navigationBarOverhang`), opaque screens, the iPhone palette (opaque labels, the
  (60, 60, 67) secondary, tertiary and quaternary as fractions of it, dark grey, indigo and
  accent), a plain list black behind its rows only, undimmed toggle and stepper labels. The
  Catalyst allowances are gone from Tier A (`approximatePrefixes` keeps only the symbol
  extrapolation), Tier B and Tier C (no `ios/` width or pixel multipliers, no frames-only
  fixtures; dark fixtures composite over the black window, which the gallery paints too).
