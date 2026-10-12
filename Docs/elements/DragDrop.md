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
| `FileRepresentation` (`SentTransferredFile`, `ReceivedTransferredFile`) | implemented with synchronous closures (Apple's are `async`): a drag's payload must be ready when the host hands it to the system. A received file is a temporary file (a `memory:` URL on wasm, read by `Data(contentsOf:)`) |
| Drags to and from other apps and the browser page | implemented (2026-10-11, below): the browser host's HTML5 drag, the AppKit host's `NSDraggingSession` and dragged types |
| `ForEach.dropDestination(for:action:isTargeted:)` (the action's `Int` is the insertion offset), `onInsert(of:perform:)` (the values, not item providers) | implemented: a drop between a list's rows; the list paints an insertion line (approximate, unmeasured) |
| `exportableToServices(_:)`, `exportableToServices(_:onEdit:)` | accepted without effect: there are no system services in a browser and the native host does not register with them |
| `importsItemProviders`, `PasteButton(supportedContentTypes:payloadAction:)` | missing (`NSItemProvider`) |

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

## Across the app boundary (2026-10-11, sw-dragdrop-os)

The runtime's drag stays pointer-driven; hosts carry it over the boundary through
`HostedScene`'s external entry points (`hasDragSource(at:)`, `beginExternalDrag(at:)`,
`externalDragItems()`, `externalDragPreview()`, `externalDragUpdated(types:at:)`,
`externalDragExited()`, `externalDrop(items:at:)`, `externalDragEnded(dropped:)`), with
`ExternalDragItem` (a MIME type or identifier, text, bytes, a file name) as the currency.

- **Items**: a `_TransferItem` exports itself as `text/plain` (a `String`), `text/uri-list` (a
  `URL`), its data representations under their MIME types (`UTType._mime`: JSON, PNG, …; the
  identifier itself for custom types) and its file representations with the file's bytes and
  name. An outside drag becomes a `_TransferItem(external:)` whose exporters give each item's
  text, URL, bytes and file; destinations load through their type's importers, matched by
  content type (`UTType.conforms(to:)`, coarse: plain text, text, image, data). Before the drop
  the host only knows the types: an *announced* item is accepted by type alone (`canLoad`),
  the data decides at the drop.
- **Browser host** (`CanvasHost`): a press on a drag source marks the canvas `draggable` for
  that press (other gestures never become system drags); `dragstart` lifts the payload at once
  (the browser fires it before the scene's 4 pt threshold), fills the `DataTransfer` (text,
  base64 for bytes, `DownloadURL` for files) and paints the lifted preview into an offscreen
  canvas for `setDragImage`; the scene paints no preview of its own while the system carries
  the drag, and `pointercancel`/`pointerup` are ignored until `dragend`. `dragover` asks the
  scene (own drag or outside types) and prevents the default when a destination accepts;
  `dragleave` untargets (an outside drag ends); `drop` reads the strings at once and files
  through `arrayBuffer()` before delivering; `dragend` reports whether another page took the
  drag. `Playwright/dragdrop-probe.mjs` drives `dragdrop/external` with synthetic `DragEvent`s
  in Chromium: 14 checks (the DataTransfer's text, acceptance, the green targeted fill, the
  dropped label, an outside text drop, a PNG refused).
- **AppKit host** (`RuntimeView`): once the scene lifts a payload, `mouseDragged` starts an
  `NSDraggingSession` with a pasteboard item (string, URL, data by type, files written to a
  temporary directory and offered as file URLs) and the preview rendered by the CoreGraphics
  painter as the drag image; the view registers for strings, URLs, files, images and data, and
  `draggingEntered/Updated/Exited`, `performDragOperation` and the session's end forward to
  the scene. Built and compiled; not driven by a test (AppKit's session needs a real event).
- **Lists**: `ListContentNode` is a drop target when a `ForEach` in it has a drop; the insertion
  offset is before the first row of that `ForEach` whose middle the point is above, else after
  its last; a 2 pt accent line with a ring at its leading end marks it while targeted.

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

## UIKit (2026-10-12, uk-dragdrop, `Packages/UIKitWeb/Sources/UIKitWebCore/Events/DragDrop.swift`)

`UIDragInteraction` / `UIDragInteractionDelegate` (`itemsForBeginning`, `previewForLifting`,
`sessionWillBegin`, `session:didEndWith:`, `sessionAllowsMoveOperation`,
`sessionIsRestrictedToDraggingApplication`), `UIDropInteraction` / `UIDropInteractionDelegate`
(`canHandle`, `sessionDidEnter` / `Update` / `Exit` / `End`, `performDrop`), `UIDragItem`
(`itemProvider`, `localObject`, `previewProvider`), `UIDragPreview` and its parameters,
`UIDropProposal` / `UIDropOperation`, the `UIDragSession` / `UIDropSession` protocols (`items`,
`location(in:)`, `localDragSession`, `hasItemsConforming(toTypeIdentifiers:)`,
`canLoadObjects(ofClass: String.self)`, `loadObjects(ofClass:completion:)`, `localContext`,
`allowsMoveOperation`). Collection views: `dragDelegate` / `dropDelegate`
(`UICollectionViewDragDelegate`, `UICollectionViewDropDelegate` with `UICollectionViewDropProposal`'s
intent and a `UICollectionViewDropCoordinator` of `UICollectionViewDropItem`s carrying the
source index paths of a reorder and the destination), `dragInteractionEnabled`, `hasActiveDrag`
/ `hasActiveDrop`; table views the same (`UITableViewDragDelegate`, `UITableViewDropDelegate`,
`UITableViewDropProposal`, `UITableViewDropCoordinator`).

Behaviour: a finger held 0.5 s within 10 pt (a pointer: 4 pt of travel, no wait) on a view
with a drag interaction, or on a cell of a table or collection with a drag delegate, asks for
the items and lifts them; the lifted view (the delegate's preview, else the view or cell) is
painted at 0.8 opacity under the pointer keeping the grab offset, the cursor is `grabbing`. The
deepest drop interaction (or table / collection drop delegate) under the pointer that can
handle the session is targeted: it hears `sessionDidEnter`, its proposal is asked on every
move, `sessionDidExit` when the pointer leaves. Release performs the drop when the proposal is
copy or move and the source hears the proposal's operation (`forbidden` as forbidden, `cancel`
with no target). A table's or collection's destination index path is the row or item under the
pointer, else the end of the section under it. The same session crosses the app boundary
through the host's entry points as SwiftUI's does (`Docs/elements/DragDrop.md`, "Across the app
boundary"): the items' providers become `text/plain` (text types), `text/uri-list` (URLs) or
their bytes, a drag from outside opens a session of its announced types whose data arrives
with the drop; the system draws its own image, so no preview is painted then. Foundation's
`NSItemProvider` loads on a queue of its own: a `UIDragItem` fetches its values as it is made
and the drop finds them (WebFoundation's stand-in on wasm gives them at once); an app on a
native host that needs the string in the same event can `_preloadText`. Inside a representable
the hosted tree's session reaches the SwiftUI runtime through `_PlatformViewTree`'s drag
hooks: the runtime asks the tree under the point for drag sources, paints the tree's preview
over its content and forwards the external entry points (a drag from outside lands in the tree
under the point when nothing of the runtime's takes it). `uikit/events/dragdrop` (pixels
0.48 % at rest), `DragDropTests`, `HostedDragDropTests`, `Playwright/uikit-dragdrop-probe.mjs`
(the mouse drag, the browser's system drag, a drag from outside, a refused type).

## Open

- UIKit: drops between a UIKit tree and SwiftUI destinations in the same window (sessions stay
  with their framework except across the app boundary), `UICollectionViewDropPlaceholder`,
  the lift and drop animations, `UITargetedDragPreview`, spring-loading, multiple items added
  to a session, the data source's `moveItemAt` from a reorder drop (the delegate rewrites its
  data), `UIPasteConfiguration`.
- The AppKit drag session by hand; the insertion line's geometry; snap-back animation on
  cancel; `importsItemProviders`; `async` file representation closures.
- `UIPasteboard`: reading the system clipboard (the browser hands it only to paste events),
  `UIPasteboard.changedNotification`, `detectPatterns`, `UIPasteControl`, `canPerformAction`
  with selectors, a text field's own selection for its edit actions.
