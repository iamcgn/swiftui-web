# 0014 — UIKitWeb: a shared graphics substrate, a UIKit reimplementation, and the representables

Status: accepted (2026-09-06); Phases 0 to 3 done; Phase 4 (the larger UIKit classes) in progress

## Context

`UIViewRepresentable` and `UIViewControllerRepresentable` are the last large piece of the iOS
API surface an unmodified app source can hit. Supporting them means a `UIView` to represent:
a UIKit reimplementation that runs where SwiftUIWeb runs (wasm, macOS native, Linux headless),
built the way SwiftUIWeb was (decision 0001: an app-facing module with Apple's name; 0002: the
display list as the seam; 0010/0013: goldens from Apple's own frameworks). The user asked for
UIKitWeb as its own package that works independently, so a UIKit-only app can use it without
SwiftUI.

## Constraints that shape the layout

- **One `CGRect`.** On wasm there is no CoreGraphics: `Geometry/CGTypes.swift` defines `CGFloat`,
  `CGRect`, `CGAffineTransform` and friends. A UIKitWeb with its own copies would give an app
  that imports both frameworks two incompatible `CGRect` types, and a representable's `frame`
  would not type-check. The geometry has to live below both frameworks.
- **The package graph has one legal direction.** Apps get `UIViewRepresentable` from
  `import SwiftUI`, so the `SwiftUI` module depends on the `UIKit` module. SwiftPM forbids
  cycles, so UIKitWeb can never depend on the SwiftUIWeb package: everything both need
  (geometry, paths, the display list, text measuring and the measured tables, the hosts) must
  sit in a package below both.
- **`package` access stops at a package boundary.** What moves down becomes `public`; the
  substrate is a real API, the one UIKitWeb is written against.
- A module named `UIKit` shadows nothing on macOS, wasm or Linux: the macOS SDK the swiftly
  toolchain uses has no top-level `UIKit.framework` (Catalyst's lives under `iOSSupport` and is
  only visible with the flags `scripts/gen-goldens-ios.sh` adds). The Harness never depends on
  the root, so `import UIKit` there is always Apple's.

## Decision

Three packages in this repository:

```
SwiftUIWeb (root)          SwiftUI ─┬─ SwiftUIWebCore (+ _PlatformViewHostNode)
                                    └─ SwiftUIWebUIKit (UIViewRepresentable, UIViewControllerRepresentable)   [Phase 2]
        │ depends on
Packages/UIKitWeb          UIKit (thin) ── UIKitWebCore (UIView/CALayer trees, responders, controls,
        │ depends on                       UIViewController, UIWindow, UIApplication; a HostedScene)          [Phase 1]
Packages/WebGraphics       WebGraphics (geometry, Path, DisplayList + encoder, TextEngine + TextLayouter,
                           font and symbol tables, AssetCatalog, SemanticsNode, TextInputInfo, keys)          [Phase 0]
                           WebGraphicsCanvas / WebGraphicsNative / WebGraphicsHeadless (the hosts over
                           a `HostedScene` protocol)                                                          [Phase 0]
```

- SwiftUIWeb depends on UIKitWeb the way Apple's SwiftUI depends on UIKit; on wasm and Linux
  `import SwiftUI` re-exports `UIKit` as iOS does. Whether that stays unconditional is decided
  by the size gate after Phase 2.
- UIKit views paint into the same `DisplayList` as SwiftUI views, not into DOM elements. A
  representable is an ordinary painted leaf, so clipping, opacity, transforms, overlays and
  scroll views compose correctly; Tier A/C tests work unchanged; the macOS host paints UIKit
  views for free. The cost is painting UIKit's control looks by hand, mitigated by the iOS
  switch, slider, stepper, segmented and text field geometry already measured from Catalyst,
  which is UIKit's own. Text input keeps the overlay `<input>` mechanism through `TextInputInfo`.
- Goldens for UIKit fixtures come from real UIKit in the Catalyst window decision 0013 opened,
  plus a UIKit text-metrics recorder: UIKit measures text 1.5 to 2.5 pt narrower than
  SwiftUI's `Text` for the same string (`Docs/elements/iOS.md`).
- Phases: 0 extracts the substrate with no behaviour change; 1 makes UIKitWeb run alone
  (`Examples/UIKitCounter`); 2 adds the representables with sizing pinned by Catalyst goldens;
  3 adds Auto Layout (an in-house Cassowary solver, first), `draw(_:)`, `UIView.animate`,
  `UIHostingController` and the larger UIKit classes.

## Phase 0 log

- Step 1 (2026-09-06): `Packages/WebGraphics` with the `WebGraphics` module. Moved out of
  `SwiftUIWebCore`: `Geometry/` (with `EdgeInsets`), `Display/` (`DisplayList`, encoder,
  `PaintContext`, `AssetCatalog` and `ColorScheme`, `DisplayGradient`, `BlendMode`, the image
  loading protocol, pixel filters), `Shapes/` (`Path`, path geometry and boolean algebra, rounded
  corners, `StrokeStyle`), `Text/` (`TextEngine`, `TextLayouter`, `ResolvedFont`, the font and
  symbol tables), and the host value types (`SemanticsNode`, `TextInputInfo`, `KeyEquivalent`,
  `EventModifiers`, `KeyEvent`, `PointerType`). SwiftUI's nested names stay as typealiases
  (`Font.Weight = FontWeight`, `Font.TextStyle = FontTextStyle`, `Text.TruncationMode`,
  `Text.Scale`); conformances to SwiftUI protocols (`Animatable`, `Shape`) stay in Core
  (`Shapes/GeometryConformances.swift`). The measured tables hang off
  `SystemFontMetricsTables` (the generators in `scripts/` write there); `PlatformProfile`
  forwards. `SwiftUIWebCore` re-exports the substrate. 338 native tests pass unchanged; the
  wasm canvas target builds.
- Step 2 (2026-09-06): `HostedScene` (`WebGraphics/Input/HostedScene.swift`) is the list of
  calls the hosts made on `Runtime`: install text engine, assets, image loader, appearance and
  clipboard; `needsFrame`, `advanceFrame(elapsed:)`, `layout(in:)`, `render(scale:)`; pointer,
  wheel and key input plus the cursor; the semantics tree with activate, adjust, set value,
  focus and blur; the text-field callbacks. `Runtime` conforms in
  `SwiftUIWebCore/Runtime/HostedScene.swift`. The hosts moved: `CanvasSceneHost`
  (`WebGraphicsCanvas`, with `PainterScript` and `Canvas2DTextEngine`), `NativeSceneHost`
  (`WebGraphicsNative`, with `CoreTextEngine`, `CoreGraphicsPainter`, `RuntimeView` and the
  accessibility elements), `RecordedTextEngine` and the manifest reader (`WebGraphicsHeadless`).
  What stayed in SwiftUIWeb is SwiftUI's to decide and lives in thin wrappers named as before
  (`CanvasHost`, `NativeHost`, `HeadlessRenderer`): the window background and chrome flags, the
  platform look from the page's pointer (`requestedPlatform`, `hasCoarsePointer`), the
  `OpenURLAction` and `ShareAction` handlers over the hosts' `openURL` and `share`, and mounting
  the root. The page-facing names (`window.__swiftuiweb`, `__swiftuiwebAssets`,
  `__swiftuiwebDebug`, the `swiftuiwebready` event) are unchanged, so the Playwright scripts are too.
- Step 3 (2026-09-06): verification of the whole extraction. 338 native tests (Tier A and C)
  unchanged; Tier B 367/367 renders within tolerance in Chromium; the Counter smoke test green
  in Chromium, WebKit and Firefox. Release Counter bundle 10,747,042 bytes raw and 2,751,777
  brotli against 10,782,020 and 2,762,661 at the commit before the extraction (`0d87724`,
  built the same way): the package split cost nothing. One gotcha for anyone repeating this:
  SwiftPM does not recompile unchanged files in *other* targets when a type they use moves
  modules, so both the root `.build` and every example's `.build/wasm` needed a clean before
  the link succeeded (stale objects referenced `SwiftUIWebCore.CGSize`).

## Phase 1 log

- Step 1 (2026-09-06): the package skeleton and the counter (`Docs/ROADMAP.md`, Phase 7 status
  1.1). Two things UIKit source cannot keep without an Objective-C runtime: `#selector` (the
  target-action and gesture APIs take closures and `UIAction`s instead), and the app delegate's
  instantiation: `main()` creates it with `init()`, which a non-final class can only promise
  with `required init()`, so a delegate is `final` or declares `required override init()`.
  `UIResponder.init()` is deliberately not `required`: that would force `required init()` onto
  every view and view controller subclass with its own initializer, which is far more common
  than an app delegate. The bundle is 2.24 MB brotli for a three-view app because the
  substrate's symbol and font tables come along; trimming them is a Phase 3 item.
- Step 2 (2026-09-10): the fidelity loop (`Docs/ROADMAP.md`, Phase 7 status 1.2). UIKit
  fixtures are plain UIKit code building a view tree (`Fixtures/UIKit`), so the fixture API
  (`UIKitFixtureKit`) is implemented twice, once over Apple's UIKit in the Harness and once over
  UIKitWeb, and the fixture sources are symlinked into both packages; `#if canImport(UIKit)`
  keeps them empty in the Harness's plain macOS build. Goldens come from `UIKitGoldenGen` in a
  Catalyst window (`scripts/gen-goldens-uikit.sh`), like the iOS SwiftUI goldens. Two recorders
  feed the runtime: the fixture strings measured by a real `UILabel` (replayed by the shared
  `RecordedTextEngine`, keyed exactly as UIKitWeb's label asks, line limit included) and a sweep
  of `UIFont` at every weight and integer size plus the text styles, with the label heights UIKit
  gives each. The sweep showed what the hhea ratios of step 1 got wrong: UIKit's ascender and
  descender are 1980/2048 and 432/2048 of the size, `lineHeight` is their rounded sum (20 at
  17 pt, not 20.29), a one-line label is one point taller at nine sizes with no derivable rule
  (so it is a table), and a text style carries its own ascender, descender and leading (body:
  24.02 line, 26 pitch). The generator's `--dump` mode prints UIKit's internal view trees, which
  is how the buttons' 15 pt system title, the configured button's 26.5 pt body label and the
  stack's rounded placement were found. Catalyst's Mac switch is the one artefact so far: the
  test compares its origin only.


## Phase 2 log

- Step 1 (2026-09-10): the representables (`Docs/ROADMAP.md`, Phase 7 status 2.1;
  `Docs/elements/Representable.md`). The root package depends on `Packages/UIKitWeb`; the
  `SwiftUI` module re-exports `UIKit` on every platform (Apple's SwiftUI does on iOS), so a file
  that only imports SwiftUI can name `UIColor` and declare a `UIViewRepresentable`. The seam is
  two protocols: `_PlatformViewTree` in `SwiftUIWebCore` (what a hosted tree provides: layout in a
  size, paint at an origin, pointer events, wheel, semantics with routing by identifier, focus,
  text input, baselines, dismantle) with `_PlatformViewHostNode` as the leaf that owns the
  SwiftUI side, and `UIKitHostedTree` in `UIKitWebCore` (a window the scene never shows, the
  scene's `TouchRouter`, the semantics walk, first-responder tracking). `SwiftUIWebUIKit` in the
  root package joins them; being in the same package as the core it uses `package` members, so
  nothing new became public in the core. Two runtime changes were needed for hosted trees:
  routing by semantics identifier falls through to the tree that contains an identifier (UIKit's
  start at 20 000 000, clear of every SwiftUIWeb range), and the semantics cache keeps a hosted
  element's frame relative to its node so a scroll-only frame moves it correctly. The scene's
  `setNeedsFrame` fans out to hosted trees, which suppress it while laying out or painting for
  the host; `updateUIView` runs under observation tracking, as a body would. Sizing was
  measured, not assumed: SwiftUI takes the alignment rect (intrinsic size less
  `alignmentRectInsets`) and lets a proposal win unless the relevant priority is at least 750,
  which also exposed that the iOS 26 `UISwitch` is 68 × 30 with a 2 pt right inset (a run
  earlier the same day had measured 51 × 31 for `sizeToFit`; the fixture now says 68 × 30) and
  that a rounded `UITextField` has a real intrinsic width (text + 28). The size gate: Counter
  2,835,785 bytes brotli against 2,751,777 before UIKitWeb was linked (budget 3,145,728), so the
  re-export stays unconditional.

## Phase 3 log

- Step 1 (2026-09-10): Auto Layout (`Docs/ROADMAP.md`, Phase 7 status 3.1;
  `Docs/elements/UIKit/AutoLayout.md`). The solver is Cassowary in Kiwi's incremental simplex
  form, written for the one way it is used here: a fresh tableau per layout pass, constraints
  added once, no removal. UIKit priorities map to weights of 10^(priority / 100) so that a
  higher priority outweighs any realistic number of lower ones, with 1000 required. The engine
  gives every view in a root's subtree four variables in its superview's coordinates and pins
  the views that translate their autoresizing mask to their frames, which makes a frame-laid
  container an anchor for the constrained views inside it, as UIKit's engine does. Two
  findings from the goldens: a view controller's root view has system minimum margins of 16
  sideways and 0 vertically (with no status bar) that replace the 8 pt default rather than
  raise it, and a label's baseline anchor is its ascender rounded to the pixel below the text
  rect's rounded top (the representable step had rounded to the point from one measurement).
  One Swift gotcha for the solver: iterating a dictionary's `keys` while mutating the
  dictionary is an exclusivity violation ("Fatal access conflict"), as is optimising an
  `inout` row that the pivot's substitution also writes through `self`.
- Step 2 (2026-09-11): `draw(_:)` (`Docs/ROADMAP.md`, Phase 7 status 3.2;
  `Docs/elements/UIKit/Drawing.md`). Without an Objective-C runtime there is no way to ask
  whether a class overrides `draw(_:)`, so every view that is not one of the built-in painters
  gets `draw(bounds)` called each frame with a recording context; the default draws nothing and
  the recorder is cheap. The context is a state machine over the display list (CoreGraphics's
  save/restore semantics, transforms applied when a path is painted). Naming: on wasm the
  recorder is `CGContext`, so `UIGraphicsGetCurrentContext()` code compiles as on iOS; on Apple
  platforms CoreGraphics owns the name and a typealias in the `UIKit` shim would make it
  ambiguous for any file that also sees AppKit (the root's native tests), so there the class is
  `UIGraphicsRecordingContext` and type inference carries most drawing code. The pixel tier
  showed the first attempt right at 0.16 %.
- Step 3 (2026-09-11): `UIView.animate` (`Docs/ROADMAP.md`, Phase 7 status 3.3;
  `Docs/elements/UIKit/Animation.md`). The mechanism is the one SwiftUIWeb's transactions use
  (record the property changes a block makes, present the interpolation while the clock runs)
  placed on the layer setters, which are the funnel for every animatable view property. No
  goldens: the harness cannot capture animations in flight, so the curves are UIKit's documented
  cubic beziers and a damped spring, held by unit tests.
- Step 4 (2026-09-11): `UIHostingController` (`Docs/ROADMAP.md`, Phase 7 status 3.4). The
  reverse embedding: a `Runtime` inside a UIView. It has to live in the root package (UIKitWeb
  cannot depend on SwiftUIWeb), so UIKitWebCore grew a small hosting SPI on `UIView`
  (`_hostedPaint`, `_hostedSemantics`, `_hostedHandles` and the routing calls, the frame clock,
  wheel) and a registry on the scene; the SwiftUI side overrides them in `_UIHostingView`. With
  this the plan's four Phase 3 items are in: Auto Layout, `draw(_:)`, `UIView.animate`,
  `UIHostingController`.

## Phase 4 log

- Step 1 (2026-09-11): `UINavigationController` and `UITabBarController`
  (`Docs/ROADMAP.md`, Phase 7 status 4.1; `Docs/elements/UIKit/Navigation.md`). The
  generator's `--dump` mode paid for itself: UIKit's iOS 26 bars are stacks of private views
  (platters, lenses, transition containers) whose frames the dump lists, so the geometry was
  read off rather than inferred from pixels. The bars are drawn as measured: translucent, with
  glass platters for items; the transitions apply at once for now. Containers hand their
  children a safe area through a `containerSafeAreaInsets` on the child's view.
- Step 2 (2026-09-11): `UITableView` (`Docs/ROADMAP.md`, Phase 7 status 4.2;
  `Docs/elements/UIKit/TableView.md`). Rows are built for the whole table (the fixtures are
  short; recycling waits for a long-list fixture). Two platform seams surfaced: UIKit's
  `IndexPath.row`/`section` are UIKit's additions to Foundation's type, so UIKitWebCore adds
  them, and data sources written for UIKit subclass `NSObject`, which FoundationEssentials on
  wasm does not have, so UIKitWebCore declares an empty one there.
- Step 3 (2026-09-11): the remaining controls (`Docs/ROADMAP.md`, Phase 7 status 4.3;
  `Docs/elements/UIKit/Controls.md`): `UISlider`, `UISegmentedControl`, `UIStepper`,
  `UIProgressView`, `UIActivityIndicatorView`, `UIPageControl`, one fixture, frames exact and
  0.6 % of pixels off. The capture is transparent where UIKit draws a material (the page
  control's backdrop), so the colours sampled from it are the controls' own, not the composite.
- Step 4 (2026-09-11): `UICollectionView` with the flow layout (`Docs/ROADMAP.md`, Phase 7
  status 4.7; `Docs/elements/UIKit/CollectionView.md`). The flow layout's two justification
  rules came straight from the goldens: a full line spreads its items over the free space, and
  items of one size always sit on the grid a full line would make, so a short last line keeps
  the same gap. Cells exist for the items in view only, which the golden for the horizontal
  fixture demands (its fourth item has no probe: UIKit never made the cell).
- Step 5 (2026-09-11): alerts and sheets (`Docs/ROADMAP.md`, Phase 7 status 4.8;
  `Docs/elements/UIKit/Presentation.md`). Presentations live beside the root controller's view,
  so the UIKit golden generator learned to capture the whole window (a `capturesWindow()`
  fixture flag, the same in both fixture kits) and to dump the view tree after each behaviour
  step, which is where an alert exists. The dump showed iOS 26 drawing action sheets as the same
  centred card as alerts, and a page sheet's spring still 0.13 pt short of rest after half a
  second, so the harness now settles for 1.2 s after a step.
- Step 6 (2026-09-11): `UITextView` (`Docs/ROADMAP.md`, Phase 7 status 4.9;
  `Docs/elements/UIKit/TextView.md`). The goldens showed TextKit's line fragments on the pixel
  grid (a 20.5 pt pitch for 17 pt, the first baseline rounded up), `sizeThatFits` answering the
  used width plus the insets without the fragment padding, and a non-scrolling view laying out
  only the lines its container holds; a default-font view left the fixture because UIKit's
  default is Helvetica 12, which the web cannot measure. Found on the way: the nav and tab bar
  buttons fired their actions twice (UIControl already sends `primaryActionTriggered` on the
  touch up), which orphaned an alert under its container in the settings example.
- Step 7 (2026-09-11): `UIToolbar` and `UISearchBar` (`Docs/ROADMAP.md`, Phase 7 status
  4.10; `Docs/elements/UIKit/Bars.md`). The dump showed iOS 26 building a toolbar from the same
  glass platters as the navigation bar, 48 tall instead of 44, in a SwiftUI-hosted row with a
  12 pt spacing that a fixed space adds its width to; the platter button gained a height and
  a prominent (done) look. The search bar's field is a real text field (`searchTextField`), so
  the host's text input and the representables' routing work unchanged.
- Step 8 (2026-09-11): toolbars and search in navigation controllers (`Docs/ROADMAP.md`, Phase
  7 status 4.11; `Docs/elements/UIKit/Bars.md`). iOS 26 hosts both in a SwiftUI floating bar
  over the bottom of the screen: the toolbar's items grouped by their flexible spaces rather than
  spread by them, and a navigation item's search field in a 264 pt capsule with an empty 60 pt
  `UISearchBar` left under the navigation bar. Neither `navigation.toolbar` nor the
  `searchTextField` joins UIKit's hierarchy, so those probes came out of the fixtures and the
  pixels pin the geometry.
- Step 9 (2026-09-11): `UIDatePicker` (`Docs/ROADMAP.md`, Phase 7 status 4.12;
  `Docs/elements/UIKit/DatePicker.md`). The compact style is two capsules whose geometry the
  dump gave outright; the strings are formatted in Swift for en_US because wasm has no ICU
  (FoundationEssentials has `Calendar`, not `DateFormatter`), and UIKit's time uses a narrow
  no-break space before the period, which the text-metrics request had to carry too. The
  wheels drum is drawn approximately and its fixture is frames-only in both pixel tiers.
- Step 10 (2026-09-11): alert text fields (`Docs/ROADMAP.md`, Phase 7 status 4.13). The dump
  showed the fields in a collection view of 34 pt cells under the header, a secure field's
  cell 32 tall and the second row half a point higher than a plain stack would put it; the
  card grew the block and the actions moved under it. The fields are ordinary `UITextField`s,
  so the host's text input and the action handlers reading `textFields` work unchanged.
- Step 11 (2026-09-11): `UIPickerView` (`Docs/ROADMAP.md`, Phase 7 status 4.14). The drum
  painter left the date picker for both to share; the picker's fixture pins its frame only,
  as the wheels date picker's does.
- Step 12 (2026-09-11): presentation animations (`Docs/ROADMAP.md`, Phase 7 status 4.15),
  followed rather than measured like the navigation slide: the scene animates the container's
  dimming and the presented view's transform and opacity through `UIView.animate`, and the
  completion chain moved from the controller to the scene so handlers run when the animation
  ends. Found on the way: the alert action button re-sent `primaryActionTriggered` after
  `UIControl` had, the same double dispatch the bar buttons had.
- Step 13 (2026-09-11): scroll polish (`Docs/ROADMAP.md`, Phase 7 status 4.16): rubber banding
  from UIKit's published curve, paging, and indicators whose geometry the text view dump had
  already recorded (3 pt bars 3 in, black at 35 %). They are hidden at rest, so no golden
  changes; the tests drive them through the scene's pointer and frame clock.
