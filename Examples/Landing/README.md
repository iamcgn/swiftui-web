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

## The gist

The two source files depend on nothing but `import SwiftUI`, so they live in a GitHub gist as
well: https://gist.github.com/iamcgn/f7e74fe1718809dd1efb3df1acfd37f3 (id `f7e74fe1718809dd1efb3df1acfd37f3`).

```sh
scripts/landing-gist.sh push f7e74fe1718809dd1efb3df1acfd37f3   # update the gist from Sources/Landing (needs gh)
scripts/landing-gist.sh pull f7e74fe1718809dd1efb3df1acfd37f3   # fetch the gist's files back into Sources/Landing
scripts/landing-gist.sh push                                     # create a new public gist
```

## GitHub Pages

`.github/workflows/landing.yml` builds `dist/` on every push to `main` and deploys it to Pages
(enable Pages with the "GitHub Actions" source in the repository settings). The workflow
installs the toolchain with `scripts/bootstrap.sh`; it has not run yet because the repository
has no remote.
