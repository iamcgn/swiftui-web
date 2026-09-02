# SwiftUI support matrix

Generated from `Docs/support.json` by `scripts/support-matrix.py`. Anything not listed is not implemented.

| Status | Meaning |
|---|---|
| ✅ full | API complete, fixtures pass exact layout and pixel checks |
| 🟢 partial | Common usage works; listed gaps |
| 🟡 approximate | Works but rendering knowingly differs (e.g. SF Symbols substitute) |
| 🟠 stub | Compiles, no behaviour |
| ❌ missing | Not implemented |

## App lifecycle

| API | Status | Notes | Fixtures |
|---|---|---|---|
| `App / Scene / WindowGroup / @main` | 🟢 partial | App/Scene/WindowGroup/SceneBuilder API; main() mounts the first WindowGroup in the canvas host (wasm) or lays out headlessly; Tier B (Chromium) within tolerance |  |

## View composition

| API | Status | Notes | Fixtures |
|---|---|---|---|
| `View / ViewBuilder (if/else, optional, switch, #available, any child count)` | 🟢 partial | Runtime node tree with structural identity; no layout or painting yet; Tier B (Chromium) within tolerance |  |
| `EmptyView / TupleView / Group / _ConditionalContent / Optional` | 🟢 partial | Runtime nodes exist; no layout yet; Tier B (Chromium) within tolerance |  |
| `AnyView` | 🟢 partial | Runtime nodes exist; no layout yet; Tier B (Chromium) within tolerance |  |
| `ViewModifier / ModifiedContent / EmptyModifier / modifier(_:)` | 🟢 partial | Runtime nodes exist; no layout yet; Tier B (Chromium) within tolerance |  |
| `EnvironmentValues / EnvironmentKey / environment(_:_:) / transformEnvironment` | 🟢 partial | @Entry macro not provided; Tier B (Chromium) within tolerance |  |
| `Transaction / TransactionKey / withTransaction` | 🟠 stub | No `animation` member until the animation system exists |  |
| `id(_:) / IDView` | 🟢 partial | Identity change rebuilds the subtree; Tier B (Chromium) within tolerance |  |
| `ForEach (Identifiable, id:, Range<Int>, Binding collections) / DynamicViewContent` | 🟢 partial | Keyed reconciliation: state follows ids across insert/mutate/reorder/remove (foreach/identity, 4 steps); modifiers distribute per element; no editActions, onDelete/onMove, or Subviews-based forms; Tier B (Chromium) exact frames, ≤ 0.3 % pixels incl. every identity step | foreach/* |
| `Section (content/header/footer, title forms, deprecated argument orders)` | 🟢 partial | Transparent outside List/Form: header, content and footer flatten in order, exact against goldens; no List/Form styling, isExpanded or collapsible; Tier B (Chromium) exact frames, ≤ 0.3 % pixels | section/* |
| `DynamicProperty (custom, nested)` | 🟢 partial | update() and nested installation; Tier B (Chromium) within tolerance |  |

## Views

| API | Status | Notes | Fixtures |
|---|---|---|---|
| `Text (verbatim/localized/interpolation, concatenation with mixed styles)` | 🟢 partial | Layout exact with recorded metrics on 17 fixtures; default font is the 13 pt system font and bold() resolves per text style (decision 0010); concatenated parts keep font/weight/traits/colour; wrapping, character wrapping, hard newlines, lineLimit (Int, ranges, reservesSpace), truncationMode head/middle/tail, multilineTextAlignment, lineSpacing; no localization tables, kerning/tracking, attributed strings, height-pressure truncation; Tier B (Chromium) exact frames on all 17 text fixtures, pixels ≤ 1.9 % (system-font fallbacks 4.7 %); WebKit exact frames, text pixels ≤ 1.1 %; Firefox exact frames, pixels ≤ 3.5 % (hinting) | text/* |
| `lineLimit / multilineTextAlignment / truncationMode / lineSpacing (View + EnvironmentValues)` | 🟢 partial | All lineLimit overloads (lower bounds reserve lines); truncation at character granularity with spaces dropped next to the ellipsis; alignment shifts lines by drawn width; a text under height pressure does not drop lines yet; Tier B (Chromium) exact frames on all 17 text fixtures, pixels ≤ 1.9 % (system-font fallbacks 4.7 %); WebKit exact frames, text pixels ≤ 1.1 %; Firefox exact frames, pixels ≤ 3.5 % (hinting) | text/line-limit, text/truncation, text/alignment, text/line-spacing |
| `allowsTightening / minimumScaleFactor` | 🟠 stub | Environment values stored, not applied to layout |  |
| `VStack / HStack / ZStack` | 🟢 partial | Layout exact against goldens; no painting yet; Tier B (Chromium) within tolerance | layout/* |
| `Spacer` | 🟢 partial | Layout exact; no painting yet; Tier B (Chromium) within tolerance | layout/spacer, layout/spacer-min-length |
| `Button` | 🟢 partial | bordered (default), borderedProminent, plain exact in layout; borderless approximate (grey label in a window); custom ButtonStyle; press state; no roles/disabled; Tier B (Chromium) within tolerance | button/basic, button/styles |
| `Divider` | 🟢 partial | Layout exact (1pt); no painting yet; Tier B (Chromium) within tolerance | layout/divider |
| `Color (as a view)` | 🟢 partial | macOS light system colour table; painting via display list; Tier B (Chromium) within tolerance | paint/system-colors |
| `Layout protocol / custom layouts / layoutValue` | 🟢 partial | sizeThatFits, placeSubviews, spacing, explicitAlignment, cache; no RTL; Tier B (Chromium) within tolerance |  |
| `Font (text styles, system(size:weight:design:), bold/weight/italic/monospaced)` | 🟢 partial | macOS text-style table; bold() is a per-style trait; italic keys; Tier B (Chromium) within tolerance | text/styles, text/system-fonts, text/modifiers |
| `Rectangle / RoundedRectangle / Circle / Ellipse / Capsule, fill / stroke, Path` | 🟢 partial | Fill and plain stroke; no StrokeStyle or InsettableShape; Tier B (Chromium) within tolerance | paint/shapes |
| `GeometryReader / GeometryProxy (size, frame(in:), bounds(of:))` | 🟢 partial | No safe area or anchors; Tier B (Chromium) within tolerance | all (probe implementation) |
| `ScrollView (axes, showsIndicators) / ScrollViewReader / ScrollViewProxy.scrollTo` | 🟢 partial | Fills the proposal along its axes and is exactly content-sized across them, implicit VStack content, clipping, defaultScrollAnchor, scrollTo with/without anchor resolved at layout; wheel scrolling with chaining, touch pan + momentum (0.998/ms), overlay indicators while scrolling (approximate geometry); no bounce, keyboard scrolling, scrollPosition/scrollTargetBehavior, contentMargins or lazy stacks; Tier B exact frames in Chromium, WebKit and Firefox (17/17 renders each) | scroll/* |

## State

| API | Status | Notes | Fixtures |
|---|---|---|---|
| `@State` | 🟢 partial | Box per node; writes coalesce; no animation transactions yet; Tier B (Chromium) within tolerance |  |
| `@Binding` | 🟢 partial | get/set, constant, dynamic member lookup, optional and collection projections; Tier B (Chromium) within tolerance |  |
| `@Environment` | 🟢 partial | Key-path and Observable-object forms (`Environment(Model.self)`, optional variant); `.environment(object)`; Tier B (Chromium) within tolerance |  |
| `@Observable / @Bindable` | 🟢 partial | Per-body withObservationTracking; only reading nodes invalidate. Bindable via ReferenceWritableKeyPath; Tier B (Chromium) within tolerance |  |
| `ObservableObject / @Published / @StateObject` | ❌ missing | Combine is unavailable on wasm/Linux; minimal in-house implementation planned (Phase 3) |  |

## Modifiers

| API | Status | Notes | Fixtures |
|---|---|---|---|
| `padding` | 🟢 partial | Layout exact; Tier B (Chromium) within tolerance | layout/padding-default, layout/padding-edges |
| `frame` | 🟢 partial | Fixed and flexible forms exact; Tier B (Chromium) within tolerance | layout/frame-fixed, layout/frame-flex |
| `background / overlay` | 🟢 partial | View, style and shape forms; layout exact, display-list painting; Tier B (Chromium) within tolerance; one layer per element when applied to a list (foreach/modifier, section/modifier) | paint/background-overlay |
| `foregroundStyle / foregroundColor` | 🟢 partial | Flat colours only; Tier B (Chromium) within tolerance |  |
| `fixedSize / layoutPriority / alignmentGuide` | 🟢 partial | Layout exact; Tier B (Chromium) within tolerance | layout/fixed-size, layout/hstack-priority, layout/alignment-guide |
| `font(_:)` | 🟢 partial | Environment font; Tier B (Chromium) within tolerance | text/modifiers |
| `opacity / clipShape / clipped / cornerRadius` | 🟢 partial | Display-list groups and clips; Tier B (Chromium) within tolerance; applied per element on lists | paint/clipping |
| `preference / transformPreference / onPreferenceChange / coordinateSpace` | 🟢 partial | Bottom-up reduction after layout; no anchorPreference or overlayPreferenceValue yet; Tier B (Chromium) within tolerance |  |
| `onTapGesture` | 🟢 partial | Single tap via the pointer arena; count ignored; Tier B (Chromium) within tolerance |  |
| `scrollIndicators / scrollDisabled / scrollBounceBehavior / scrollClipDisabled / defaultScrollAnchor` | 🟢 partial | Environment-backed; scrollBounceBehavior is stored but has no effect (no rubber band); defaultScrollAnchor sets the initial offset only | scroll/modifiers, scroll/anchor-bottom |
| `onChange(of:initial:_:) (two- and zero-argument actions), deprecated onChange(of:perform:)` | 🟢 partial | Actions run from the scheduler's action queue after the update that changed the value; sibling onChange order is inner first | scroll/scroll-to |
