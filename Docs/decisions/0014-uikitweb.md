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
- Step 14 (2026-09-11): collection view headers and footers (`Docs/ROADMAP.md`, Phase 7
  status 4.17). The flow layout's supplementary attributes join the item attributes in
  `layoutAttributesForElements(in:)` with their element kind set, and the collection view
  hosts and pools them beside the cells.
- Step 15 (2026-09-11): the visual format language (`Docs/ROADMAP.md`, Phase 7 status 4.18):
  a recursive-descent parser over Apple's published grammar producing ordinary constraints,
  so the solver and the goldens already in place verify it.
- Step 16 (2026-09-11): Core Animation (`Docs/ROADMAP.md`, Phase 7 status 4.19). Explicit
  animations and transactions sit on the same animation groups `UIView.animate` records
  into: an explicit animation is a group whose entry names the layer property a key path
  maps to, and a transaction is a group standalone layers' property setters record into when
  no animation block is open. The groups gained repeats, autoreverse and a retained final
  value for the forwards fill mode.
- Step 17 (2026-09-11): `UIViewPropertyAnimator` (`Docs/ROADMAP.md`, Phase 7 status 4.20). The
  animation group learned to be scrubbed, reversed and written back into the models, which is
  all the animator needs; nothing new in painting.
- Step 18 (2026-09-11): content configurations and `UIHostingConfiguration` (`Docs/ROADMAP.md`,
  Phase 7 status 4.21). The cells gained the configuration seam UIKit has had since iOS 14,
  and the hosting configuration composes its background, margins and content into one SwiftUI
  view for the hosting view `UIHostingController` already uses. The golden showed the default
  margins at 16 sideways and hosted rows on the 56 pt default row height; the iOS generator
  skips a fixture that does not declare `.platform(.iOS)`, silently.
- Step 19 (2026-09-11): self-sizing collection cells (`Docs/ROADMAP.md`, Phase 7 status 4.22).
  The flow layout measures through the cell's `preferredLayoutAttributesFitting`, which reads
  the content view's constraints with the solver already in place; the golden confirmed the
  fitted sizes and that the justification rules apply to them unchanged.
- Step 20 (2026-09-11): pinned table headers (`Docs/ROADMAP.md`, Phase 7 status 4.23), the
  clamp UIKit applies to a plain header's frame between its natural place, the visible top and
  its section's end; the fixture's steps probe `headerView(forSection:)` after each scroll.
- Step 21 (2026-09-11): diffable data sources and registrations (`Docs/ROADMAP.md`, Phase 7
  status 4.24): the snapshot is a value with ordered sections and items, the data sources
  keep the applied one and answer the plain protocols from it, and registrations map to the
  reuse identifiers already in place. Animated differences stay open.
- Step 22 (2026-09-11): compositional layouts (`Docs/ROADMAP.md`, Phase 7 status 4.25). The
  solver walks sections, groups and items with the dimensions resolved against their
  container; the golden settled the one rule that is not documented, that a group fills its
  slots by the items' own sizes and then takes a fixed spacing out of the fractional ones.
- Step 23 (2026-09-11): list layouts (`Docs/ROADMAP.md`, Phase 7 status 4.26). The list layout
  is a compositional layout in name that lays rows out as the inset grouped table does, sizing
  each through the list cell's preferred attributes; the dump gave the list content's metrics
  (24.5 pt body labels, rows 56 and 79.5), which differ from a table cell's labels.
- Step 24 (2026-09-11): orthogonal scrolling (`Docs/ROADMAP.md`, Phase 7 status 4.27). The dump
  showed UIKit's embedded scroll view sitting inside the section's insets with the cells kept
  in the section's coordinates and the off-screen ones never made; the collection view hosts
  such sections' cells in a scroll view per section and re-culls when it moves. Nested scroll
  views needed a rule for sharing a drag: a pan mostly along an axis a scroll view cannot
  scroll passes to the enclosing one.
- Step 25 (2026-09-11): list headers and footers (`Docs/ROADMAP.md`, Phase 7 status 4.28).
  A supplementary header replaces the 35 pt gap above a grouped section and the footer follows
  its rows, both sized through the list cell's preferred attributes without the 44 pt row floor;
  the dump gave the grouped header and footer content metrics (a headline 10 down in 44.5, a
  footnote 8 down in 35 laid out 21 tall although the label fits in 19).
- Step 26 (2026-09-11): first-item headers, decoration items, pinned headers (`Docs/ROADMAP.md`,
  Phase 7 status 4.29-4.31). The dumps settled three guesses: a first-item header is the same
  44.5 pt card-less header cell as a supplementary one with 17.5 between sections; a background
  decoration spans its section with the content insets included (its own insets shrink it);
  a pinned header clamps between the visible top and the next section's start, and once pushed
  away iOS 26 draws it beneath the cells (a scroll pocket blur UIKitWeb does not paint). The
  pinned fixture probes no row that scrolls away: UIKitWeb recycles its cell while UIKit keeps
  every cell, so the probe would follow the reused cell.
