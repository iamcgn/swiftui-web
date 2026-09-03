# Open-source SwiftUI clone: browser (wasm + Canvas painter) first, native later

## Context

Goal: an open-source reimplementation of SwiftUI where **unmodified SwiftUI app source** (`import SwiftUI`, `@main struct MyApp: App`, `@State`, `ViewBuilder`, modifiers, etc.) compiles with the stock Swift toolchain and runs in a browser via WebAssembly with 1:1 rendering and behaviour fidelity, and later as a native macOS/Linux executable. SwiftUI is closed source, so fidelity is inferred from Apple's documentation plus black-box comparison against the real SwiftUI on the developer's Mac.

This plan sets up the **workflow** (toolchain, architecture, fidelity harness, per-element loop) and delivers the foundation plus the first elements. The full element library is built afterwards, one element per PR, using that loop.

### Key finding: no custom compiler is needed

"Compiling real SwiftUI code" only requires a Swift module that exposes SwiftUI's API surface. `@ViewBuilder` (result builders), `@State` (property wrappers) and `@Observable` (macro shipped with the toolchain in the stdlib `Observation` module) are language features the stock compiler already handles. Tokamak, OpenSwiftUI and SkipUI all work this way. What we build is a **library + runtime + painter backend**, not a compiler. The only compiler-plugin work is a `#Preview` macro so files containing previews still compile (Phase 3).

### Decisions made with the user (2026-09-01)

