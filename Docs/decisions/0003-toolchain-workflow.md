# 0003. Toolchain workflow: swiftly + wasm SDK, Apple toolchain only for the harness

Date: 2026-09-01
Status: accepted

## Context
The official Swift SDK for WebAssembly requires an exactly matching swift.org toolchain; Apple's
Xcode/Command Line Tools toolchain cannot use it. Apple's SwiftUI (for goldens) is only usable
from Apple's toolchain. Both must coexist on one machine.

## Decision
- `.swift-version` pins the swift.org toolchain (6.3.3), installed with swiftly; the matching
  `swift-6.3.3-RELEASE_wasm` SDK is installed with `swift sdk install` (see `scripts/bootstrap.sh`).
- `. scripts/env.sh` before any build of the root package. It activates swiftly and exposes
  Apple's `ld` through a shim directory (an Anaconda `ld` earlier on PATH broke linking with
  `unknown option: -no_warn_duplicate_libraries`). It deliberately does not put the whole
  CommandLineTools bin dir on PATH, which would shadow swiftly's `swift`.
- `Harness/` is built with `/usr/bin/swift` (Apple toolchain) and never with swiftly.
- wasm builds use `--scratch-path .build/wasm` and `--target`/`--product` so SwiftPM does not
  try to compile plugin host tools (BridgeJSTool) for wasm. Mixing a wasm `swift build` and a
  native `swift test` in the same scratch directory corrupted the build manifest once.
- `swift package --swift-sdk <sdk> js` needs `--use-cdn` for a plain static server (otherwise the
  generated `index.js` imports bare npm specifiers and needs a bundler such as Vite).
- `js test` runs `npm install` from inside the SwiftPM plugin sandbox, which has no network;
  run it with `--disable-sandbox`.

## Evidence
Root package: `swift test` (7 tests, macOS native) and `swift build --swift-sdk ... --target
SwiftUIWebCanvas` both green on 2026-09-01. Spike package built and ran in headless Chromium.
