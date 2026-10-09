#!/usr/bin/env bash
# Source this before building: `. scripts/env.sh`
# 1. swiftly toolchain (Swift matching .swift-version) first on PATH
# 2. On macOS, expose ONLY Apple's `ld` through a shim dir, ahead of any other `ld` on PATH
#    (Anaconda ships an ld64-530 from 2022 that fails with "unknown option: -no_warn_duplicate_libraries").
#    Prepending the whole CommandLineTools bin dir would shadow swiftly's `swift`, so we don't.
# 3. On macOS, build against the Command Line Tools' macOS SDK: with Xcode selected, `xcrun`
#    hands the swiftly toolchain Xcode's newer SDK, whose interfaces it cannot read
#    ("unknown argument: '-target-arch-variant'"). Xcode stays the developer dir for the simulator
#    scripts, which use /usr/bin/swift. Since the Command Line Tools 27 their default SDK is
#    macOS 27 too, which the toolchain cannot read either, so the macOS 26 SDK is preferred
#    while it is still installed beside it.
[[ -f "$HOME/.swiftly/env.sh" ]] && . "$HOME/.swiftly/env.sh"
if [[ "$(uname)" == "Darwin" ]]; then
  for _SDK in MacOSX26.sdk MacOSX.sdk; do
    if [[ -d "/Library/Developer/CommandLineTools/SDKs/$_SDK" ]]; then export SDKROOT="/Library/Developer/CommandLineTools/SDKs/$_SDK"; break; fi
  done
  unset _SDK
  _APPLE_LD="$(xcrun --find ld 2>/dev/null || echo /Library/Developer/CommandLineTools/usr/bin/ld)"
  _SHIM="${TMPDIR:-/tmp}/swiftuiweb-ld-shim"
  mkdir -p "$_SHIM" && ln -sfn "$_APPLE_LD" "$_SHIM/ld"
  export PATH="$_SHIM:$PATH"
  unset _APPLE_LD _SHIM
fi
