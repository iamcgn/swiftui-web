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
| `@Environment` | ❌ missing |  |  |
| `@Observable / @Bindable` | ❌ missing |  |  |
| `ObservableObject / @Published / @StateObject` | ❌ missing | Combine is unavailable on wasm/Linux; minimal in-house implementation planned (Phase 3) |  |

## Modifiers

| API | Status | Notes | Fixtures |
|---|---|---|---|
| `padding` | ❌ missing |  |  |
| `frame` | ❌ missing |  |  |
| `background / overlay` | ❌ missing |  |  |
| `foregroundStyle / foregroundColor` | ❌ missing |  |  |
