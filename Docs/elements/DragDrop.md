# draggable, dropDestination, Transferable

Apple docs: [draggable(_:)](https://developer.apple.com/documentation/swiftui/view/draggable(_:)),
[dropDestination(for:action:isTargeted:)](https://developer.apple.com/documentation/swiftui/view/dropdestination(for:action:istargeted:)),
[Transferable](https://developer.apple.com/documentation/coretransferable/transferable).

## API surface

| API | Notes |
|---|---|
| `draggable(_:)`, `draggable(_:preview:)` | implemented: in-app drags with the view (or the preview) painted under the pointer |
| `dropDestination(for:action:isTargeted:)` | implemented: targeting while the pointer is over the view, the values and the drop point in the view's coordinates on release |
| `Transferable`, `TransferRepresentationBuilder`, `ProxyRepresentation`, `CodableRepresentation`, `DataRepresentation` | implemented for in-app transfer: a destination of another type reads the payload through a proxy export, or a data export the destination's type can import |
| `String`, `Data`, `URL` as `Transferable` | implemented |
| `UTType` (the identifiers the representations name) | a minimal `UTType` in the SwiftUI module; no `UniformTypeIdentifiers` module |
| `onDrag` / `onDrop` (`NSItemProvider`), `DropDelegate`, `DropInfo`, `DropProposal` | missing |
| `copyable`, `cuttable`, `pasteDestination`, `PasteButton`, `exportableToServices`, `importsItemProviders` | missing |
| Drags to and from other apps or the browser page, `FileRepresentation`, `dropDestination` on `List` rows with insertion indices | missing |

## Behaviour

- A pointer press on a view with `draggable` (or inside one: a button inside a draggable view
  still starts the drag) that travels 4 pt lifts the payload: the press in flight is cancelled,
  the pointer shows the grabbing hand, and the view (or its `preview`) is painted at 0.8 opacity
  under the pointer, keeping the offset at which it was grabbed (a preview is centred).
- While dragging, the deepest `dropDestination` under the pointer whose type can read the
  payload is targeted (`isTargeted(true)`, then `false` when the pointer leaves or the drag ends);
  other destinations are not.
- Releasing over a targeted destination calls its action with the value(s) and the point in the
  destination's coordinates; releasing elsewhere cancels. The drag is entirely in the runtime, so
  browser and native hosts need no extra support and headless tests drive it with the pointer.
- Type matching: the payload's own type; a `ProxyRepresentation(exporting:)` to the wanted
  type (a `Person` exporting its name drops on a `String` destination); a data export the
  destination's type imports (`DataRepresentation`, `CodableRepresentation`).

Layout is untouched (`dragdrop/basic` exact in Tier A/B/C).

## Open

- Cross-app drags: the browser host would need HTML5 drag events, the native host an
  `NSDraggingSession`; the payload representations are in place for it.
- Drop indicators, snap-back animation on cancel, `List`/`ForEach` reordering.
