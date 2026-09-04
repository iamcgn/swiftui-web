# Keyboard: focus, key presses, commands, shortcuts, list and menu navigation

Apple docs: [onKeyPress](https://developer.apple.com/documentation/swiftui/view/onkeypress(_:action:)),
[keyboardShortcut](https://developer.apple.com/documentation/swiftui/view/keyboardshortcut(_:)),
[focusable](https://developer.apple.com/documentation/swiftui/view/focusable(_:)),
[onMoveCommand](https://developer.apple.com/documentation/swiftui/view/onmovecommand(perform:)).

## API surface

| API | Notes |
|---|---|
| `KeyEquivalent` (arrows, escape, delete, deleteForward, return, space, tab, home, end, pageUp, pageDown, clear, characters), `EventModifiers`, `KeyPress` (`phase`, `key`, `characters`, `modifiers`, `Phases`, `Result`) | implemented; key-up phases never fire (hosts send key-downs and repeats) |
| `onKeyPress(_:action:)`, `onKeyPress(_:phases:action:)`, `onKeyPress(phases:action:)`, `onKeyPress(action:)`, `onKeyPress(keys:phases:action:)` | implemented on the focused view and its ancestors; `onKeyPress(characters:)` (needs `CharacterSet`) missing |
| `onMoveCommand`, `MoveCommandDirection`, `onExitCommand`, `onDeleteCommand` | implemented |
| `keyboardShortcut(_:modifiers:)`, `keyboardShortcut(_:)` (incl. optional), `KeyboardShortcut`, `.defaultAction`, `.cancelAction`, `Localization` | implemented (localization accepted, not applied) |
| `focusable(_:)`, `focusable(_:interactions:)`, `FocusInteractions` | implemented: a focusable element that takes key presses; interactions accepted |
| `focused(_:)` / `focused(_:equals:)` on buttons and focusable views | implemented (was text fields only, `Docs/elements/Focus.md`) |
| `List` selection by keyboard | implemented: Up/Down, Home/End, Shift ranges |
| Menus by keyboard | implemented: Up/Down highlight, Return/Space activates, Escape closes |
| Escape dismissing sheets, popovers, alerts and menus | implemented |
| Tab / Shift-Tab focus traversal (`Runtime.focusOrder`, `moveFocus`) | implemented 2026-09-04: controls, text fields, focusable views and selectable lists in paint order, wrapping; the topmost modal presentation's alone while one is up; the host mirrors the focus into its overlay |
| Arrow keys on a focused slider or stepper (Up/Right increment, Down/Left decrement) and on a segmented or radio picker (previous/next option; Down opens a pop-up) | implemented 2026-09-04 in the runtime; the browser's range input follows the runtime's value |
| Space / Return activating the focused control | implemented 2026-09-04 in the runtime; a consumed press keeps the browser's overlay button from clicking too |
| `onKeyPress(characters:)`, `onCommand`, `onPasteCommand`, `onCopyCommand`, `focusSection`, `defaultFocus`, `prefersDefaultFocus`, `FocusedValue`, `@FocusedBinding`, Tab order control, `onPlayPauseCommand`, Cmd/Ctrl ranges in lists, type-to-select | missing |

## Behaviour

**Focus.** `Runtime.focusedIdentifier` is the semantics identifier of the element with keyboard
focus: any interactive node (buttons, toggles, pickers, lists with a selection) or a
`focusable` view; a focused text field sets it too. `Runtime.focus(semanticsIdentifier:keyboard:)`
and `blur` move it; `keyboard` (the host passes `:focus-visible`) decides whether the focus ring
shows. The canvas host mirrors both ways: the overlay's `focus`/`blur` events set the runtime's
focus, and after each frame the element whose identifier the runtime holds is focused when it
is not already the document's active element (programmatic `FocusState` changes, a click on a
focusable view). Focusable lists and views get `tabindex="0"`; a list with a selection is a
`listbox` (its rows stay their own elements).

**Dispatch.** `Runtime.keyDown(KeyEvent) -> Bool` (the host's `window` `keydown`; a text field's
input keeps its own keys except Escape) builds a
`KeyPress` and tries, in order: the focused node and its ancestors (`KeyPressNode`,
`CommandNode`, a list's own navigation) until one consumes the press; the topmost menu; Tab moving focus; Space or Return
activating the focused control; keyboard shortcuts in presented content (a sheet's
default and cancel buttons); Escape dismissing the topmost presentation; the window's
keyboard shortcuts. A consumed press has its browser default prevented. Steppers and sliders
no longer need their overlay's native arrow handling: the runtime adjusts them and the
consumed press stops the range input from moving twice.

**Lists.** Up/Down select the previous/next row from the last selected one (the first or last
row when nothing is selected), Home/End the first/last; Shift extends a multiple selection from
the anchor row (the last row picked without Shift). A focused list paints its selection in the
accent colour at 25 % (unverified) instead of the grey.

**Menus.** Up/Down move a highlight over the rows (wrapping), painted as a black 10 % rounded
band 5 pt in from the panel's sides (unverified); Return or Space activates the highlighted row
and closes every menu; Escape closes the menu. Space on a focused pull-down or pop-up button
opens it through the overlay button's click.

**Focus ring.** For keyboard focus on anything but a text field (which paints its own) or a
list, the runtime strokes the accent colour at 50 %, 3 pt, around the element's frame with
6 pt corners (unverified: no focused golden).

## Measured (macOS 26.2, `keyboard/basic`, 2026-09-04)

| Property | Value | Probe |
|---|---|---|
| Layout | `focusable`, `onKeyPress`, the commands and `keyboardShortcut` do not affect frames | `focusable` (71 × 28 for a padded "Focus me"), `buttons` |

Keys, focus rings and highlights cannot be captured by the golden window (the harness's
focus steps do not repaint), so the metrics above are unverified and marked so.

## Verification (2026-09-04)

Tier A: `keyboard/basic` exact. Tier B 1/1 in Chromium (1.18 %), WebKit and Firefox.
`KeyboardTests` cover list arrow keys and Shift ranges, `onKeyPress` and the commands on a
focused view, the focus ring, shortcuts (⌘S, default and cancel actions), Escape with and
without a cancel button in the sheet, and menu highlight/Return/Escape; `Playwright/keyboard-probe.mjs`
drives the same in Chromium through the overlay (13 checks, Tab included). wasm js tests pass.

## Not yet covered

The real focus ring, list highlight and menu highlight looks; Tab order control (`focusSection`);
Cmd-click and Shift-click ranges; key-up phases; `onKeyPress(characters:)`; commands beyond
move/exit/delete; focus restoration after a presentation closes; key equivalents shown in menus.
