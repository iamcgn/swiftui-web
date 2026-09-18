# Progress page

The SwiftUIWeb progress page (decision 0016), written in nothing but SwiftUI and rendered by
SwiftUIWeb at `/progress/` next to the landing page: the counts per framework, the full support
matrix with a search field and status filters (every row links to the gallery fixtures that
prove it), the todo list grouped by priority and framework (every item links to the docs it
refers to), what landed recently and the non-goals. `Sources/Progress/ProgressData.swift` is
generated from `Docs/support.json` and `Docs/todo.json` by `scripts/gen-progress.py`, which CI
runs with `--check`.

```sh
. scripts/env.sh
scripts/build-wasm.sh Examples/Progress --debug   # wasm bundle
python3 -m http.server 8770 --directory Examples/Progress   # http://localhost:8770/
(cd Examples/Progress && swift run Progress)      # the same page natively in an AppKit window
scripts/build-landing.sh                          # release bundle into Examples/Landing/dist/progress
```
