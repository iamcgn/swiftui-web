# SwiftUIWeb

An open-source reimplementation of SwiftUI that runs **unmodified SwiftUI source** in the
browser (WebAssembly + Canvas) today and natively on macOS/Linux later, with 1:1 rendering
and behaviour fidelity measured against the real SwiftUI.

```swift
import SwiftUI

@main struct CounterApp: App {
    var body: some Scene { WindowGroup { ContentView() } }
}

struct ContentView: View {
    @State private var count = 0
    var body: some View {
        VStack(spacing: 12) {
            Text("Count: \(count)")
            Button("Increment") { count += 1 }
        }
        .padding()
    }
}
```

No custom compiler: this package provides a module named `SwiftUI` with Apple's API surface,
a runtime and layout engine written from the documented semantics, and a painter backend.
Every element is verified against goldens rendered by Apple's SwiftUI on macOS.

## Status

Phase 0 (toolchain and spikes) is nearly complete; see `Docs/ROADMAP.md` for the status table and
`Docs/decisions/` for measured results. No SwiftUI API is implemented yet; `Docs/support-matrix.md`
will track that from Phase 1.

## Getting started

```sh
./scripts/bootstrap.sh          # swiftly + Swift 6.3.3 + wasm SDK + binaryen
swift test                      # native runtime + layout tests (fast)
./scripts/build-wasm.sh Examples/Counter   # wasm bundle
./scripts/serve.sh Examples/Counter        # open in a browser
```

## Layout of the repository

| Path | Purpose |
|---|---|
| `Sources/SwiftUI` | Thin `import SwiftUI` module re-exporting the implementation |
| `Sources/SwiftUIWebCore` | API, runtime, layout engine, text engine, display list |
| `Sources/SwiftUIWebCanvas` | wasm Canvas2D painter, semantics overlay, text input host |
| `Sources/SwiftUIWebHeadless` | Display-list recorder for native tests |
| `Fixtures/` | Fixture views (shared with the harness) and committed goldens |
| `Harness/` | Separate macOS package that renders fixtures with **Apple's** SwiftUI |
| `Docs/` | Architecture, element workflow, decision records, support matrix |

## Documentation

- `Docs/ARCHITECTURE.md`
- `Docs/ELEMENT_WORKFLOW.md`
- `Docs/decisions/`

## License

Apache-2.0. Ideas and small pieces are borrowed with attribution from Tokamak (Apache-2.0),
ElementaryUI (Apache-2.0) and OpenSwiftUI (MIT); see `NOTICE`.

## Running the examples

```sh
. scripts/env.sh                                  # swiftly toolchain + Apple ld shim
swift test                                        # native: runtime, layout and golden-frame tests
scripts/build-wasm.sh Examples/Counter --debug    # wasm bundle for the Counter app
scripts/serve.sh Examples/Counter 8765            # then open http://localhost:8765/
scripts/tier-b.sh --filter layout/                # browser fidelity: gallery + Playwright vs goldens
(cd Tools/Host && /usr/bin/swift run swiftui-host ../../Examples/Counter)   # the bundle in a WKWebView window
(cd Examples/Counter && swift run Counter)          # the same app natively: AppKit window, CoreGraphics painter
```

`Examples/Landing` is the project's landing page written in SwiftUI and rendered by SwiftUIWeb: a
sales page with live controls and the support matrix (generated from `Docs/support.json` by
`scripts/gen-landing-support.py`). `scripts/build-landing.sh` builds it into `Examples/Landing/dist`
for GitHub Pages (`.github/workflows/landing.yml` deploys it); `scripts/landing-gist.sh` keeps its two
source files in a gist. See `Examples/Landing/README.md`.

`Examples/Gallery` lists every fixture in a left pane and shows the selected one as code (the
`Fixture(...)` declaration or its whole file, via `scripts/gen-fixture-sources.py`) next to its live
preview, with buttons for its behaviour steps; `index.html?fixture=text/wrapped` opens one directly.
`scripts/gen-goldens.sh` regenerates goldens with Apple's SwiftUI (macOS only).

`Tools/Host` is the native host of Phase 4: `swiftui-host <package-dir>` serves the package's
`index.html` and built bundle on 127.0.0.1 and opens it in a WKWebView window (macOS 14+, Apple
toolchain). `--screenshot out.png` waits for the app's first frame, writes a snapshot and quits;
`--timeout seconds` quits on its own (both for scripts and CI); `--port`, `--path`, `--width` and
`--height` are optional.

`SwiftUIWebNative` (decision 0012) is the true native backend: on macOS `App.main()` opens an
AppKit window whose flipped view paints the display list with CoreGraphics and measures text
with CoreText, so an unmodified `@main` app runs with `swift run`. `SWIFTUIWEB_SCREENSHOT=out.png`
and `SWIFTUIWEB_TIMEOUT=seconds` capture the first frame from a script. Tier C
(`Tests/NativeFidelityTests`, part of `swift test` on macOS) paints every fixture natively and
compares it with Apple's golden pixels.

