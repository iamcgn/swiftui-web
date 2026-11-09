# 0025 — An iOS app's `#if os(iOS)` code is the app

Date: 2026-11-09
Status: accepted

## Context

On wasm every `os(...)` condition is false. An iOS app written for several platforms mostly
spells its differences as `#if os(macOS) … #else … #endif`, and its `#else` is the iOS code, so it
built as iOS. PomPadDo (the sixth app in the browser) also spells them the other way, 22 times
in its iOS target: `#if os(iOS) @Binding var activeTasksCount: Int #endif` in one view, a call
passing `activeTasksCount:` in another. Compiled as not-iOS it is not the app at all: one file
calls an initializer another file does not declare. The browser runs iOS apps, as an iPhone
would (decision 0020's phone frame); their iOS code is what should compile.

There is no compiler flag that makes `os(iOS)` true for a wasm triple, and Apps/upstream/*
stays exactly its pin (scripts/check-apps.sh).

## Decision

`Apps/ios-conditions.txt` lists the apps whose iOS branches are the app. For each,
`scripts/ios-conditions.py` (run by `scripts/build-wasm.sh` for the Apps package, before every
build) writes `Apps/ios-sources/<app>`: the upstream tree with `os(iOS)` replaced by `true` in
`#if` and `#elseif` lines and nothing else (same files, same lines, so diagnostics keep their
line numbers; the copy is not committed). The app's target in `Apps/Package.swift` builds the
copy. `canImport` conditions still decide by what the SDK has, so `#if os(iOS) &&
canImport(ActivityKit)` stays out.

An app is listed when it needs it. The five apps already in the browser are not: their code
under `os(iOS)` is either absent or would bring in APIs they do not need here, and their pass
in CI is the measure.

## Consequences

The app's source is still upstream's, unchanged; what changes is the platform it is compiled
for, which is the platform it is written for. Diagnostics name `Apps/ios-sources/...` paths
with upstream's line numbers. A later step could do this for every app and drop the list.
