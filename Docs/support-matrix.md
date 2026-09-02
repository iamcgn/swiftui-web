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

## Views

| API | Status | Notes | Fixtures |
|---|---|---|---|
| `Text` | ❌ missing |  |  |
| `VStack / HStack / ZStack` | ❌ missing |  |  |
| `Spacer` | ❌ missing |  |  |
| `Button` | ❌ missing |  |  |

## State

| API | Status | Notes | Fixtures |
|---|---|---|---|
| `@State` | ❌ missing |  |  |
| `@Binding` | ❌ missing |  |  |
| `@Environment` | 🟠 stub | Key-path form only; resolved by the runtime from step 3 |  |
| `@Observable / @Bindable` | ❌ missing |  |  |
| `ObservableObject / @Published / @StateObject` | ❌ missing | Combine is unavailable on wasm/Linux; minimal in-house implementation planned (Phase 3) |  |

## Modifiers

| API | Status | Notes | Fixtures |
|---|---|---|---|
| `padding` | ❌ missing |  |  |
| `frame` | ❌ missing |  |  |
| `background / overlay` | ❌ missing |  |  |
| `foregroundStyle / foregroundColor` | ❌ missing |  |  |
