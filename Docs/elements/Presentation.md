# sheet, popover, alert, dismiss (the presentation layer)

Apple docs: [sheet(isPresented:onDismiss:content:)](https://developer.apple.com/documentation/swiftui/view/sheet(ispresented:ondismiss:content:)),
[popover(isPresented:attachmentAnchor:arrowEdge:content:)](https://developer.apple.com/documentation/swiftui/view/popover(ispresented:attachmentanchor:arrowedge:content:)),
[alert(_:isPresented:actions:message:)](https://developer.apple.com/documentation/swiftui/view/alert(_:ispresented:actions:message:)-8dvt3),
[DismissAction](https://developer.apple.com/documentation/swiftui/dismissaction).

## API surface

| API | Notes |
|---|---|
| `sheet(isPresented:onDismiss:content:)`, `sheet(item:onDismiss:content:)` | implemented (modal, dimmed backdrop) |
| `popover(isPresented:attachmentAnchor:arrowEdge:content:)`, `popover(item:…)` | implemented (`attachmentAnchor` ignored: anchored to the view's bounds; a press outside dismisses) |
| `alert(_:isPresented:actions:message:)` (Text, key and string titles, with and without a message) | implemented (buttons dismiss after their action) |
| `confirmationDialog(_:isPresented:titleVisibility:actions:message:)` | implemented as an alert-style panel |
| `@Environment(\.dismiss)`, `DismissAction` | implemented: dismisses the presentation the view is in, else pops the enclosing `NavigationStack` |
| Pop-up `Picker` menu | implemented (`Docs/elements/Picker.md`): a menu below the button with the selected row checked |
| `fullScreenCover`, `presentationDetents`, `presentationDragIndicator`, `interactiveDismissDisabled`, `Menu`, `contextMenu`, `fileImporter`, `presentationMode`, keyboard dismissal (Escape) | missing |

## Behaviour

`PresentationNode`s are owned by the runtime (`Runtime.presentations`), parented to the root
but outside its layout children. `Runtime.layout` lays them out after the main tree at the
window's size (`layoutPresentations`), `render` paints them last (`paintPresentations`) and
`interactiveNode(at:)` consults them first (`presentationHit`): a hit inside the topmost panel
wins, a press inside a panel but on nothing is consumed, a press outside a modal panel is
consumed, and a press outside a popover or menu dismisses it and is consumed. The modifiers'
bodies read their binding (`_PresentationModifier` → `_PresentationSync`), so observation
presents and dismisses through `PresentationSyncNode`; dismissing from inside (the `dismiss`
action, an alert button, a menu row, a press outside) removes the node at once and resets the
binding. Content is mounted with the presenter's environment plus `dismiss`; `_dismissesOnActivation`
makes an alert's buttons dismiss after running. `Runtime.dismissTopmostPresentation()` is for hosts.

## Geometry (approximate: macOS shows these in separate windows, so there are no goldens)

| Kind | Panel |
|---|---|
| Sheet | the content's ideal size (limited to the window minus 20 pt margins) plus 20 pt padding, centred horizontally, hanging from the top edge; window dimmed by black 20 %; 10 pt corners, 1 pt border at 15 %, a 2 pt shadow ring at 12 % |
| Popover | content plus 20 pt padding beside the anchor on `arrowEdge` (10 pt gap for a 24 × 10 arrow pointing at the anchor's midpoint), kept 20 pt inside the window |
| Alert | 260 pt wide, centred; bold 13 pt title, 11 pt secondary message, the actions in a row, 20 pt padding; window dimmed |
| Menu | rows 22 pt tall (a 22 pt check column, the 13 pt title, 16 pt trailing), at least the pop-up's width, 4 pt above and below, 2 pt under the button (above it when it would overflow); 6 pt corners |

## Verification (2026-09-03)

`presentation/basic` (buttons presenting each kind, a pop-up picker) is exact in Tier A and Tier B
for the base state. `PresentationTests` cover the sheet (geometry, modal blocking, `dismiss`,
`onDismiss`), the popover (anchor, dismissal outside), the alert (buttons dismiss) and the picker
menu (opens, a row selects and closes). `Playwright/presentation-probe.mjs` presents and dismisses
every kind in headless Chromium through the accessibility overlay. wasm js tests pass.

## Not yet covered

The real macOS looks (sheet slide-in and shadow, popover material, alert icon and button
layout), sizes for wide content (no scrolling inside sheets), `Menu`/`contextMenu`, keyboard
dismissal, focus moving into the presentation, `presentationDetents`, `interactiveDismissDisabled`,
`attachmentAnchor` other than the bounds, multiple presentations from one view.
