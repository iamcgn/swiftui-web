# 0009. Platform profile: macOS look first, all constants measured, iOS behind the same table

Date: 2026-09-02
Status: accepted

## Context
SwiftUI's defaults (padding, spacing, control geometry, text styles, colours) are undocumented
and differ per platform. Goldens come from this Mac.

## Decision
`PlatformProfile` (macOS today) holds every inferred constant: text-style sizes and weights,
the measured font metrics table, the light system colour table, and `PlatformMetrics` for
padding (16), spacing (8), divider (1), bold trait (semibold), bordered button geometry
(24 pt, 12 pt padding, 6 pt radius, 7.5 % fill). Each value cites the fixture that proves it
in `Docs/elements/*.md`; a value without a fixture is marked unverified. The environment
carries the profile so an iOS profile can be selected per app later without touching layout.

## Consequences
- Dark appearance, iOS and dynamic type sizes are new tables, not new code paths.
- Goldens are regenerated only in deliberate PRs (`meta.json` records macOS/SwiftUI versions).
