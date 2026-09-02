#!/usr/bin/env bash
# Source this before building: `. scripts/env.sh`
# 1. swiftly toolchain (Swift matching .swift-version) first on PATH
# 2. On macOS, expose ONLY Apple's `ld` through a shim dir, ahead of any other `ld` on PATH
#    (Anaconda ships an ld64-530 from 2022 that fails with "unknown option: -no_warn_duplicate_libraries").
#    Prepending the whole CommandLineTools bin dir would shadow swiftly's `swift`, so we don't.
[[ -f "$HOME/.swiftly/env.sh" ]] && . "$HOME/.swiftly/env.sh"
if [[ "$(uname)" == "Darwin" ]]; then
  _APPLE_LD="$(xcrun --find ld 2>/dev/null || echo /Library/Developer/CommandLineTools/usr/bin/ld)"
  _SHIM="${TMPDIR:-/tmp}/swiftuiweb-ld-shim"
  mkdir -p "$_SHIM" && ln -sfn "$_APPLE_LD" "$_SHIM/ld"
  export PATH="$_SHIM:$PATH"
  unset _APPLE_LD _SHIM
fi