- Step 27 (2026-09-11): string and image drawing in `draw(_:)` (`Docs/ROADMAP.md`, Phase 7
  status 4.32). Text and images recorded from a graphics context go between a concat of the
  context's transform and a restore rather than through pre-transformed geometry, since the
  symbol painter and the image draw have no transform of their own; the display list already
  had the command. `NSAttributedString` is Foundation's on Apple platforms (with the UIKit keys
  added as extensions) and a one-dictionary stand-in on wasm, where FoundationEssentials has none.
- Step 28 (2026-09-11): the search bar's scope bar (`Docs/ROADMAP.md`, Phase 7 status 4.33).
  The dump showed the scope bar is a segmented control unlike a standalone one: segments of
  equal width across the bar and 15 pt regular titles even when selected, so the control gained
  a title size and an emphasis switch the search bar sets.
- Step 29 (2026-09-11): tabular figures (`Docs/ROADMAP.md`, Phase 7 status 4.34). The flag
  lives on the substrate's `ResolvedFont` so both frameworks and every engine see it. Chromium's
  `font-variant-numeric` does nothing for the system font, so a DOM measurement was no use; the
  slot comes from the "0" advance and a per-weight ratio measured with CoreText (regular text
  face: exactly the "0"), sent in the font string, digits centred in their slots. The recorded
  metrics key gains `:tabular`, spelled by `UIKitFixtureFont.monospacedDigit`.
- Step 30 (2026-09-11): animated batch updates (`Docs/ROADMAP.md`, Phase 7 status 4.35). Rather
  than diffing views, both containers take a map of surviving rows (old index path to new): the
  batch API builds it from the recorded inserts, deletes and moves under UIKit's old/new index
  semantics, the diffable data sources from the item identifiers. The container lays out for
  the new data with the surviving cells handed back to it under their new paths, then animates
  frames and alpha with `UIView.animate`; no golden covers the motion (the harness settles
  before capturing), so `BatchUpdateTests` drive the scene's clock.
- Step 31 (2026-09-11): self-sizing table rows (`Docs/ROADMAP.md`, Phase 7 status 4.36). The
  dump showed three things the guesses had wrong: a default cell's labels use the body and
  subheadline text styles (a wrapping title's lines are 26 apart, not 20.5), UIKit fits a cell
  with the row width required rather than compressed (else a wrapping label widens the content
  view instead of wrapping), and a wrapped label under constraints is a point taller than its
  own fit. The estimate correction reuses the batch-update retained-cell path: the rows are laid
  out again with the cells already made handed back under their paths.
- Step 32 (2026-09-11): table editing and swipe actions (`Docs/ROADMAP.md`, Phase 7 status
  4.37). Editing mode came from a golden with steps (`setEditing` is public); swipes cannot be
  captured on the simulator (no public way to open a row's actions), so their geometry is
  UIKit-shaped rather than measured and `EditingTests` drive the scene's pointer. The swipe is
  a pan recognizer on the table that begins only for horizontal pans on rows with actions
  (the scroll view already leaves horizontal pans alone); a bug surfaced in the tap
  recognizer, which failed on movement but reset to possible at once and so recognised at the
  end of a drag. Two test gotchas: a data source held only by the test's tuple is deallocated
  (the table keeps it weakly), and every stored-property change needs a package clean.
  Reordering rides the same recognizer: a pan starting on a grip lifts the row instead; the
  begin check must use where the finger went down (location minus translation), since the pan
  begins after the slop.
- Step 34 (2026-09-11): dark appearance (`Docs/ROADMAP.md`, Phase 7 status 4.38). Rather than
  new content, six light fixtures are declared again dark through a `renamed(_:)` on the
  fixture kit (both twins), so the goldens measure only what the appearance changes. Two
  colour errors hid inside the light tolerances until the dark twins exposed them: grouped
  cards drew the cell's default `systemBackground` (white in the light, black in the dark) and
  grouped headers drew in the label colour; both are fixed for both appearances. The browser
  exposed a third: a view made under one interface style kept its layer's resolved colour on
  joining a tree of the other, so insertion now re-resolves dynamic colours when the styles
  differ (UIKit's trait change on moving to a window).
- Step 35 (2026-09-11): outlines (`Docs/ROADMAP.md`, Phase 7 status 4.39). The section snapshot
  is a value the data source keeps per section and flattens into the plain snapshot's items,
  so expansion rides the existing animated diff. Fixture lesson: a golden's probes are read
  from views, so a removed cell keeps reporting its last frame and a reused one another item's;
  fixtures whose steps remove rows probe only the rows that stay.
- Step 36 (2026-09-11): plain lists (`Docs/ROADMAP.md`, Phase 7 status 4.40). The fixture's
  probes showed the list layout had been asking the data source for every row's cell to size
  it, so rows below the fold existed here and not on the simulator; the layout now lays rows
  out at the estimate until their cells appear and measures then (the table's estimate
  correction, in the collection's terms). The pinned header's pocket has the same scrim
  profile as the plain table's (214 grey at the top over white, 253 at 65 pt).
