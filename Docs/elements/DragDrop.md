# draggable, dropDestination, Transferable, pasteboard

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
| `copyable(_:)`, `cuttable(for:action:)`, `pasteDestination(for:action:validator:)` | implemented: ⌘C / ⌘X / ⌘V around the focused view, through the app's pasteboard |
| `PasteButton(payloadType:onPaste:)` | implemented: a bordered Paste button, enabled while the pasteboard holds a matching value |
| System clipboard | copies hand their text to the host clipboard when the page may write it; reads are not attempted (permission prompts) |
| `onDrag` / `onDrop` (`NSItemProvider`), `DropDelegate`, `DropInfo`, `DropProposal` | not portable: `NSItemProvider` and `NSString` do not exist on wasm, so these forms cannot compile there |
| `exportableToServices`, `importsItemProviders`, `PasteButton(supportedContentTypes:payloadAction:)` | missing |
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

## Pasteboard

The runtime keeps the app's pasteboard as transfer items. With a view focused (`focusable`, a
text field, any focusable control), ⌘C looks for a `copyable` view among the focused view, its
ancestors and its descendants and puts its values on the pasteboard; ⌘X does the same with a
`cuttable` view's action; ⌘V hands the pasteboard's values to the nearest `pasteDestination`
that can read them (through the same type conversions as drops), after its validator. Copies
also write their text to the host's clipboard where the page is allowed to (`navigator.clipboard`
in the browser). `PasteButton` re-evaluates on every copy or cut and is disabled while nothing
of its type is on the pasteboard. Covered by `PasteboardTests`.

## Open

- Cross-app drags: the browser host would need HTML5 drag events, the native host an
  `NSDraggingSession`; the payload representations are in place for it.
- Drop indicators, snap-back animation on cancel, `List`/`ForEach` reordering.
