# FocusState, focused

Apple docs: [FocusState](https://developer.apple.com/documentation/swiftui/focusstate),
[focused(_:equals:)](https://developer.apple.com/documentation/swiftui/view/focused(_:equals:)),
[focused(_:)](https://developer.apple.com/documentation/swiftui/view/focused(_:)).

## API surface

| API | Notes |
|---|---|
| `@FocusState` (`Bool` and optional `Hashable` forms), `FocusState.Binding` | implemented |
| `focused(_:)`, `focused(_:equals:)` on a view containing a text field | implemented (the first text field in the modified subtree is the focus target) |
| Tab between fields, click to focus, blur | the browser's, mirrored into the state through the host's focus/blur events |
| `focusable()`, `FocusedValue`, `@FocusedBinding`, `focusSection`, `prefersDefaultFocus`, `defaultFocus`, focus on buttons and custom views, `onKeyPress`, `keyboardShortcut`, arrow-key navigation in lists | missing |

## Behaviour

`_FocusStateBox` (a node slot) holds the value and the registered targets (`FocusedNode`s,
each reporting the `TextFieldNode` identifier under it). Writing the state through the wrapper
or its binding records the value, invalidates the owning node and calls
`Runtime.focusTextField` with the target's identifier (or `nil`); the canvas host moves the
browser focus to the input of the field the runtime focused when it refreshes its overlay.
Every path that changes the focused field — a press on a field, the host's focus and blur
events (`Runtime.textField(_:focused:)`, which Tab drives), programmatic changes — goes through
`focusTextField`, which notifies every focus state (`focusDidChange`) so bindings follow the
user's focus without moving it again. A `focused` modifier created while its state already
holds its value focuses at once.

## Measured (macOS 26.2, `focus/basic`, 2026-09-03)

| Property | Value | Probe |
|---|---|---|
| Base state | two 24 pt fields, the status "Focused: none", a bordered button; no focus ring in the hosted (non-key) window | `name`, `email`, `status`, `button` |
| Programmatic focus | Apple's frames after the step report "Focused: email" (91.5 wide) but its pixels were captured before the repaint, so the step is verified by tests and the probe instead | (removed step) |

## Verification (2026-09-03)

Tier A: `focus/basic` exact. Tier B 1/1 in Chromium and WebKit; Firefox differs by its width
hinting on "Focus email" and "Focused: none". `FocusTests` cover presses, the button setting the
state, host blur and focus events, clearing, and the Boolean form. `Playwright/focus-probe.mjs`
checks click, Tab, blur and programmatic focus in headless Chromium (the browser's active element
follows). wasm js tests pass.

## Not yet covered

Focus on non-text views, the focus ring's real look, `FocusedValue`, key handling, the focus
order across presentations, restoring focus after a sheet closes.
