# Accessibility (semantics tree and ARIA overlay)

Apple docs: [accessibilityLabel(_:)](https://developer.apple.com/documentation/swiftui/view/accessibilitylabel(_:)-1d7jv),
[accessibilityHidden(_:)](https://developer.apple.com/documentation/swiftui/view/accessibilityhidden(_:)),
[accessibilityElement(children:)](https://developer.apple.com/documentation/swiftui/view/accessibilityelement(children:)),
[AccessibilityTraits](https://developer.apple.com/documentation/swiftui/accessibilitytraits).

## API surface

| API | Notes |
|---|---|
| `accessibilityLabel`, `accessibilityHint`, `accessibilityValue`, `accessibilityIdentifier` (Text, key and string forms) | implemented |
| `accessibilityHidden(_:)` | implemented (the subtree contributes no elements) |
| `accessibilityAddTraits`/`accessibilityRemoveTraits` (`isHeader`, `isButton`, `isLink`, `isImage` change the role; others stored) | implemented |
| `accessibilityElement(children:)` (`.ignore`, `.combine` make one element; `.contain` keeps the parts) | implemented (combined labels join the parts with ", ") |
| Elements for `Text`, `Image` (label, else the asset name; decorative images none), `Button`, `Toggle` (checkbox / switch), `TextField`, `Slider`, `Stepper`, `Picker` (pop-up, radio group, segmented), `NavigationLink` (button), `List` rows | implemented |
| `accessibilityAction` (kinds, named, labelled), `accessibilityActions { }`, `accessibilityAdjustableAction` | implemented 2026-10-04: a default action makes a static element a button, named actions are buttons inside the element, an adjustable element is a spinbutton the arrow keys step; Escape runs the escape action of the focused element |
| `accessibilitySortPriority`, `accessibilityHeading(_:)`, `updatesFrequently` (live region), `isSelected`, `help` as the description, `accessibilityCustomContent` | implemented 2026-10-04 |
| `accessibilityRepresentation { }`, `accessibilityChildren { }` | implemented 2026-10-04: the replacement view is laid out over the view (never painted or hit); its elements stand in for the view's, or sit under a container element that takes the view's label |
| `@AccessibilityFocusState`, `accessibilityFocused(_:)`, `accessibilityFocused(_:equals:)` | implemented 2026-10-04 over the keyboard focus (the overlay element's focus) |
| `accessibilityRotor` (entries builder, `Identifiable` entries, system rotors), `AccessibilityRotorEntry`, `accessibilityRotorEntry(id:in:)` | implemented 2026-10-04 as navigation landmarks (below) |
| `accessibilityLabel` on `Image(systemName:)` | implemented: the symbol's element takes the label (its name otherwise) |

## Behaviour

`Runtime.semanticsTree()` walks the painted tree (and presentations) in paint order. For a
layout node it gathers the accessibility modifier chain directly above it (`AccessibilityNode`s,
outermost winning); a hidden chain drops the subtree; `.ignore`/`.combine` produce one element
(the node's frame, the given label or the joined labels of the parts, the single part's role
when there is one). Otherwise interactive nodes contribute `semantics` (containers that expose
children, such as lists, also descend), `TextNode` and `ImageNode` contribute static elements,
and attributes apply to every element the subtree yields. `Runtime.adjust(semanticsIdentifier:
increment:)` and `setValue(semanticsIdentifier:value:)` reach sliders and steppers.

The canvas host mirrors the tree as a DOM overlay: `<h2>` for headings, `<div role=img|group>`
for images and groups, `<div>` for text, `<button>` for actionable elements (`role=checkbox` /
`switch` with `aria-checked`, `spinbutton` stepped by the arrow keys, `aria-haspopup=listbox` for
pop-ups, `radiogroup` for segmented and radio pickers), `<input type=range>` for sliders (min,
max, step, value; `input` events set the runtime's value), plus `aria-label`, `aria-valuetext`,
`aria-description` and `data-testid`. `__swiftuiwebDebug.semantics()` returns the tree for tests.

## Actions, order, representation, focus and rotors (2026-10-04)

`AccessibilityAttributes` carries the actions (`_AccessibilityAction`, by kind or name), the
adjustable action, the sort priority, the heading level, the help text, the focus-target flag,
the rotors and the rotor-entry key of a modifier chain; the chain is folded from the outermost
modifier in, so actions, rotors and custom content keep their declaration order. The walk
applies them to the elements a view yields (a view with actions, rotors or a focus target but no
element of its own gets a group element), ordering a container's children by sort priority
(higher first, stable), and resolves rotor entries to the elements marked with their ids after
the whole tree is walked (`SemanticsEntry` keeps the actions and rotors; `SemanticsNode` carries
`customActions`, `headingLevel`, `isLive`, `description`, `isSelected`, `rotors`).
`Runtime.activate` runs an element's default action before a control's own activation,
`adjust` an adjustable action before a slider's or stepper's, `performAccessibilityAction`
(from the host) a named one; the arrow keys and Escape reach them from the keyboard. `help`
(`HelpNode`) contributes the help text as the element's description.

`accessibilityRepresentation` and `accessibilityChildren` build the replacement view as a
second subtree laid out over the content with the content's size (never painted or hit): the
semantics walk lists its elements instead of the content's (a container element first for
`accessibilityChildren`), and the runtime's node lookups include it so a representation's slider
adjusts through the overlay. `@AccessibilityFocusState` reuses the focus-state box: the view's
first element becomes focusable and the state mirrors the keyboard focus.

The canvas host mirrors the additions: headings get `<h1>`…`<h6>` for their level (an element is
recreated when its tag changes), live regions `aria-live="polite"`, help the `title`, selection
`aria-selected`; custom actions become `<button>`s inside the element (assistive technology
lists them; a click performs the action through `performAccessibilityAction`); rotors become a
`<nav>` landmark named after the rotor with a link per entry that focuses the entry's element
(the element is made focusable). `accessibility/actions` (text only, so nothing drifts between
macOS releases) pins the layout; the probe drives the overlay and reads Chromium's own
accessibility tree (`page.accessibility.snapshot`) as the stand-in for a screen reader: the
level-one heading, the custom action button, the spinbutton and the navigation landmark are
there. `AccessibilityActionsTests` cover each API. A VoiceOver session in Safari and an IME
session by hand remain for `pf-browser-sessions`.

## Verification (2026-09-03)

Tier A: `accessibility/basic` exact (layout only). Tier B 1/1 in Chromium and WebKit, Firefox
off by the switch label's width hinting. `SemanticsTests` cover roles, hidden and combined
elements, hint/identifier/value, switch state, slider range and adjustment, stepper adjustment
and list rows. `Playwright/accessibility-probe.mjs` checks the DOM overlay's roles and labels, the
range input round trip and the spinbutton keys. wasm js tests pass. VoiceOver in Safari has not
been checked by hand yet.

## UIKit (2026-10-09, `uikit/accessibility/basic`)

`Packages/UIKitWeb/Sources/UIKitWebCore/Views/UIAccessibility.swift`; `AccessibilityTests`,
`Playwright/uikit-accessibility-probe.mjs` (the overlay, the live region and Chromium's own
accessible tree over the fixture), the UIKitSettings smoke test's accessible-tree pass.

- Elements: `isAccessibilityElement`, `accessibilityLabel` / `Value` / `Hint` / `Identifier`,
  `accessibilityTraits` (`button`, `link`, `image`, `header`, `adjustable` pick the role;
  `notEnabled` is `aria-disabled` (the node's `isEnabled`), `selected` `aria-selected`,
  `updatesFrequently` a polite live region), `accessibilityElementsHidden`,
  `accessibilityFrame` (the window frame unless set), `accessibilityCustomActions`
  (`UIAccessibilityCustomAction(name:actionHandler:)`, `attributedName`; buttons in the overlay
  the host runs by name through `performAccessibilityAction`), `accessibilityElements` (a
  container's children in the order given, views only, in place of its subviews),
  `accessibilityViewIsModal` (a modal subview hides its siblings), `shouldGroupAccessibilityChildren`,
  `accessibilityContainerType`, `accessibilityNavigationStyle`, `accessibilityLanguage`,
  `accessibilityIgnoresInvertColors` (stored). A navigation bar's titles carry the header trait.
- Actions: `accessibilityActivate() -> Bool` (a control sends `touchUpInside` and
  `primaryActionTriggered`; a switch toggles), `accessibilityIncrement` / `Decrement` (open;
  sliders, steppers, page controls, pickers and date pickers override them),
  `accessibilityPerformEscape` / `accessibilityPerformMagicTap` (the superview by default;
  reachable as the actions named `escape` and `magicTap`).
- `UIAccessibility.post(notification:argument:)`: `.announcement` with a string queues an
  announcement; `.layoutChanged` / `.screenChanged` with a view queue a focus move to its
  element (with a string, an announcement). The scene keeps them in `accessibilityEvents` and
  the host takes them (`HostedScene.takeAccessibilityEvents`) after syncing its overlay each
  frame: the canvas host speaks an announcement from a `role="status"` live region beside the
  overlay (the same text twice gets a zero-width space so it is spoken again) and moves the
  browser's focus to the element's overlay node. A hosted UIKit tree inside SwiftUI posts
  through the same queue, which the runtime drains from its platform trees. The settings
  (`isVoiceOverRunning`, `isSwitchControlRunning`, the colour and text ones) are false; the
  motion ones follow the host's reduce-motion setting.
- Measured: the fixture's elements come in view order with the three buttons reordered C, A, B;
  the modal step leaves "Modal" and "Close"; Chromium's accessible tree has the heading, the
  disabled button, the switch, the slider and the custom-action buttons. The pixels (plain
  controls) are within 1.4 %; a selected plain system button's tinted ground was measured for
  it (iOS 26: the tint at 30 % under a white title, 4.5 pt beside and 4.25 above and below the
  title, 5 pt continuous corners), and a slider keeps the frame height it is given.

## Not yet covered

VoiceOver and IME sessions by hand (`pf-browser-sessions`), the semantics of ghosts and
animations, rotor entries over text ranges (accepted, no target), `prepare` closures of rotor
entries (accepted), the `magicTap`, `delete` and `showMenu` kinds reachable only through
`performAccessibilityAction` (no web gesture maps to them); a VoiceOver pass over
`Examples/UIKitSettings` by hand (the browser's accessible tree stands in for it in the smoke
test); `UIAccessibility.post` in a SwiftUI app (SwiftUI's `AccessibilityNotification` is not
modelled yet); `accessibilityPath`, `accessibilityActivationPoint`.
