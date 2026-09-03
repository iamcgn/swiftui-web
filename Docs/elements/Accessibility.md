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
| `accessibilityAction`, `accessibilityAdjustableAction`, `accessibilitySortPriority`, `accessibilityRepresentation`, `accessibilityChildren`, `accessibilityFocused`, rotors, custom content, `accessibilityLabel` on `Image(systemName:)` | missing |

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

## Verification (2026-09-03)

Tier A: `accessibility/basic` exact (layout only). Tier B 1/1 in Chromium and WebKit, Firefox
off by the switch label's width hinting. `SemanticsTests` cover roles, hidden and combined
elements, hint/identifier/value, switch state, slider range and adjustment, stepper adjustment
and list rows. `Playwright/accessibility-probe.mjs` checks the DOM overlay's roles and labels, the
range input round trip and the spinbutton keys. wasm js tests pass. VoiceOver in Safari has not
been checked by hand yet.

## Not yet covered

Custom actions and adjustable actions, sort priority and reading order overrides, live regions
for `updatesFrequently`, headings' levels, `Image(systemName:)` names, focus for the overlay's
static elements, VoiceOver and IME sessions by hand, the semantics of ghosts and animations.
