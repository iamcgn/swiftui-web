# onAppear, onDisappear, task

Apple docs: [onAppear(perform:)](https://developer.apple.com/documentation/swiftui/view/onappear(perform:)),
[onDisappear(perform:)](https://developer.apple.com/documentation/swiftui/view/ondisappear(perform:)),
[task(priority:_:)](https://developer.apple.com/documentation/swiftui/view/task(priority:_:)),
[task(id:priority:_:)](https://developer.apple.com/documentation/swiftui/view/task(id:priority:_:)).

## API surface

| API | Notes |
|---|---|
| `onAppear(perform:)`, `onDisappear(perform:)` | implemented |
| `task(priority:_:)`, `task(id:priority:_:)` | implemented (`Task` on the main actor; the browser host installs `JavaScriptEventLoop`) |
| `onReceive`, `onChange` (see `ScrollView` session) | `onChange` implemented; `onReceive` missing (no Combine) |
| Scene phase, `onOpenURL`, `onContinueUserActivity` | missing |

## Behaviour

`AppearanceActionNode` is transparent for layout; when it is created it enqueues the appear
action with the runtime's scheduler, so the action runs in the same flush right after the update
pass that inserted the view (state it changes re-renders before the frame is painted, which is
what the fixture's count text shows); when the node is unmounted (its branch left the tree) it
enqueues the disappear action. `TaskNode` enqueues the start the same way and creates a
`Task(priority:)` running the closure on the main actor; unmounting cancels it, and an `update`
whose `id` differs cancels and starts again. Tasks continue after their view tree is gone (as in
SwiftUI until cancelled); observation callbacks hold their node weakly so such a late mutation
of an observed model is ignored rather than reviving a dead node.

## Measured (macOS 26.2, `lifecycle/appear`, 2026-09-02)

| Property | Value | Probe |
|---|---|---|
| Appear before the first capture | the count text reads "A1 D0" in the initial frames (35.5 wide): the appear action's state change is applied before the harness captures | `counts` |
| Disappear | hiding the child logs "A1 D1" (33.5 wide) in the same capture; showing it again "A2 D1" | steps `hide`, `show` |
| Task timing | a `.task` that sets the model runs after the harness capture on macOS but before the browser's first capture (the JS event loop turns before the paint), so it has no golden | (removed fixture) |

## Verification (2026-09-02)

Tier A: `lifecycle/appear` exact with both steps. Tier B frames exact in all three browsers
(≤ 0.23 % pixels). `LifecycleTests` cover appear/disappear ordering and task start, cancel on
id change, cancel on removal and completion. wasm js tests pass.

## Not yet covered

Appear ordering between siblings and parents (SwiftUI runs parents' actions after children's in
some cases; ours run in tree-creation order), `onReceive`, scene-phase actions, tasks inheriting
the view's environment (`@Environment` values inside the closure come from the enclosing body).
