# Landing page

The SwiftUIWeb landing page, written in nothing but SwiftUI and rendered by SwiftUIWeb: a sales
page with live controls and the support matrix. `Sources/Landing/LandingApp.swift` is the page;
`Sources/Landing/SupportData.swift` is generated from `Docs/support.json` by
`scripts/gen-landing-support.py` (run it after adding an element, so the page's feature list
stays current).

```sh
. scripts/env.sh
scripts/build-wasm.sh Examples/Landing --debug   # wasm bundle
scripts/serve.sh Examples/Landing 8768           # http://localhost:8768/
(cd Examples/Landing && swift run Landing)       # the same page natively in an AppKit window
scripts/build-landing.sh                         # release bundle + Examples/Landing/dist for GitHub Pages
```

## Loading screen

`index.html` shows a wordmark, a progress bar and a status line until the app has painted its
first frame: it fetches the wasm itself and pipes the bytes through a `TransformStream` that
counts them (against `data-wasm-bytes`, which `build-landing.sh` fills in, because Pages serves
the file gzip-compressed and the response's `Content-Length` is the compressed size), hands the
stream to `init({ module })` so compilation still streams, and listens for `swiftuiwebready`,
which `CanvasHost` dispatches on `#app` after its first frame. A load error shows in the status
line. `Playwright/landing-load.mjs <url>` checks the sequence in Chromium (throttled), WebKit
and Firefox.

## The gist

The two source files depend on nothing but `import SwiftUI`, so they can also live in a gist
(kept for sharing the source; the hosted page above is the primary link): https://gist.github.com/iamcgn/f7e74fe1718809dd1efb3df1acfd37f3 (id `f7e74fe1718809dd1efb3df1acfd37f3`).

```sh
scripts/landing-gist.sh push f7e74fe1718809dd1efb3df1acfd37f3   # update the gist from Sources/Landing (needs gh)
scripts/landing-gist.sh pull f7e74fe1718809dd1efb3df1acfd37f3   # fetch the gist's files back into Sources/Landing
scripts/landing-gist.sh push                                     # create a new public gist
```

## GitHub Pages

The page is hosted at https://iamcgn.github.io/swiftui-web/. `scripts/deploy-landing.sh` builds
the release bundle (under a per-build directory name, so cached copies of an older bundle are never
reused) and pushes `dist/` as the `gh-pages` branch, which Pages serves from its root
(repository settings: Pages source "Deploy from a branch", `gh-pages`, `/`).

The `Landing page` GitHub Action (`.github/workflows/landing.yml`) runs the same script on every
push to `main` that touches the page, the runtime sources, `Docs/support.json` or the build
scripts (and on demand from the Actions tab), so the hosted page follows `main` without a manual
deploy; `scripts/deploy-landing.sh` remains the way to publish from a machine.
