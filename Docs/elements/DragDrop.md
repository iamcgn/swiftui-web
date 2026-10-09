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

### UIPasteboard (2026-10-09, uk-pasteboard)

`Packages/UIKitWeb/Sources/UIKitWebCore/App/UIPasteboard.swift`; `PasteboardTests` in both
packages. `UIPasteboard.general` holds items as dictionaries of type identifier to value
(`items`, `setItems`, `addItems`, `numberOfItems`, `changeCount`, `pasteboardTypes()`,
`contains(pasteboardTypes:)`, `itemSet(withPasteboardTypes:)`, `value` / `setValue` and
`data` / `setData` `forPasteboardType`, `values(forPasteboardType:inItemSet:)`), with the
convenience values over the usual identifiers (`string(s)` as `public.utf8-plain-text`,
`url(s)` as `public.url`, `image(s)` as `public.png`, `color(s)` as `com.apple.uikit.color`,
`hasStrings` and friends, `setObjects`, `typeListString` … `typeListColor` as string arrays)
and item providers (synchronous over the wasm stand-in; Foundation's load asynchronously on
Apple platforms, so providers set there land once their strings arrive). Named pasteboards
(`UIPasteboard(name:create:)`, `withUniqueName()`, `remove(withName:)`) are separate stores.

Every write to the general pasteboard hands its first string to the host's clipboard writer
(`navigator.clipboard.writeText` in the browser; reading the system clipboard back is
asynchronous and permission-gated there, so what `string` returns is the app's own) and to a
hosting SwiftUI runtime's pasteboard (`UIKitScene.pasteboardSink`); `string` reads the
runtime's text instead when it copied more recently than the store was written
(`UIKitScene.pasteboardSource`, the runtime's pasteboard generation). `SwiftUIWebUIKit`
connects both for representables (`_PlatformViewTree.connectPasteboard(_:)`, the runtime's
`pasteboardBridge`) and for `UIHostingController`, so a UIKit copy enables a `PasteButton` and
a SwiftUI `copyable` copy reads back as `UIPasteboard.general.string`.

The responder edit actions (`copy(_:)`, `cut(_:)`, `paste(_:)`, `delete(_:)`, `select(_:)`,
`selectAll(_:)`) are open on `UIResponder` and do nothing by default; a text view works on
its `selectedRange` (copy and cut the selection, paste replacing it with the caret after,
delete, select all), a text field, whose selection the host's input element keeps, copies and
cuts its whole text and appends on paste. Typing, the caret, selection and the browser's own
copy and paste in text fields stay the browser's.

## Open

- Cross-app drags: the browser host would need HTML5 drag events, the native host an
  `NSDraggingSession`; the payload representations are in place for it.
- Drop indicators, snap-back animation on cancel, `List`/`ForEach` reordering.
- `UIPasteboard`: reading the system clipboard (the browser hands it only to paste events),
  `UIPasteboard.changedNotification`, `detectPatterns`, `UIPasteControl`, `canPerformAction`
  with selectors, a text field's own selection for its edit actions.
