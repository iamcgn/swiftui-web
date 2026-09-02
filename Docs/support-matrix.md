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
| `App / Scene / WindowGroup / @main` | ❌ missing |  |  |

## View composition

| API | Status | Notes | Fixtures |
|---|---|---|---|
| `View / ViewBuilder (if/else, optional, switch, #available, any child count)` | 🟢 partial | Runtime node tree with structural identity; no layout or painting yet |  |
| `EmptyView / TupleView / Group / _ConditionalContent / Optional` | 🟢 partial | Runtime nodes exist; no layout yet |  |
| `AnyView` | 🟢 partial | Runtime nodes exist; no layout yet |  |
| `ViewModifier / ModifiedContent / EmptyModifier / modifier(_:)` | 🟢 partial | Runtime nodes exist; no layout yet |  |
| `EnvironmentValues / EnvironmentKey / environment(_:_:) / transformEnvironment` | 🟢 partial | @Entry macro not provided |  |
| `Transaction / TransactionKey / withTransaction` | 🟠 stub | No `animation` member until the animation system exists |  |
| `id(_:) / IDView` | 🟢 partial | Identity change rebuilds the subtree |  |
| `DynamicProperty (custom, nested)` | 🟢 partial | update() and nested installation |  |

## Views

| API | Status | Notes | Fixtures |
|---|---|---|---|
| `Text` | 🟢 partial | Layout exact with recorded metrics; no painting, lineLimit, truncation or localization yet | text/* |
| `VStack / HStack / ZStack` | 🟢 partial | Layout exact against goldens; no painting yet | layout/* |
| `Spacer` | 🟢 partial | Layout exact; no painting yet | layout/spacer, layout/spacer-min-length |
| `Button` | ❌ missing |  |  |
| `Divider` | 🟢 partial | Layout exact (1pt); no painting yet | layout/divider |
| `Color (as a view)` | 🟢 partial | macOS light system colour table; painting via display list | paint/system-colors |
| `Layout protocol / custom layouts / layoutValue` | 🟢 partial | sizeThatFits, placeSubviews, spacing, explicitAlignment, cache; no RTL |  |
| `Font (text styles, system(size:weight:design:), bold/weight/italic/monospaced)` | 🟢 partial | macOS text-style table; bold() is the semibold face as measured | text/styles, text/system-fonts, text/modifiers |
| `Rectangle / RoundedRectangle / Circle / Ellipse / Capsule, fill / stroke, Path` | 🟢 partial | Fill and plain stroke; no StrokeStyle or InsettableShape | paint/shapes |
| `GeometryReader / GeometryProxy (size, frame(in:), bounds(of:))` | 🟢 partial | No safe area or anchors | all (probe implementation) |

## State

| API | Status | Notes | Fixtures |
|---|---|---|---|
| `@State` | 🟢 partial | Box per node; writes coalesce; no animation transactions yet |  |
| `@Binding` | 🟢 partial | get/set, constant, dynamic member lookup, optional and collection projections |  |
| `@Environment` | 🟢 partial | Key-path and Observable-object forms (`Environment(Model.self)`, optional variant); `.environment(object)` |  |
| `@Observable / @Bindable` | 🟢 partial | Per-body withObservationTracking; only reading nodes invalidate. Bindable via ReferenceWritableKeyPath |  |
| `ObservableObject / @Published / @StateObject` | ❌ missing | Combine is unavailable on wasm/Linux; minimal in-house implementation planned (Phase 3) |  |

## Modifiers

| API | Status | Notes | Fixtures |
|---|---|---|---|
| `padding` | 🟢 partial | Layout exact | layout/padding-default, layout/padding-edges |
| `frame` | 🟢 partial | Fixed and flexible forms exact | layout/frame-fixed, layout/frame-flex |
| `background / overlay` | 🟢 partial | View, style and shape forms; layout exact, display-list painting | paint/background-overlay |
| `foregroundStyle / foregroundColor` | 🟢 partial | Flat colours only |  |
| `fixedSize / layoutPriority / alignmentGuide` | 🟢 partial | Layout exact | layout/fixed-size, layout/hstack-priority, layout/alignment-guide |
| `font(_:)` | 🟢 partial | Environment font | text/modifiers |
| `opacity / clipShape / clipped / cornerRadius` | 🟢 partial | Display-list groups and clips | paint/clipping |
| `preference / transformPreference / onPreferenceChange / coordinateSpace` | 🟢 partial | Bottom-up reduction after layout; no anchorPreference or overlayPreferenceValue yet |  |
