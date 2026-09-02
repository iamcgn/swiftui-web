# Browser runner

```sh
cd Playwright && npm install && npm run install-browsers
node run-page.mjs http://127.0.0.1:8765/index.html --pattern '\[spike05\]' --wait-for measureText --shot spike05.png
```

Serve a built bundle first (`scripts/build-wasm.sh <pkg>` then `scripts/serve.sh <pkg> 8765`).
Tier B fidelity tests (frames via the debug bridge, screenshots, accessibility snapshots) will be
added here in Phase 1.
