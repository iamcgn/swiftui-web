# Gestures: DragGesture, LongPressGesture, TapGesture, composition, @GestureState

Apple docs: [Gesture](https://developer.apple.com/documentation/swiftui/gesture),
[DragGesture](https://developer.apple.com/documentation/swiftui/draggesture),
[LongPressGesture](https://developer.apple.com/documentation/swiftui/longpressgesture),
[TapGesture](https://developer.apple.com/documentation/swiftui/tapgesture),
[gesture(_:including:)](https://developer.apple.com/documentation/swiftui/view/gesture(_:including:)),
[GestureState](https://developer.apple.com/documentation/swiftui/gesturestate).

## API surface

| API | Notes |
|---|---|
| `Gesture` protocol (`Value`, `Body`), custom gestures with a `body` | implemented |
| `TapGesture(count:)` | implemented: taps within 0.35 s and 10 pt of each other |
| `LongPressGesture(minimumDuration:maximumDistance:)` | implemented: reports `true` on press, ends (recognises) once the duration passes on the animation clock, fails on movement or an early release |
| `DragGesture(minimumDistance:coordinateSpace:)`, `DragGesture.Value` (`time`, `location`, `startLocation`, `translation`, `velocity`, `predictedEndLocation`, `predictedEndTranslation`) | implemented: `.local` and `.global` spaces (a named space reports local points); velocity from the last two events; the prediction is a quarter second of velocity |
| `MagnifyGesture`, `RotateGesture`, `MagnificationGesture`, `RotationGesture` | API only: no host delivers a pinch or rotation to the canvas, so they never recognise |
| `onChanged`, `onEnded`, `map`, `updating(_:body:)` with `@GestureState` | implemented; `GestureState` resets to its initial value when the gesture ends or fails (the `reset` closures are accepted without effect) |
| `sequenced(before:)`, `simultaneously(with:)`, `exclusively(before:)` and their value types | implemented (`_SequenceValue`, `_SimultaneousValue`, `_ExclusiveValue`) |
| `gesture(_:including:)`, `highPriorityGesture`, `simultaneousGesture` | implemented; `GestureMask` accepted; `simultaneousGesture` behaves as `gesture` (one node takes a press) |
| `onLongPressGesture(minimumDuration:maximumDistance:perform:onPressingChanged:)` | implemented |
| `onTapGesture(count:)` | `count` beyond 1 is still ignored by the tap modifier's own node; use `gesture(TapGesture(count:))` |
| Gesture `Transaction` values, `GestureStateGesture` reset transactions, pinch/rotate from trackpads | missing |

## Behaviour

`GestureNode` is the `_Interactive` node for the modified content: a press that hit-tests to it
(the deepest interactive node under the pointer, so subviews' controls win unless the gesture is
`highPriorityGesture`, which sets `capturesHitTesting`) feeds `pressBegan(at:)`,
`pressMoved(to:)` and `pressEnded(inside:at:)` to the gesture's recogniser as `GestureEvent`s in
the node's space, with the host's event time and the animation clock. The node exposes its
children rather than itself (role `group`, `exposesChildren`). A press in flight keeps its
recogniser through re-renders, so handlers that captured `@State` keep working.

`_GestureRecognizer<Value>` is a class with a phase (`possible`, `active`, `ended`, `failed`) and
handler lists; `emitChanged` and `emitEnded` run the `onChanged`/`onEnded` handlers, and `reset`
handlers restore `@GestureState` when a gesture ends or fails. `TapRecognizer` counts releases
inside the frame; `DragRecognizer` becomes active at `minimumDistance` and reports every move;
`LongPressRecognizer` needs frames (`wantsFrames`): the node subscribes to `Runtime.subscribeFrames`
while it waits, and `tick(clock:)` recognises once `minimumDuration` has passed on the animation
clock, which hosts advance by real elapsed time. `MapRecognizer` wraps another; the sequence,
simultaneous and exclusive recognisers own two and forward events (a sequence switches to its
second once the first ended; exclusive picks the first recogniser to become active and cancels
the other; a long press's initial "pressing" report is not activation).

`Runtime.lastPointerTime` keeps the host's event time for tap intervals and drag velocity.

## Verification (2026-09-04)

`gesture/basic` (resting state): Tier A exact, Tier C 0.00 %, Tier B exact frames in three
browsers. `Playwright/gesture-probe.mjs` drags the box (the label shows the translation and the
drag ends), holds the orange box (pressing, then a long press after the duration), double-clicks
the green box, and holds the purple box (`@GestureState` set while held, reset on release).
`GestureTests` cover drag translation, the minimum distance, local and global points, velocity;
long presses on the clock, cancellation by movement and by an early release; tap counts and
intervals; `@GestureState`; sequenced, simultaneous and exclusive combinations; and priority
against an inner button.

## Not yet covered

Pinch and rotation from the trackpad (`wheel` with the control key, Safari's gesture events),
touch drags competing with scroll views (a touch pan belongs to the scroll view), transactions in
gesture callbacks, `simultaneousGesture` truly alongside a subview's gesture, and tap counts on
`onTapGesture`.
