# sheet, popover, alert, dismiss (the presentation layer)

Apple docs: [sheet(isPresented:onDismiss:content:)](https://developer.apple.com/documentation/swiftui/view/sheet(ispresented:ondismiss:content:)),
[popover(isPresented:attachmentAnchor:arrowEdge:content:)](https://developer.apple.com/documentation/swiftui/view/popover(ispresented:attachmentanchor:arrowedge:content:)),
[alert(_:isPresented:actions:message:)](https://developer.apple.com/documentation/swiftui/view/alert(_:ispresented:actions:message:)-8dvt3),
[DismissAction](https://developer.apple.com/documentation/swiftui/dismissaction).

## API surface

| API | Notes |
|---|---|
| `sheet(isPresented:onDismiss:content:)`, `sheet(item:onDismiss:content:)` | implemented (modal, dimmed backdrop) |
| `popover(isPresented:attachmentAnchor:arrowEdge:content:)`, `popover(item:…)` | implemented: anchored to the view's bounds, a rect in them (`.rect(.rect(_:))`) or a point of them (`.point(UnitPoint)`, 2026-09-18); a press outside dismisses |
| `alert(_:isPresented:actions:message:)` (Text, key and string titles, with and without a message) | implemented (buttons dismiss after their action) |
| `confirmationDialog(_:isPresented:titleVisibility:actions:message:)` | implemented: an alert-style panel on macOS; on iOS a glass popover above its source, its actions stacked as capsules and the cancel button left out (`Docs/elements/iOS.md`, `ios/dialog/basic`) |
| `@Environment(\.dismiss)`, `DismissAction` | implemented: dismisses the presentation the view is in, else pops the enclosing `NavigationStack` |
| Pop-up `Picker` menu | implemented (`Docs/elements/Picker.md`): a menu below the button with the selected row checked |
| `fullScreenCover`, `Menu`, `contextMenu`, `fileImporter`, `presentationMode`, keyboard dismissal (Escape) | implemented 2026-09-04 (`Docs/elements/Keyboard.md`) |
| `interactiveDismissDisabled(_:)` | implemented 2026-09-18: a press outside the presentation and Escape are consumed without dismissing; programmatic dismissal still works (`PresentationTests`) |
| `presentationDetents` (`medium`, `large`; `fraction`, `height` and the selection form accepted), `presentationDragIndicator` | implemented 2026-09-18 for the iOS sheet (`ios/sheet/medium`): the medium detent's floating card and the grabber; no effect on macOS |

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

iOS is measured: the sheet, its medium detent, the alert and the dialog on the iPhone SE
simulator are in `Docs/elements/iOS.md` (`ios/sheet/`, `ios/alert/`, `ios/dialog/`; the golden
captures the whole window). The macOS looks below are by eye.

| Kind | Panel |
|---|---|
| Sheet | the content's ideal size (limited to the window minus 20 pt margins on every side: a taller content is proposed the limit, so a `ScrollView` inside scrolls) plus 20 pt padding, centred horizontally, hanging from the top edge; window dimmed by black 20 %; 10 pt corners, 1 pt border at 15 %, a 2 pt shadow ring at 12 % |
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
dismissal, focus moving into the presentation, detents beyond medium and large. The macOS looks
stay by eye: sheets, popovers and alerts are separate windows the golden harness cannot capture
(`sw-presentations` accepted them as approximate, 2026-09-18; a window-list capture would be
the way to measure them). Several presentations from one view work (`oneViewPresentsASheetAndAnAlert`).
