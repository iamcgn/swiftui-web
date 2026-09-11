# Element workflow (one element per PR)

UIKit elements (decision 0014) follow the same loop with their own pieces: fixtures in
`Fixtures/UIKit/<Element>/` against the `UIKitFixtureKit` API, strings in
`Fixtures/UIKit/TextMetrics/UIKitTextMetricsRequests.swift` with the label's line limit,
goldens from `scripts/gen-goldens-sim.sh uikit` on an iPhone simulator (`--dump` shows UIKit's internal geometry, after each behaviour step too; a fixture that presents alerts or sheets is `.capturesWindow()`, so the golden and its probes cover the window; decision 0015), the
metrics table from `scripts/uikit-font-metrics-table.py`, Tier A in
`Packages/UIKitWeb/Tests/UIKitWebTests/UIKitGoldenFrameTests.swift`, the pixel tier in
`UIKitPixelTests.swift` (the CoreGraphics painter against the simulator's PNGs, 3 %;
`TIER_C_REPORT=1`, `TIER_C_DUMP=<dir>`), Tier B through the gallery (which hosts every UIKit
fixture in a representable: `scripts/tier-b.sh --filter uikit/`), docs in
`Docs/elements/UIKit/<Element>.md`.

1. **Document** `Docs/elements/<Element>.md`: API surface from Apple's documentation (signatures,
   overloads, availability), documented behaviours, platform defaults that must be inferred, open
   questions. Link the Apple doc pages.
2. **Fixtures** in `Fixtures/Sources/<Element>/`: at least five layout fixtures covering sizes,
   alignment, modifiers, edge cases; a behaviour fixture with `steps` where state matters:
   `Fixture(name, size:, model: { Model() }, steps: [FixtureStep("insert") { $0.items.insert(…) }, …]) { model in … }`
   with an `@Observable` model read inside the content. Every string a fixture shows goes into
   `Fixtures/Sources/TextMetrics/TextMetricsRequests.swift` under the font it is shown in (the
   default font is `TextMetricsRequests.defaultFont`, the 13 pt system font, not `.body`), with the
   width it is proposed and its `TextMetricOptions` (`lineLimit`, reserved lines, `lineSpacing`,
   truncation) when any is set; a concatenation with several fonts is one request with `runs:`.
   The recorded engine also answers an unconstrained request that fits the proposal, so a
   default-font word only needs the plain entry.
   Images and colours come from `Fixtures/Assets.xcassets` (edit `scripts/gen-fixture-assets.py`, rerun
   it, then `scripts/assets.py Fixtures --json Fixtures/Assets.manifest.json`); fixture sources use
   `Image("name")` / `Color("name")` as an app would (decision 0011).
   Geometry that must match Apple's `Path` output goes into `Fixtures/Sources/Shape/PathRequests.swift`
   (the harness records each path's `description` into `Fixtures/Goldens/shape/paths.json`,
   `PathGoldenTests` compares element by element; `scripts/gen-goldens.sh shape-paths` alone).
3. **Goldens**: `scripts/gen-goldens.sh <Element>/` on a Mac (plus `scripts/gen-goldens.sh text-metrics`
   when strings or fonts were added, then `scripts/font-metrics-table.py`); commit
   `Fixtures/Goldens/<Element>/`. Frames and pixels come from a hosted key window (decision
   0010); behaviour fixtures get `frames.json["steps"]` and `step-N@2x.png` per step. Never
   regenerate in CI. Record macOS/SwiftUI versions (`meta.json` does this).
4. **Implement** in `Sources/SwiftUIWebCore/API/...` plus runtime/layout/paint pieces.
5. **Verify**: `swift test --filter GoldenFrameTests` (Tier A exact, steps included), wasm build
   and `js test` in a worktree, `scripts/tier-b.sh --filter <Element>/` within tolerance (each step
   is checked as its own render), gallery page added, browser screenshot attached to the PR.
6. **Record**: update `Docs/support.json` honestly and run `scripts/support-matrix.py`; write the
   measured constants (spacing, padding, control geometry) into the element doc with the fixture
   that proves each one.
