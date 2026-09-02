# Element workflow (one element per PR)

1. **Document** `Docs/elements/<Element>.md`: API surface from Apple's documentation (signatures,
   overloads, availability), documented behaviours, platform defaults that must be inferred, open
   questions. Link the Apple doc pages.
2. **Fixtures** in `Fixtures/Sources/<Element>/`: at least five layout fixtures covering sizes,
   alignment, modifiers, edge cases; a behaviour fixture with `steps` where state matters.
3. **Goldens**: `scripts/gen-goldens.sh <Element>` on a Mac; commit `Fixtures/Goldens/<Element>/`.
   Never regenerate in CI. Record macOS/SwiftUI versions (`meta.json` does this).
4. **Implement** in `Sources/SwiftUIWebCore/API/...` plus runtime/layout/paint pieces.
5. **Verify**: `swift test --filter <Element>` (Tier A exact), wasm build, browser Tier B within
   tolerance, gallery page added, browser screenshot attached to the PR.
6. **Record**: update `Docs/support.json` honestly and run `scripts/support-matrix.py`; write the
   measured constants (spacing, padding, control geometry) into the element doc with the fixture
   that proves each one.
