# ObservableObject, @Published, @StateObject, @ObservedObject, @EnvironmentObject

Apple docs: [ObservableObject](https://developer.apple.com/documentation/combine/observableobject),
[Published](https://developer.apple.com/documentation/combine/published),
[StateObject](https://developer.apple.com/documentation/swiftui/stateobject),
[ObservedObject](https://developer.apple.com/documentation/swiftui/observedobject),
[EnvironmentObject](https://developer.apple.com/documentation/swiftui/environmentobject).

Combine is absent on wasm and Linux, so `SwiftUI` provides this family itself (about 250
lines, no OpenCombine). On Apple platforms Foundation re-exports Combine's names; the `SwiftUI`
module declares typealiases so `import SwiftUI` resolves to these without ambiguity.

## API surface

| API | Notes |
|---|---|
| `ObservableObject` (`objectWillChange: ObservableObjectPublisher`, a default per-object publisher) | implemented; `ObjectWillChangePublisher` is fixed to `ObservableObjectPublisher` |
| `ObservableObjectPublisher` (`send`, `subscribe`, `sink`), `AnyCancellable` (`cancel`, `store(in:)`) | implemented as closure subscribers; no other Combine operators |
| `@Published` | implemented through the enclosing-instance subscript: the setter sends `objectWillChange` before assigning; `$property` is a minimal publisher with `sink` on the object's changes |
| `@StateObject(wrappedValue:)` | implemented: one instance per view identity, kept in the node's slot |
| `@ObservedObject` (`wrappedValue:`, `initialValue:`), `$object.property` bindings | implemented (re-subscribes when the object changes) |
| `@EnvironmentObject`, `environmentObject(_:)` | implemented (a missing object traps with Apple's message) |
| `onReceive`, `Timer.publish`, `NotificationCenter.publisher` | missing |

## Behaviour

Each wrapper is a `DynamicProperty` installed per node: `_StateObjectBox` (the object and a
`_ObjectSubscription`) or a bare `_ObjectSubscription` for observed and environment objects.
`_ObjectSubscription.observe(_:from:)` subscribes `{ node.invalidate() }` to the object's
publisher, cancelling the previous subscription when the object identity changes. `@Published`
sends before the value changes; the invalidated node re-renders in the next flush, after the
assignment. `environmentObject(_:)` stores the object in `EnvironmentValues` by type.

## Measured (macOS 26.2, `observable/object`, 2026-09-03)

| Property | Value | Probe |
|---|---|---|
| Re-render on change | "Count: 0" (52 wide) becomes "Count: 1" (50) after the step; the toggle turns on through `$model.flag` | `count`, `toggle`, steps |

## Verification (2026-09-03)

Tier A: `observable/object` exact with both steps. Tier B 3/3 in Chromium and WebKit; Firefox
differs by its "Flag" width (the known hinting class). `ObservableObjectTests` cover state object
persistence across parent re-renders, button and toggle mutations, observed object replacement,
environment objects, a manual `objectWillChange`, publisher identity and cancellation. wasm js
tests pass.

## Not yet covered

Combine publishers and operators, `onReceive`, `Published.Publisher` values (it only signals
changes), `objectWillChange` on non-main threads, `@StateObject` `update()` semantics for
`wrappedValue` written before installation.
