# Element workflow (one element per PR)

1. **Document** `Docs/elements/<Element>.md`: API surface from Apple's documentation (signatures,
   overloads, availability), documented behaviours, platform defaults that must be inferred, open
   questions. Link the Apple doc pages.
2. **Fixtures** in `Fixtures/Sources/<Element>/`: at least five layout fixtures covering sizes,
   alignment, modifiers, edge cases; a behaviour fixture with `steps` where state matters:
   `Fixture(name, size:, model: { Model() }, steps: [FixtureStep("insert") { $0.items.insert(…) }, …]) { model in … }`
   with an `@Observable` model read inside the content. Every string a fixture shows goes into
   `Fixtures/Sources/TextMetrics/TextMetricsRequests.swift` under the font it is shown in (the
   default font is `TextMetricsRequests.defaultFont`, the 13 pt system font, not `.body`).
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
