# 0023 — An Objective-C runtime for wasm, and a toolchain with interop on

Date: 2026-10-14
Status: **working on one machine; not yet in CI** — the SDK is built locally, not published.

## The requirement

Decision 0021 left SwiftUI-2048 at "every file but `AppDelegate.swift`": `@objc func newGame`
and `#selector(newGame(_:))` cannot compile for wasm because the wasm Swift compiler and
standard library are built without Objective-C interop, and forcing `-enable-objc-interop`
aborted the frontend. Route 1 of that decision — a runtime for wasm and a toolchain built
with interop on — is now built, in a sibling project:
[`~/Development/swift-objc-wasm`](../../../Development/swift-objc-wasm) (its `PLAN.md` and
`README.md` are the authority on the toolchain side).

## What was chosen (the model from the swift.org interop thread)

The Darwin model, kept whole: every Swift class is an Objective-C class, `NSObject` is the
root, the compilers keep emitting Apple's objc4-format class metadata, and a new runtime
(`libobjc-wasm`, C with a Foundation-lite `NSObject`) implements the objc4 ABI and API on
`wasm32-unknown-wasip1`. GNUstep's libobjc2 was not used: it would need a different metadata
emitter in the Swift compiler and its class layout conflicts with Swift's.

Two facts shaped the compiler patches. The abort was clang's section-name switch
(`CGObjCCommonMac::GetSectionName`) having no WebAssembly case. And WebAssembly type-checks
every indirect call, so `objc_msgSend` cannot exist: both compilers now emit
`IMP imp = objc_msgLookup(receiver, selector)` followed by a call with the message's own
signature (clang adds a nil-receiver skip). Metadata is found through `__start_`/`__stop_`
section symbols; lists are marked `llvm.used` so `wasm-ld --gc-sections` keeps them.

## What this package does with it

- `scripts/build-wasm.sh` honours `SWIFTUIWEB_WASM_SDK` (`swift-6.3.3-RELEASE_wasm-objc`
  for the apps that need `@objc`). The stock SDK keeps working for everything else: every
  change is behind `canImport(ObjectiveC)`.
- `WebFoundation` re-exports the `ObjectiveC` module on wasm when the SDK has one, so
  `Selector`, `NSObject` and `NSObjectProtocol` are the real ones; the stand-ins stay for
  builds without a runtime. Guards that meant "Apple's Foundation" (`NSItemProvider`,
  `NSUserActivity`, the pasteboard and drag providers) now say `canImport(Darwin)`.
  `NSStringFromClass`/`NSClassFromString` exist on wasm with the runtime.
- `UIResponder` is rooted at `NSObject` (`UIResponderBase`), so `responds(to:)`,
  `perform(_:with:)` and target-action work on every responder; its standard edit actions are
  `@objc`. `canPerformAction(_:withSender:)`, `target(forAction:withSender:)`,
  `buildMenu(with:)` and `validate(_:)` are added.
- `UICommand` (selector actions) is `UIKeyCommand`'s superclass; `UIKeyCommand` keeps the
  closure form and gains UIKit's selector initializers. A key command's selector is sent
  down the responder chain from the key responder, the application and the app delegate last
  (Events/Keyboard.swift).
- `UIMenuSystem.main` and `UIMenuBuilder` (Containers/MenuBuilder.swift): the standard menus
  (`UIMenu.Identifier.file`, `.edit`, `.format`, `.view`, `.window`, `.help`, …) are built once
  the app has launched, through `buildMenu(with:)` on the application and the delegate; their
  key commands are matched after the responder chain's own. A page has no menu bar to show.
- `UIApplicationDelegate` has no `init()` requirement with the runtime: the launch
  instantiates the delegate class as UIKit does, and `UIApplicationMain(_:_:_:_:)` (what
  `@UIApplicationMain` expands to; the compiler is patched to call a Swift one when there is
  no Foundation `NSString`) resolves the class by name.
- `UIScene`'s identity `Hashable` comes from `NSObject` with the runtime.

## Evidence

`Playwright/2048-probe.mjs` against `scripts/build-wasm.sh Apps --debug --product SwiftUI2048`
with `SWIFTUIWEB_WASM_SDK=swift-6.3.3-RELEASE_wasm-objc`: the unmodified app launches (the
title and two starting tiles), four swipes move the tiles, ⌘N starts a new game (two tiles
again), no console or page errors — `full_app_pass: true` (2026-10-14, report under
`.build/apps/2048`). Native macOS: the root suite (606 tests) and UIKitWeb's (193) pass; the
stock wasm SDK still builds `SwiftUIWebCanvas`.

## Limits, in the order they will matter

- The SDK is local. CI keeps the stock SDK until the bundle is published; the 2048 step is
  not in `ci.yml` yet.
- No bridging of `String`, `Array`, `Dictionary` or `Error` to Foundation classes without a
  Foundation (`String as NSString` is a compile error), no Objective-C exceptions, no
  corelibs Foundation, XCTest or Swift Testing in the interop SDK, single-threaded only.
- `#selector`-based `UIKeyCommand`s do nothing on builds without the runtime; the closure
  form works everywhere.