| Decision | Choice |
|---|---|
| Browser rendering | **Canvas painter**: Swift computes layout and emits a display list; Canvas2D paints it (WebGPU / Skia-wasm later, same display list). No CSS layout. |
| Starting point | **Fresh codebase**; borrow selectively with attribution (Tokamak Apache-2.0, ElementaryUI Apache-2.0, OpenSwiftUI MIT for inferred internals, SkipUI's support-matrix format). |
| Fidelity reference | **macOS SwiftUI look first** (goldens from this Mac); iOS later behind a platform profile. |
| Native executable | **WebView host first** (WKWebView / WebKitGTK loading the wasm bundle); a true native painter (CoreGraphics / Skia) is a later backend on the same display list. |

Assumptions (change any time): license Apache-2.0; working package name `SwiftUIWeb` (the app-facing module is literally `SwiftUI`); repo stays at `/Users/iamcgn/swiftui-to-html` and gets `git init`. Embedded Swift is out of scope (the SwiftUI API is existential/keypath/reflection heavy).

### Research summary (verified 2026-09-01)

- **Toolchain**: Swift 6.3.3 is the current release with the official Swift SDK for WebAssembly (target `wasm32-unknown-wasip1`). The SDK must exactly match a **swift.org toolchain installed via swiftly**; Apple's Xcode/CLT toolchain cannot use it. This Mac has Apple CLT Swift 6.2.3 only (no swiftly, no wasm SDK, no Xcode), but the CLT SDK includes the real `SwiftUI.framework`, so goldens can be generated from an offscreen hosted window (decision 0010: not `ImageRenderer`, whose default font differs).
- **JavaScriptKit** (min Swift 6.3) + **BridgeJS** typed glue + **PackageToJS** plugin (`swift package --swift-sdk <sdk> js`, with a test driver for swift-testing in Node/browser).
- **Prior art**: Tokamak archived Jan 2026 (Swift 5.6 era, CSS layout). OpenSwiftUI (MIT) is faithful but Apple-platform-focused on an incomplete OpenAttributeGraph, no wasm. ElementaryUI is SwiftUI-*inspired* HTML, not API compatible. **Flutter Web** is the precedent for canvas UI: hidden semantics DOM tree for accessibility, hidden input for IME.
- **Module naming**: on wasm/Linux a module named `SwiftUI` has no conflict. On macOS it collides with the system framework; SwiftPM `moduleAliases` platform conditions are ignored (swift-package-manager#7412) and `#if os()` in a manifest evaluates on the host. Handled by the thin-module hedge + separate harness package below.

## Architecture

```
App source (unchanged) ──import SwiftUI──▶ SwiftUI (thin: @_exported import SwiftUIWebCore, Foundation, Observation)
                                             │
                                   SwiftUIWebCore (API + runtime + layout + text + display list; `package` access)
                                             │ Renderer / TextMeasurer / HostEnvironment (package protocols)
              ┌──────────────────────────────┼──────────────────────────────┐
     SwiftUIWebCanvas (wasm)        SwiftUIWebHeadless (any OS)        SwiftUIWebNative (Phase 4)
  Canvas2D painter via BridgeJS,   records display list + frames     CoreGraphics / Skia painter,
  rAF loop, input events,          for tests; replays recorded       AppKit / GTK window
  a11y DOM overlay, hidden input   text metrics
```

### Repository layout

```
Package.swift (tools 6.1+), .swift-version = 6.3.3, LICENSE, README.md
Sources/SwiftUI/                 thin re-export module (hedge against macOS shadowing)
Sources/SwiftUIWebCore/          API/  Runtime/  Layout/  Text/  Display/  Platform/  Semantics/
Sources/SwiftUIWebCanvas/        wasm-only (JavaScriptKit dep gated `.when(platforms: [.wasi])`)
Sources/SwiftUIWebHeadless/      display-list recorder + RecordedTextMeasurer
Sources/SwiftUIWebTestSupport/   fixture registry, frames.json codec, comparison helpers
Tests/CoreRuntimeTests/          identity, state, invalidation (native, fast, blocking)
Tests/LayoutFidelityTests/       headless vs goldens (native, fast, blocking)
Tests/BrowserTests/              swift-testing under PackageToJS test driver (reporting first)
Fixtures/Sources/                fixture .swift files compiled by BOTH packages via symlink
Fixtures/Goldens/<fixture>/      frames.json, image@2x.png, meta.json  (committed; never regenerated in CI)
Harness/                         SEPARATE package, macOS only, imports Apple's SwiftUI, zero dependency on `/`
Examples/Counter/, Examples/Gallery/   wasm apps served by a static server / Vite
Docs/ARCHITECTURE.md, Docs/ELEMENT_WORKFLOW.md, Docs/decisions/NNNN-*.md, Docs/support.json → support-matrix.md
scripts/bootstrap.sh, gen-goldens.sh, build-wasm.sh, serve.sh
.github/workflows/ci.yml
```

Why: one core module keeps generic View machinery specialised (cross-module generics without `@inlinable` lose specialisation); `package` access (SE-0386) gives internal boundaries. The Harness must be a separate package so `import SwiftUI` there resolves to Apple's framework; fixtures are shared on the filesystem (`Harness/Sources/Fixtures -> ../../Fixtures/Sources`).

### Public API shape (mirrors Apple, including underscored hooks)

```swift
@MainActor @preconcurrency public protocol View {
    associatedtype Body: View
    @ViewBuilder @MainActor @preconcurrency var body: Body { get }
    static func _makeNode(_ context: _NodeContext<Self>) -> ViewNode   // hidden hook, default = CompositeNode<Self>
}
@resultBuilder public enum ViewBuilder { buildBlock<each C: View>(_: repeat each C) -> TupleView<(repeat each C)>; buildEither → _ConditionalContent; buildOptional; buildLimitedAvailability → AnyView }
public protocol DynamicProperty { mutating func update(); static func _install<V>(_: WritableKeyPath<V, Self>, into: DynamicPropertyStorage, node: ViewNode) }
public protocol Layout: Animatable { /* exactly Apple's: sizeThatFits/placeSubviews/spacing/explicitAlignment/makeCache */ }
```
`HStack/VStack/ZStack` are implemented as `HStackLayout/VStackLayout/ZStackLayout` so the `Layout` protocol is the single layout code path from day one. `View` is `@MainActor` from the start (Apple's since iOS 18); retrofitting breaks user code.

### Runtime: type-structured node tree, no AttributeGraph, no general diffing

- The `ViewNode` tree mirrors the **type** tree: `CompositeNode<V>` has one child of type `V.Body`; `TupleNode` has fixed N children; `ConditionalNode` identity is the branch (switching tears down state, as SwiftUI does); `OptionalNode`; `AnyViewNode` rebuilds when the dynamic type changes; `IDNode` rebuilds when the id changes. **Only `ForEachNode` reconciles by key** (moves preserve state).
- **View lists flatten**: `Group`, `ForEach`, `TupleView`, `Optional`, `_ConditionalContent`, `Section` contribute their children to the enclosing stack (`HStack { Group { A; B }; C }` = 3 children, 2 spacings). Phase 1 invariant with tests.
- `DynamicProperty` installation: per view type, discover stored properties via `_forEachFieldWithKeyPath` (verify on wasm in Phase 0), open the existential once, cache installer closures. `State` holds a `StateBox` installed on first appearance; later initial values are ignored; writes invalidate the owning node and coalesce into one flush.
- `@Observable`: wrap each body evaluation in `withObservationTracking`; `onChange` marks dirty and reschedules. Environment reads are recorded per evaluation the same way.
- Change detection to skip work: `_isPOD` bitwise compare, else `Equatable ==`, else assume changed (cached per type).
- `UpdateScheduler.flush()`: update top-down by depth → layout → preferences → emit one display list → paint inside `requestAnimationFrame`. Animation later slots in between layout and paint as per-frame interpolation of `Animatable` values.

### Layout engine (documented semantics, constants measured from goldens)

`ProposedViewSize` (`unspecified/zero/infinity/explicit` per dimension), leaf `sizeThatFits` (Text via TextMeasurer, Spacer, Color/Shape fill proposal with 10×10 for `.unspecified`, Image intrinsic), `frame` min/ideal/max clamping, `fixedSize`, `layoutPriority`, `padding` (default measured, expected 16), stacks with the "least flexible first" algorithm and priority groups, `ViewSpacing` (Text-to-Text spacing is font-derived, not 8: known trap, measure it), alignment guides / `ViewDimensions`, `ZStack`, `GeometryReader` + `coordinateSpace`, **pixel rounding to `displayScale` at placement**. Whole-tree relayout per flush first; memoise `sizeThatFits` by proposal later.

### Display list and Canvas painter

- `DisplayList` is a flat command encoding (opcodes + Float64 operands + interned strings/paths): `save/restore/concat/clipRect/clipRRect/clipPath/beginGroup(opacity, blend, shadow, cacheKey)/endGroup/fillRect/fillRRect/fillPath/strokePath/drawText(handle)/drawImage(handle)`. Wasm builds it; JS decodes it in **one call per frame** and issues Canvas2D calls (later: WebGPU or an optional CanvasKit module consume the same buffer; CoreGraphics/Skia consume it natively). Groups with opacity/shadow/blend render through an `OffscreenCanvas` (a `needsOffscreen` bit keeps the common single-fill case direct); `.continuous` corners are emitted as superellipse paths. Text and image handles are backend resources released on unmount.
- Canvas backing store = CSS size × `devicePixelRatio`, `setTransform(dpr…)`, all coordinates in points; frames are already pixel-rounded by layout; re-round and repaint on DPR/zoom change. Phase 1 does a full repaint per invalidated frame, but each painting node caches its own display-list fragment so damage rects and `cacheKey` layer caching (scroll content) can be enabled in Phase 2 without redesign.
- **Hit-testing entirely in Swift** from frames (`contentShape`, `allowsHitTesting`, `disabled`, gesture arena with SwiftUI precedence). One listener set on the canvas root (`pointer*` with capture, `wheel`, `keydown/up`, resize/DPR/`matchMedia` colour scheme) forwarded as `InputEvent` in points.
- **Text engine** (`TextEngine` protocol returning a retained `TextLayout` with lines and baselines): Canvas2D `measureText` for advances and vertical metrics, plus DOM-assisted line breaking (hidden element + `Range.getClientRects()` for the browser's break positions) instead of a hand-rolled UAX #14 breaker in Phase 1; LRU cache keyed by (string, font, width, options); first flush blocks until `FontFace.load()` completes. A Swift line breaker is added when CanvasKit/native parity requires it.
- **Fonts**: bundle **Inter** (OFL, variable) and use it on both sides for the deterministic fixture family (harness registers it via CoreText and applies it at the fixture root; web loads it via `@font-face`), so pixel goldens are meaningful. A second small "SF" fixture family has no font override and is compared with tolerance only on Apple hosts, where `-apple-system` in canvas is real SF. Never ship SF fonts or SF Symbols; `Image(systemName:)` maps to an OFL icon set and is flagged "approximate".
- **Accessibility**: semantics tree built after layout (roles, label/value/hint, actions, frames) → always-on transparent absolutely positioned DOM overlay with ARIA roles and `tabindex` (Flutter Web approach); AT activations dispatch actions back into Swift; browser focus and the Swift focus system are kept in sync. Cheap, and it lets Playwright click by role. Basic overlay lands with `Button` in Phase 1; full coverage in Phase 3. **Text input**: a real `<input>/<textarea>` in the overlay at the field's frame with transparent text/caret (so IME candidate windows anchor correctly); Swift paints text, caret and selection and mirrors selection into the element for native copy/paste. **Scrolling**: own implementation; desktop `wheel` deltas already carry OS momentum, touch uses UIScrollView-style deceleration and rubber-banding; content paints through a cached layer. Documented as unsupported by the canvas backend: find-in-page, print, native text selection on `Text` (added in Phase 3 via an overlay element).

### Fidelity harness: two tiers

- **Fixtures** are plain SwiftUI source (`Fixture("stack/hstack-basic", size: 400×300) { HStack { Text("A").probe("a"); Text("B") } }`). `.probe(id)` is defined on both sides purely from public API: `background(GeometryReader { Color.clear.preference(...) })` + root `coordinateSpace(name:)` + `onPreferenceChange`. This pulls GeometryReader/preferences into Phase 1 (fine, they're needed anyway). Behaviour fixtures declare `steps` that mutate an `@Observable` model between renders.
- **Determinism**: fixed root frame, `locale en_US`, `.colorScheme(.light)`, `.dynamicTypeSize(.large)`, animations disabled, `controlActiveState .key`, window rasterised at 2× (decision 0010), PNG converted to sRGB; `meta.json` records macOS/SwiftUI versions. Goldens are committed; regenerated only in deliberate PRs after OS updates.
- **Tier A, layout fidelity (blocking, exact, eps 0.01pt)**: the harness also dumps per-Text `(string, font, proposal) → (size, baselines, lineCount)`; native tests run the headless renderer with a `RecordedTextMeasurer` that replays them, isolating the layout engine from font shaping. Runs under plain `swift test` on macOS and Linux in milliseconds.
- **Tier B, browser/pixel fidelity (tolerance, reporting first)**: Playwright at `deviceScaleFactor: 2` renders the same fixtures; a BridgeJS debug export (`window.__swiftuiweb.debug.frames()`) returns probe frames and the current display list as JSON, compared with eps ~1pt (0.5pt widths, exact line counts for wrapped text), and screenshots go through an anti-aliasing-tolerant perceptual diff (target ≤ 0.5% differing pixels for the Inter family); promoted to blocking per fixture once stable. Also assert that the Canvas backend's display list is byte-identical to the headless recorder's for every fixture, and that the accessibility snapshot contains the expected roles/names.

### Platform profile

`PlatformProfile` (`.macOS` now, `.iOS` later) in the environment carries default padding, stack spacing, text-style sizes (macOS body 13 / iOS body 17, etc.), control geometry and **system colour tables** (`Color.blue`, `.primary`, `.accentColor` are per-platform, per-scheme values sampled from goldens). Optional Phase 0 experiment: build the harness for Mac Catalyst (`-target arm64-apple-ios26-macabi` against the CLT SDK's `iOSSupport`) to get iOS-styled goldens without Xcode; time-box one day, record the result.

## Phases

### Phase 0 — Toolchain, skeleton, spikes (about 1–2 weeks). Exit: every spike has a decision doc and `scripts/bootstrap.sh` reproduces the environment.

| # | Task | Done when |
|---|---|---|
| 0.1 | `brew install swiftly; swiftly init; swiftly install 6.3.3; swiftly use 6.3.3`; `swift sdk install <URL from swift.org/install/macos> --checksum <sha>`; `brew install binaryen`; check Node version needed by PackageToJS (Node 18 installed; use nodenv if 20+ required) | `swift build --swift-sdk swift-6.3.3-RELEASE_wasm` of hello-world runs under WasmKit; Apple CLT 6.2.3 still drives the Harness. |
| 0.2 | Package skeleton with all targets (empty), thin `SwiftUI`, `Examples/Counter` printing to console, `git init`, LICENSE, README, Docs skeleton, `Docs/support.json` + generator script | Builds for macOS (swiftly toolchain), Linux (`docker run swift:6.3.3`), wasm. |
| 0.3 | **Spike: module shadowing** | A test doing `import SwiftUI; _ = SwiftUIWebMarker()` passes on macOS with both toolchains. If not, tests import `SwiftUIWebCore` directly. `Docs/decisions/0001-module-name.md`. |
| 0.4 | **Spike: reflection & observation on wasm**: `_forEachFieldWithKeyPath`, `Mirror`, `_openExistential`, `withObservationTracking`, `AnyHashable`; which module vends `CGFloat/CGRect` in the wasm SDK (`Foundation` vs `FoundationEssentials`) | A wasm test discovers a `State<Int>` field by key path, installs a box, and an `@Observable` mutation fires `onChange`. Gates the runtime design; fallback is a registration macro (much worse, so verify first). |
| 0.5 | **Spike: canvas hello + display list**: BridgeJS, DPR-correct canvas, decode a `Float64Array` display list in one JS call, paint 3,000 rounded rects + 500 `fillText` runs per frame at DPR 2, one `OffscreenCanvas` group, `measureText` × 1,000, receive a click, rAF loop | Decode + paint < 4 ms/frame, measure < 3 ms recorded; BridgeJS vs raw JavaScriptKit decided for the applier. `Docs/decisions/0002-display-list.md`. |
| 0.11 | **Spike: font pipeline**: bundle Inter, `FontFace.load()` before first paint, compare `measureText("Hello, World")` at 13pt in Chrome/Safari/Firefox against CoreText with the same file | Deltas recorded; Tier B width tolerance set from them. |
| 0.12 | **Spike: semantics overlay + IME**: 200 overlay nodes with `tabindex` over a canvas; VoiceOver reads roles/labels and Tab order; a transparent `<input>` over the canvas receives composition events with a Japanese input source | Recorded works/limits in a decision doc. |
| 0.13 | **Spike: CanvasKit sizing**: load CanvasKit next to hello-world wasm; record bundle size and startup | Decides when (not whether) to offer the optional CanvasKit painter. |
| 0.6 | **Spike: swift-testing on wasm** via `swift package --swift-sdk … js test` (Node) and browser (Playwright) | One test passes in Node and headless Chromium in CI. |
| 0.7 | **Spike: binary size** with/without Foundation, `-Osize`, `wasm-opt -Oz`, brotli | Baseline recorded; budget set (e.g. ≤ 4 MB brotli for Counter) and a CI size gate. |
| 0.8 | Harness skeleton: `swift run GoldenGen` renders `Text("Hello")` via `ImageRenderer` from a CLI process, writes PNG + `frames.json` + `meta.json` with a GeometryReader probe and text metrics | Files produced; fixture lives in `Fixtures/Sources` via symlink. |
| 0.9 | CI matrix: macOS (native tests), Linux (native tests + wasm build + Node tests), browser job (Playwright); wasm artifact + size check | Green on the empty suite. |
| 0.10 | Optional: Catalyst goldens experiment | Recorded works/doesn't in a decision doc. |


### Phase 0 status (2026-09-01)

| # | Task | Status |
|---|---|---|
| 0.1 | Toolchain (swiftly 6.3.3, wasm SDK, binaryen) | done; `scripts/bootstrap.sh`, `scripts/env.sh` (decision 0003) |
| 0.2 | Package skeleton, docs, example, harness | done (this repo) |
| 0.3 | Module shadowing | done: our `SwiftUI` wins on macOS (decision 0001) |
| 0.4 | Reflection + observation on wasm | done: all 7 spike tests pass natively and on wasm (decision 0004) |
| 0.5 | Canvas display list | done: 3,000 rects + 500 texts = 6 ms paint / 7.2 ms total per frame in headless Chromium at DPR 2 (decision 0002) |
| 0.6 | swift-testing on wasm | done under Node via `js test --disable-sandbox`; browser runner in `Playwright/` (Tier B wiring in Phase 1) |
| 0.7 | Binary size | done: 1.0 MB brotli without Foundation, 12 MB with it (decision 0006) |
| 0.8 | Golden generator | done: `Fixtures/Goldens/text/hello` from Apple's SwiftUI 7.2.5 on macOS 26.2 |
| 0.9 | CI | workflow written (`.github/workflows/ci.yml`), not yet run (no remote) |
| 0.10 | Catalyst goldens experiment | not started |
| 0.11 | Font pipeline | done: Canvas widths identical to CoreText on macOS (decision 0005) |
| 0.12 | Semantics overlay + IME | not started (needs manual VoiceOver / IME session) |
| 0.13 | CanvasKit sizing | not measured |

### Phase 1 — Core runtime, layout, canvas painter, harness loop (about 4–6 weeks). Each step is a PR with tests.

1. API skeleton: `View`, `Never: View`, `ViewBuilder` (parameter packs), `EmptyView`, `TupleView`, `_ConditionalContent`, `Optional`, `Group`, `AnyView`, `ModifiedContent`, `ViewModifier`, `EnvironmentValues`/`EnvironmentKey`/`@Environment`, `Transaction` stub. Acceptance: a body with `if/else`, optionals, `Group` and 12 children type-checks.
2. Node tree: `ViewNode` family, `_makeNode` dispatch, `layoutChildren` flattening, `UpdateScheduler`. Tests: tree shape and flattening counts.
3. `DynamicProperty` + `State` + `Binding` (+ `$` projection), coalesced flush. Tests: state survives parent re-evaluation; resets on branch switch and `.id`; two writes → one flush.
4. `@Observable` tracking, `@Environment(Type.self)`, `@Bindable`. Tests: mutation invalidates only reading nodes.
5. Layout core: `ProposedViewSize`, `ViewDimensions`, alignments, `ViewSpacing`, `Layout` protocol + `LayoutSubviews`, `frame`, `padding`, `fixedSize`, `layoutPriority`, `HStackLayout/VStackLayout/ZStackLayout`, `Spacer`, `Divider`, pixel rounding.
6. Text (static): `Text(String)`, basic `LocalizedStringKey` incl. interpolation overloads, `Font` (`.system(size:weight:design:)`, text styles), `foregroundStyle/foregroundColor`, `TextMeasurer`, `RecordedTextMeasurer`, macOS metric table.
7. Paint modifiers: `background` (view + `ShapeStyle`), `overlay`, `Color` + system colour table, `opacity`, `clipShape`/`cornerRadius`, `Rectangle/RoundedRectangle/Circle` fill-only.
8. Preferences, `GeometryReader`, `coordinateSpace` (needed by probes).
9. Headless renderer + `LayoutFidelityTests` against `Fixtures/Goldens`. Acceptance: first 20 fixtures exact on macOS and Linux.
10. Core protocols `DisplayList`/`Painter`/`TextEngine`/`SemanticsHost`/`TextInputHost`; `SwiftUIWebCanvas`: `CanvasHost` (DPR, resize, rAF, events), `Canvas2DPainter` (all ops incl. offscreen groups, gradients, shadows, clip), `Canvas2DTextEngine` (measureText + DOM-assisted breaks + cache), `DOMSemanticsHost`, FontFace loading.
11. `Button` (`Button(action:label:)`, `Button("Title") {}`, macOS bordered default geometry from goldens, `.plain/.bordered/.borderless`), Swift `HitTester` + tap gesture arena, semantics role with keyboard activation through the overlay, `onTapGesture` minimal.
12. `App`/`Scene`/`WindowGroup`/`App.main()` (installs `JavaScriptEventLoop`, awaits fonts, creates canvas + overlay, mounts the first `WindowGroup`); `@_exported import Foundation`/`Observation` in the thin module; `Examples/Counter` in a browser; `scripts/build-wasm.sh` + `serve.sh`.
13. Browser Tier B job (Playwright at DPR 2): `debug.frames()` comparison, screenshots + perceptual diff reporting, accessibility snapshot check, display-list identity check against headless.
14. Support matrix v1 from `support.json`; `Docs/decisions` for module naming, display list, text tiers, platform profile.

Phase 1 done: Counter (`@main App`, `@State`, `VStack/HStack/Text/Button/Spacer/padding/frame/background`) builds unmodified with `swift package --swift-sdk … js` and runs in Chrome, Safari and Firefox with working clicks, keyboard and VoiceOver; ≥ 30 layout fixtures exact in Tier A on macOS + Linux; Tier B within tolerance and Inter-family pixel diff ≤ 0.5% on the macOS runner; Canvas and headless display lists identical; runtime semantics covered by `CoreRuntimeTests`; bundle within the size budget.

### Phase 1 status

| # | Step | Status |
|---|---|---|
| 1 | API skeleton | done 2026-09-02: `Sources/SwiftUIWebCore/API/`, `Tests/CoreRuntimeTests/ViewBuilderTests.swift`. Library view types conform to `View` in extensions so their inits stay nonisolated and the nonisolated `ViewBuilder` can construct them under Swift 6 strict concurrency. |
| 2 | Node tree | done 2026-09-02: `Sources/SwiftUIWebCore/Runtime/` (`ViewNode`/`TypedNode<V>`, `CompositeNode`, `LeafNode`, `TupleNode` via cached tuple key paths, `ConditionalNode`, `OptionalNode`, `GroupNode`, `AnyViewNode`, `ModifierBodyNode` + `ModifierContentNode`, `EnvironmentModifierNode`, `Runtime`/`RootNode`, `UpdateScheduler`). `View._makeNode` and `ViewModifier._makeNode` are protocol requirements (hidden, underscored) so primitives dispatch statically. `EnvironmentValues.generation` lets unchanged subtrees skip re-evaluation. Tests: `NodeTreeTests` (tree dumps, flattening counts, branch/optional/AnyView teardown, modifier placeholders, scheduler coalescing). |
| 3 | DynamicProperty + State + Binding | done 2026-09-02: `_DynamicPropertyFields<Root>` (cached key-path discovery, opened once per field), `DynamicPropertyStorage` slots per composite/modifier node, `State`/`StateBox` (nonisolated accessors like Apple's; box hops to the main actor to invalidate), `Binding` (projections, collections), `IDView`/`IDNode`, `@Environment` resolved at install, nested `DynamicProperty` with `update()`. Tests: `StateTests`. |
| 4 | @Observable, @Environment(Type.self), @Bindable | done 2026-09-02: each body evaluation runs in `withObservationTracking`; `onChange` (fires in `willSet`) hops to the main actor and invalidates the node only if the session is still current (`ObservationToken`). `EnvironmentValues[objectType]`, `.environment(object)`, `_EnvironmentObjectWritingModifier`. Tests: `ObservationTests`. |
| 5 | Layout core | done 2026-09-02: `Layout/` (ProposedViewSize, alignments, ViewDimensions with lazy explicit guides, ViewSpacing with spacing categories, `Layout` protocol + LayoutSubviews, H/V/ZStackLayout), `Runtime/LayoutNodes.swift` (LayoutContainerNode, UnaryLayoutModifierNode that distributes over lists via proxies, frame/flex-frame/padding/fixedSize/priority/alignmentGuide/layoutValue nodes, Spacer/Divider/Color), per-pass size cache, `Runtime.layout(in:)`, `_probe` debug modifier. Geometry types own on wasm (decision 0006). **Golden loop pulled forward:** `Sources/FixtureKit` twin + `SwiftUIWebFixtures` target compile the shared fixture sources; `LayoutFidelityTests/GoldenFrameTests` compares frames exactly: 21/21 layout fixtures match macOS 26.2 (`Docs/elements/Layout.md`). |
| 6 | Text (static) | done 2026-09-02: `Text` (verbatim/localized/interpolation/concatenation, bold/fontWeight/italic/foregroundColor), `Font` (styles, system sizes, weights, designs, modifiers), `PlatformProfile.macOS` text-style table, `TextEngine`/`FontMetrics`/`TextLayout`, `TextNode` (wrapping at the proposal, baselines as explicit guides, font-derived spacing categories), `RecordedTextEngine` in Headless replaying `Fixtures/Goldens/text-metrics.json`. Harness measures every fixture string (plus zero-width minimum) and per-font spacing. 9 text fixtures exact (`Docs/elements/Text.md`). Thin module re-exports FoundationEssentials on wasm (CGRect ambiguity found by the wasm run). |
| 7 | Paint modifiers | done 2026-09-02: `Display/` (`DisplayList`/`DisplayCommand`, `RGBA`, `PaintContext` with per-edge pixel rounding, `Runtime.render(scale:)`), `Shapes/` (`Path`, `Shape`, Rectangle/RoundedRectangle/Circle/Ellipse/Capsule, `fill`/`stroke`, `_ShapeView`), macOS light colour table sampled from goldens, `background`/`overlay` (view, style, shape forms via `LayeredNode`), `opacity`, `clipShape`/`clipped`/`cornerRadius`, text painting. Tests: `PaintTests`; 4 paint fixtures exact (`Docs/elements/Paint.md`). 34/34 fixtures exact. |
| 8 | Preferences, GeometryReader, coordinateSpace | done 2026-09-02: `PreferenceKey`, `preference`/`transformPreference`/`onPreferenceChange` (bottom-up reduction over structural children, writes replace subtrees, observers run after every layout pass), `GeometryReader`/`GeometryProxy` (content built during layout; local/global/named frames, `bounds(of:)`), `coordinateSpace(name:)`. FixtureKit's `probe` is now the same GeometryReader+preference code as the Apple harness, so all 34 fixtures validate that chain. Tests: `PreferenceTests`. |
| 9 | Headless renderer + LayoutFidelityTests | done 2026-09-02 (pulled forward in steps 5–7): `RecordedTextEngine`, `HeadlessRenderer`, `GoldenFrameTests` exact on 34 fixtures (macOS; Linux via CI once a remote exists). |
| 11 | Button (done before 10) | done 2026-09-02: `Button` + `ButtonStyle` (bordered/prominent/borderless/plain/custom), `_ButtonHost` press state, Swift hit testing (`Runtime.pointerDown/Up`, deepest interactive node wins), `onTapGesture`, `semanticsTree()`/`activate(semanticsIdentifier:)`. Geometry and colours from `button/*` goldens (`Docs/elements/Button.md`). Also `App`/`Scene`/`WindowGroup`/`SceneBuilder` API (step 12 part) and the flat `DisplayListEncoder` + `SystemFontMetrics` table (step 10 part). Reflection switched to `_forEachField` offsets because key-path reflection rejects closure fields. 36/36 fixtures exact. |
| 10 | Canvas backend | done 2026-09-02: `SwiftUIWebCanvas` — `CanvasHost` (DPR canvas, ResizeObserver, rAF loop coalescing invalidations, pointer capture, DOM button overlay with click/keyboard activation, `window.__swiftuiwebDebug`), injected Canvas2D decoder (`PainterScript`), `Canvas2DTextEngine` (measureText + measured font table + SwiftUI's trailing-space wrapping rule). Decision 0007. |
| 12 | App / Counter in the browser | done 2026-09-02: `App.main()` in the thin module launches `CanvasHost`; `Examples/Counter` builds unmodified (`scripts/build-wasm.sh Examples/Counter`) and `Playwright/counter.mjs` verifies first paint, click and keyboard activation in headless Chromium. |
| 13 | Browser Tier B | done 2026-09-02: `Examples/Gallery` mounts any fixture; `scripts/tier-b.sh` + `Playwright/tier-b.mjs` compare probe frames (exact for layout/paint/button, 3 % for text) and pixels vs goldens: 36/36 pass, layout fixtures pixel-identical (decision 0008). WebKit 36/36, Firefox 35/36 exact frames; Counter smoke test green in Chromium, WebKit and Firefox (`scripts/browser-smoke.sh`). Release Counter bundle 1.15 MB brotli (budget 3 MB). |
| 14 | Support matrix, decisions | done 2026-09-02: `Docs/support-matrix.md` regenerated each step; decisions 0007–0009. |

**Phase 1 exit check (2026-09-02):** Counter builds unmodified and runs in Chromium, WebKit and Firefox with working clicks and keyboard activation through the overlay (VoiceOver not yet checked by hand); 36 fixtures exact in Tier A on macOS (Linux pending CI); Tier B within tolerance in all three engines; canvas and headless display lists come from the same code path (identity test still to add); runtime semantics covered by `CoreRuntimeTests`; bundle within budget. Open: CI has never run (no remote), VoiceOver/IME session (spike 0.12), Linux native run.

### Phase 2 — Element workflow, one element per PR (`Docs/ELEMENT_WORKFLOW.md`)

Per element: (1) `Docs/elements/<Element>.md` with the API surface from Apple docs, documented behaviours, constants to infer; (2) fixtures under `Fixtures/Sources/<Element>/` (≥ 5 layout fixtures, a behaviour fixture where applicable); (3) `scripts/gen-goldens.sh <Element>` on the Mac, commit goldens; (4) implement API + runtime/layout/paint; (5) `swift test --filter <Element>` exact, wasm build green, browser Tier B within tolerance, gallery page added with a screenshot in the PR; (6) `support.json` updated honestly (full / partial / approximate / stub / missing) and matrix regenerated; measured constants recorded in the element doc.

Order (each unlocks the next): `ForEach` + `Section` (keyed reconciliation, `Identifiable`, `id:`) → `Text` completeness (concatenation, `lineLimit`, `multilineTextAlignment`, `truncationMode`, baseline alignment, wrapped-paragraph fixtures) → `ScrollView` (own physics; drives damage rects and layer caching) → `Image` (async `ImageHandle` load that invalidates layout; `systemName` via icon table) → `Shape`/`Path`/`stroke`/`fill`/`Capsule`/`Ellipse`/`border` → `Toggle` + `Label` → `TextField`/`SecureField` (`TextInputHost`, IME, painted caret and selection) → `List` (macOS inset/plain styles) → `NavigationStack`/`NavigationLink`/`navigationTitle`/`navigationDestination` → `Picker`/`Slider`/`Stepper` → `Form` → `.onAppear/.onDisappear/.task` (cancellation via JS event loop) → animation (`withAnimation`, `.animation`, transitions) → `sheet`/`popover` → custom `Layout` → `Grid` → `Canvas`.

### Phase 2 status

| Element | Status |
|---|---|
| ForEach + Section | done 2026-09-02: `API/ForEach.swift`, `API/Section.swift`, `Runtime/CollectionNodes.swift` (keyed `ForEachNode`, `SectionNode`), `CoreRuntimeTests/ForEachTests`; 14 fixtures exact incl. the 4-step `foreach/identity` behaviour fixture (`Docs/elements/ForEach.md`). Along the way: **behaviour fixtures** (`Fixture(name, model:steps:content:)`, `FixtureRunner`, per-step goldens, gallery `__galleryStep`, Tier B per step) and **decision 0010**: goldens now come from a key hosted window (frames *and* pixels), which showed the default font is the 13 pt system font (16 pt line), not `.body`; `bold()` is a per-text-style trait (`text/bold-trait`). Tier B (Chromium) 55/55 renders within tolerance after fixing painting modifiers on lists (proxies now paint through `paintTarget`) and generating the canvas font table from the recorded metrics (`scripts/font-metrics-table.py`). WebKit 55/55; Firefox 53/55: `section/title` and `section/foreach` are off by 0.25 pt in x because Firefox measures "Vegetables" 0.5 pt wider (same glyph-hinting class as in Phase 1). |
| Text completeness | done 2026-09-02: `Text + Text` with mixed fonts/weights/traits/colours (`Text.parts`, `StyledRun`, per-run fragments in `TextLayout`), `lineLimit` (all overloads; lower bounds reserve lines), `truncationMode`, `multilineTextAlignment`, `lineSpacing`, hard newlines, character wrapping; `TextLayouter` in core holds the measured rules (hanging trailing spaces, two-line balance against a lone last word, per-font `linePitch`/`unroundedLineHeight` with `pitch = max(linePitch, unrounded + spacing)`, character-granular truncation dropping spaces at the ellipsis) and is unit-tested with a synthetic measurer (`TextLayoutTests`); recorded keys gain option and `rich:` slots; the harness records mixed-font requests, their parts and per-font pitches. 7 new fixtures, 17 text fixtures exact in Tier A (`Docs/elements/Text.md`). Rules were pinned with a hosted `NSHostingView` sweep (0.5 pt steps) after the goldens contradicted the greedy model. Tier B (Chromium) 62/62 renders within tolerance, every text fixture with exact frames. WebKit 62/62 (most text fixtures pixel-identical, worst 1.05 %); Firefox 60/62 with every text fixture passing (the two failures are the known `section/title`/`section/foreach` 0.25 pt shift from "Vegetables" measuring 0.5 pt wider). Open: text under height pressure (fewer lines + truncation), middle-truncation balancing, `kerning`/`tracking`, attributed strings. |
| ScrollView | done 2026-09-02: `API/ScrollView.swift` (ScrollView, ScrollViewReader/ScrollViewProxy, scrollIndicators/scrollDisabled/scrollBounceBehavior/scrollClipDisabled/defaultScrollAnchor), `API/OnChange.swift`, `Runtime/ScrollNodes.swift` (`ScrollNode`: implicit VStack content, flexible along its axes and exactly content-sized across them, clipping, clamped offset, `scrollTo` resolved at layout; wheel scrolling with chaining to enclosing scroll views, touch pan with slop and 0.998/ms momentum, overlay indicators while scrolling), scheduler action queue for `onChange`, `Runtime.requestLayout` for geometry-only changes; the canvas host consumes non-passive wheel events and advances scroll animations per frame. 14 fixtures exact in Tier A incl. the 4-step `scroll/scroll-to` behaviour fixture (`Docs/elements/ScrollView.md`); Tier B 17/17 renders in Chromium (≤ 0.63 %), WebKit (≤ 0.2 %) and Firefox (≤ 1.09 %). Every scrolled frame runs a full layout pass: 8.3 ms median for 500 rows in a release build (`Playwright/scroll-probe.mjs`), so damage rects and content layer caching are deferred until content in the thousands of rows needs them. Open: bounce/rubber band, keyboard scrolling, `scrollPosition`/`scrollTargetBehavior`, `contentMargins`, lazy stacks. |
| Image | done 2026-09-02: images come from **Xcode asset catalogs** read at build time (`scripts/assets.py`, decision 0011: SwiftUI resolves named images only from a compiled `.car`, so the harness `FixtureKit` shadows `Image(_:)`/`Color(_:)` and feeds SwiftUI a `CGImage` from `Fixtures/Assets.xcassets`). `API/Image.swift` (`Image(_:bundle:)`, `resizable(capInsets:resizingMode:)`, `renderingMode`, `interpolation`, `aspectRatio`/`scaledToFit`/`scaledToFill`, `Color(_:bundle:)`, `ColorScheme`), `Display/AssetCatalog.swift` (variants by scale, idiom and appearance), `Runtime/ImageNodes.swift` (`ImageNode`, `AspectRatioNode`), `drawImage` display command with cap insets, tiling and tint; the canvas painter loads files lazily and repaints when they arrive; `scripts/build-wasm.sh` emits `assets/manifest.js` + files into the bundle. 8 fixtures exact in Tier A incl. the 3-step `image/swap`; Tier B exact frames and ≤ 0.5 % pixels in all three browsers (`image/tiling` 1.6 %: AppKit drops the bottom row of a tiled nine-part draw, we draw it). `Image(systemName:)` is a stub. Open: SF Symbols icon table, PDF/SVG sets, catalog slicing, dark-appearance goldens, `AsyncImage`. |
| Shape / Path | done 2026-09-02: `Shapes/Path.swift` (arcs, rounded rects, `description`/`init?(_:)` in Apple's format, `contains`, `trimmedPath`, `strokedPath`), `Shapes/RoundedCorners.swift` (circular and **continuous** corner geometry, uneven radii limits, all measured from Apple's paths), `Shapes/Shape.swift` (`StrokeStyle`, `FillStyle`, `ShapeView` with `FillShapeView`/`StrokeShapeView`/`StrokeBorderShapeView` chaining, `InsettableShape`), `Shapes/BuiltinShapes.swift` (+ `UnevenRoundedRectangle`, `AnyShape`, `ContainerRelativeShape`), `Shapes/ShapeModifiers.swift` (trim/offset/scale/rotation/transform/size/stroke as shapes), `Geometry/Angle.swift`, `View.border`; the `strokePath` command carries caps, joins, miter limit and dashes, `fillPath`/`clipPath` an even-odd flag. **Path goldens**: `PathRequests` (74 paths) recorded from Apple's `Path.description` into `shape/paths.json`, compared element for element (`PathGoldenTests`). 7 fixtures exact in Tier A incl. the 3-step `shape/steps` (`Docs/elements/Shape.md`); Tier B frames exact in all three browsers, pixels ≤ 1.4 % Chromium, ≤ 0.11 % WebKit, ≤ 1.2 % Firefox. Found: only `trim` and `stroke` lay out like the base shape; a `Path` view is in local coordinates; wasi-libc's `sin`/`cos`/`acos` trap like `pow`, so `Geometry/Math.swift` carries series implementations for wasm. Open: shape boolean operations, true offset outlines for `strokedPath`, gradients as shape styles. |

### Phase 3 — Compatibility and accessibility

Semantics tree → ARIA DOM overlay; `@FocusState`, keyboard navigation, text selection, VoiceOver checks in Safari. Minimal in-house `ObservableObject`/`@Published`/`@StateObject`/`@ObservedObject` (Combine is absent on wasm/Linux; ~200 lines, no OpenCombine dependency). `#Preview` macro plugin that expands to nothing (prebuilt swift-syntax). `TimelineView`/timers via renderer hooks (Foundation `Timer`/`RunLoop` do not fire on wasm; document it).

### Phase 4 — Native executables

1. `Tools/Host`: Swift executable embedding WKWebView (macOS) / WebKitGTK (Linux) that serves and loads a built wasm bundle: `swift run swiftui-host <bundle-dir>`.
2. `SwiftUIWebNative`: CoreGraphics painter (macOS) and Skia or Cairo painter (Linux) consuming the same display list; AppKit/GTK windowing and input. Layout and runtime unchanged.
3. iOS platform profile + goldens once Xcode (or the Catalyst trick) is available; touch devices default to `.iOS`.

## Risk register

| Risk | Mitigation |
|---|---|
| Reflection (`_forEachFieldWithKeyPath`) unavailable on wasm | Spike 0.4 gates the design; fallback registration macro. |
| `SwiftUI` module resolves to Apple's on macOS | Thin re-export hedge; tests can import `SwiftUIWebCore`; harness is a separate package regardless. |
| wasm size (Foundation + reflection metadata + Observation) | Budget + CI gate; keep `Foundation` out of hot paths; `-Osize`, wasm-opt, brotli. |
| JS bridging cost per draw call | Flat display list, one call per frame (spike 0.5). |
| Text metrics: CoreText vs Canvas2D, non-Apple fonts | Tier A recorded metrics (exact) vs Tier B tolerance; Inter with metric overrides; own line breaker. |
| Undocumented constants (spacing, padding, control geometry, scroll physics, animation curves) | Every constant is a fixture-backed measurement recorded in `Docs/elements/*.md`; borrow reverse-engineered knowledge from OpenSwiftUI/Tokamak with attribution. |
| Canvas accessibility gap | Always-on semantics overlay from Phase 1 (`Button`), full coverage in Phase 3; accessibility snapshot assertions per fixture. |
| Line-breaking parity (DOM-assisted breaks vs CoreText) | Wrapped-paragraph fixtures early; exact line count, 0.5pt widths; Swift UAX #14 breaker for CanvasKit/native parity. |
| Canvas text quality differs across browsers (AA on transparent canvas, Firefox hinting) | Paint text over opaque layers where possible; per-browser status in the matrix; optional CanvasKit for parity. |
| Group compositing cost (opacity/shadow/blend via OffscreenCanvas) | `needsOffscreen` fast path, layer caching, budget from spike 0.5. |
| IME/autofill/password managers with a transparent input | Keep the input real and positioned, never `display:none`; test Japanese/Chinese IMEs and Safari autofill (spike 0.12). |
| Golden drift on macOS updates | `meta.json` per golden; regenerate only in deliberate PRs. |
| Toolchain drift | Pin `.swift-version`, SDK version and CI images together. |

## Verification

- Phase 0: `swift build --swift-sdk swift-6.3.3-RELEASE_wasm` succeeds; the canvas spike renders rects + text in Chrome and Safari (screenshot via the Chrome tools); `swift test` passes natively and under the wasm test driver; `swift run GoldenGen` writes a PNG showing real SwiftUI output; CI green on all three jobs.
- Phase 1: Counter source builds unmodified and runs in three browsers; `swift test` layout comparisons exact against committed goldens; gallery shows working button clicks; size gate passes.
- Every element PR: fixtures, goldens, exact Tier A, tolerant Tier B, support-matrix entry, gallery page, browser screenshot.
