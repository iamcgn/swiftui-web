# 0016 — The progress page: one source of truth for what works and what is next

Date: 2026-09-12
Status: proposed

## Context

Seven phases in, the project's state lives in four places that drift: `Docs/support.json` (139
SwiftUI rows and 5 interop rows, no rows for UIKitWeb's sixty-odd classes), the `## Not yet
covered` and `Open:` lines in `Docs/elements/*.md` (some name work that later steps closed:
`Text.md` still lists kerning as missing, `CollectionView.md` lists supplementary views as open),
the status tables in `Docs/ROADMAP.md` (a log, not a plan), and the memory of whoever last
worked on it. The landing page shows the SwiftUI matrix and a few demos; the gallery, which is
the complete set of examples (381 goldens across 68 prefixes, SwiftUI and UIKit, with the source
that made each), is a local tool nobody outside the repository can open. A reader who wants to
know what works, see it run, and learn what is planned has no page that answers all three.

Phase 7 also leaves the representables with a short list of unmeasured corners (`layoutOptions`,
safe areas, hover, traits, animations across the seam, `UIHostingConfiguration`'s state) that
should close before the next sweep starts.

## Decision

Three data files in `Docs/` are the truth, every page and markdown table is generated from them,
and CI refuses stale outputs.

1. **`Docs/support.json`** keeps its shape and gains a `framework` per section (`SwiftUI`,
   `UIKit`, `Interop`; absent means SwiftUI) and sections for every UIKit class with a status,
   notes and the `uikit/` fixtures that prove it. Every row names at least one fixture (the
   gallery link for that row) or says why none can exist.
2. **`Docs/todo.json`** is the plan: one item per gap with a framework, an area, a `kind`
   (missing, accepted, approximate, verify, infra), a `priority` (next: Phase 8 in order; soon:
   the gap sweep, what ordinary apps hit; later: needs a decision, a subsystem or a platform), a
   `status` (planned, in-progress, done with a date, wontfix with the reason) and `refs` into
   the docs. Done items stay so the page can show what landed; non-goals stay so nobody asks
   twice.
3. **`scripts/gen-progress.py`** validates both files and renders `Docs/support-matrix.md`
   (taking over `scripts/support-matrix.py`), `Docs/TODO.md`, the landing page's summary counts
   and the progress page's data blob. `--check` is a CI step.

Two pages join the landing page on GitHub Pages, built by the same workflow:

- **`/progress/`** (`Examples/Progress`, a SwiftUI app like the landing page): the counts per
  framework and section with the commit and date they were generated at; the full matrix with
  status filters and a search field, every row linking to its gallery examples and its element
  doc; the todo list grouped by framework and priority; what landed recently. This is the page
  someone tracking the project reads.
- **`/gallery/`** (`Examples/Gallery`, a release build): every fixture, its source and its steps,
  SwiftUI and UIKit alike, reachable by name (`?fixture=`) and by prefix (`?filter=`). This is
  the complete set of examples of what is supported: a fixture exists for exactly the behaviour
  the goldens pin.

The landing page links to both from its navigation bar and its hero, and its matrix section
becomes a summary card (counts per framework, a link to the full page), which also trims its
bundle. The element workflow's last step becomes: mark the todo item done with the date, add the
gaps the step found as new items, update the support row, run the generator, commit the outputs.

Phase 8 of the roadmap is this decision's execution, in order: finish the representables, land
the tracking data and the generator, publish the gallery and the progress page, link the landing
page, then the gap sweep through `todo.json`'s `next` and `soon` items.

## Evidence

- Rows without a fixture: 38 of 139 (`python3 -c` over `support.json`, 2026-09-12). Most are
  composition and state rows that every fixture exercises; three are documented non-goals.
- The gallery's debug bundle is 60 MB (84 MB with ICU); the landing page's release build is
  10.9 MB of wasm, 2.9 MB over the wire. A release gallery is expected between the two; the
  build logs its size, and the first release build sets the gate the deploy refuses to exceed
  until the substrate tables are trimmed (`uk-size`).
- Stale notes found by the 2026-09-12 sweep of `Docs/elements`: `Transaction` "no animation
  member", `Text.md`'s missing list, `Animation.md`'s "not yet" list, `CollectionView.md`,
  `Presentation.md` and `TableView.md`'s first `Open:` lines, `Navigation.md`'s toolbars. Zero
  `TODO`/`FIXME` markers exist in `Sources/` or `Packages/UIKitWeb/Sources`; the five `Accepted
  without effect` comments all have matching doc rows.

## Consequences

- One edit per landed step (the todo item and the support row) keeps the site, the markdown and
  the roadmap in agreement; the CI check makes forgetting it a failed build rather than drift.
- The progress page is itself a SwiftUI app rendered by SwiftUIWeb: a third demonstration, with
  the same self-contained constraint as the landing page (`import SwiftUI` only, no libm).
- `Docs/ROADMAP.md`'s status tables stay as the log of what each step measured; the plan moves
  to `todo.json`. Element docs keep their `## Not yet covered` sections as the detailed source
  the todo items point at, reconciled once (`st-row-audit`) and then per step.
- `scripts/support-matrix.py` and `scripts/gen-landing-support.py` fold into the one generator;
  the landing workflow's path filter adds `Docs/todo.json`, `Examples/Progress/**` and
  `Examples/Gallery/**`.
- AppKit representables and the other frameworks (Charts, Map) stay decisions to make, listed
  as `later` items rather than implied by silence.
