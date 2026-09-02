# Browser runner

```sh
cd Playwright && npm install && npm run install-browsers
node run-page.mjs http://127.0.0.1:8765/index.html --pattern '\[spike05\]' --wait-for measureText --shot spike05.png
```

Serve a built bundle first (`scripts/build-wasm.sh <pkg>` then `scripts/serve.sh <pkg> 8765`).

- `tier-b.mjs`: Tier B fidelity (probe frames via the debug bridge, screenshots against the
  goldens, behaviour steps); run through `scripts/tier-b.sh [--browser chromium|webkit|firefox]`.
- `counter.mjs`: the Counter example end to end.
- `scroll-probe.mjs`: interactive scrolling in the gallery (`--fixture scroll/long`): a real wheel
  event, 60 in-page wheel ticks with the host's layout + paint time per frame
  (`__swiftuiwebDebug.frameMillis()`), clamping at the top and the indicator fade. Measurements
  are recorded in `Docs/elements/ScrollView.md`; use a release build for numbers.
