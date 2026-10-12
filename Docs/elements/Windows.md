# Windows: WindowGroup, Window, Settings, MenuBarExtra, openWindow, dismissWindow, openSettings

Apple docs: [WindowGroup](https://developer.apple.com/documentation/swiftui/windowgroup),
[Window](https://developer.apple.com/documentation/swiftui/window),
[Settings](https://developer.apple.com/documentation/swiftui/settings),
[openWindow](https://developer.apple.com/documentation/swiftui/environmentvalues/openwindow),
[dismissWindow](https://developer.apple.com/documentation/swiftui/environmentvalues/dismisswindow).

## API surface

| API | Notes |
|---|---|
| `WindowGroup` (`content`, `title`, `id`, `for:` value type with a `Binding<D?>`, and their combinations) | implemented |
| `Window(_:id:content:)` | implemented |
| `Settings(content:)`, `EnvironmentValues.openSettings` | implemented: opens as a window titled Settings |
| `MenuBarExtra` (title, title + systemImage, custom label) | accepted and recorded; browsers have no menu bar, so it is not shown |
| `openWindow(id:)`, `openWindow(value:)`, `openWindow(id:value:)` | implemented |
| `dismissWindow()`, `dismissWindow(id:)`, `dismissWindow(value:)`, `dismissWindow(id:value:)` | implemented (`dismissWindow()` in the main window does nothing) |
| `supportsMultipleWindows` | always true |
| Scene modifiers: `defaultSize` | implemented (the window opens at that size) |
| Scene modifiers: `defaultPosition`, `windowResizability`, `windowStyle` | implemented 2026-10-11: the window opens at the unit point of the host (centred by default), `.contentSize` takes the corner grip away, `.hiddenTitleBar` and `.plain` open it without the 28 pt bar (the lights stay over the content); `menuBarExtraStyle` accepted |
| Window dragging and resizing | implemented 2026-10-11: the title bar beside the lights (the top 16 pt without a bar) drags the window, a 16 pt grip at the bottom-trailing corner resizes a resizable one (the content lays out again at the new size, a `frameResize` pointer over it); both clamp to the host's margins |
| Per-window focus and keyboard routing | implemented 2026-10-11: the window a press lands in is the key window (`Runtime.keyWindow`; a new window is key as it opens) and Tab cycles its controls; a press beside every window gives the keyboard back to the main one; keyboard shortcuts stay app-wide |
| `commands` on scenes: `Commands`, `CommandsBuilder`, `CommandMenu`, `CommandGroup(before:/after:/replacing:)`, `CommandGroupPlacement`, `EmptyCommands`, `ToolbarCommands`, `SidebarCommands`, `TextEditingCommands`, `TextFormattingCommands`, `ImportFromDevicesCommands`, `InspectorCommands` | implemented 2026-10-11: each menu's content is mounted in a hidden tree so its `keyboardShortcut`s match key presses in every host; `Runtime.commandMenus` describes the menus (titles, items with labels, shortcuts, enabled and checked states, dividers; a group's placement names its standard menu) and `performCommand(identifier:)` runs an item; the native host builds `NSApp.mainMenu` from them (the app menu with Quit, File/Edit/View/Window/Help as placements ask, the `CommandMenu`s in order). Browsers have no menu bar: the shortcuts are the commands there |
| `DocumentGroup(newDocument:editor:)`, `DocumentGroup(viewing:viewer:)`, `FileDocument`, `FileDocumentConfiguration` (`document`, `$document`, `fileURL`, `isEditable`), `FileDocumentReadConfiguration`, `FileDocumentWriteConfiguration`, `FileWrapper` (a wasm stand-in for regular files and directories) | implemented 2026-10-11: the main window shows a new document; File > New ⌘N opens another window with one, Open… ⌘O reads a file through the host (the browser's file input, `NSOpenPanel`) into a new window, Save ⌘S and Save As… ⇧⌘S write the frontmost document's bytes through the host (a download named after the file, `NSSavePanel` or the file's URL); the document commands join the File menu. `ReferenceFileDocument` is not offered |
| `WindowGroup` restoration | implemented 2026-10-11: hosts give the runtime a store (`windowStateStore`: localStorage in the browser, the defaults natively) where the open windows' ids and their string, integer, double or boolean values are kept; `restoreWindows()` reopens them at the next launch (other value types and documents are not restored) |

## Behaviour

The app's scenes become window descriptors on the runtime (`Runtime.installWindows`, called
by every host at launch); the first `WindowGroup` (or `Window`) is the main window, as before.

Secondary windows are floating windows inside the host rather than separate browser windows,
so the app's state stays shared and every host has them:

- `openWindow(id:)` opens the scene with that id; `openWindow(value:)` opens the first value
  window group whose type matches, one window per distinct value; opening a window that is
  already open brings it forward. Unknown ids do nothing (and return false to hosts).
- A window is content-sized plus 20 pt of padding (or the scene's `defaultSize`), clamped to
  the host with a 20 pt margin, centred, and cascaded by 24 pt per window already open. A
  28 pt title bar shows three traffic lights (only the red one closes) and the title centred
  in 13 pt semibold; the panel has the presentation corner radius of 10, a shadow ring and a
  hairline border.
- Windows are not modal: presses beside a window reach what is under it; a press inside a
  window behind others brings it to the front. Escape closes the frontmost presentation.
- Inside a window, `dismiss` and `dismissWindow()` close that window; `dismissWindow(id:)` and
  `dismissWindow(value:)` close matching windows from anywhere. A value window's binding writes
  update the window's content.

Covered by `WindowTests` on the headless runtime (scene registration, opening by id and by
value, closing by the control and by action, settings, non-modality). No goldens: SwiftUI opens
real windows the harness does not capture, so the chrome is by eye, not measured.

`WindowTests.modifiersDraggingCommandsAndDocuments` covers the modifiers, dragging and
resizing, the key window, commands (shortcut, description, running an item), documents (new,
open and save through the host hooks) and restoration.

## Real windows on the native host (2026-10-12, pf-native-text)

`SwiftUIWebNative` installs `Runtime.realWindowHost` (`RealWindowHost`): every `.window`
presentation opens as an `NSWindow` of its own (titled, closable, miniaturizable, resizable
when the scene allows; a hidden title bar as a transparent one), cascaded from the main
window, its content view painting the presentation's content through
`Runtime.render(hostedWindow:scale:)` (the content at the window's origin; the painted title
bar, lights and grip stay off, the real window has them) and repainting with each frame of the
main view. Pointer events in the window reach the runtime in root coordinates (the
presentation's virtual frame, which is no longer clamped to the main window), keys go through
the main view's input client (the focused field is the scene's), the window coming to the
front makes its presentation the topmost, resizing it sets the presentation's size and closing
it dismisses the presentation (`Runtime/HostedWindows.swift`: `_HostedWindow`,
`_RealWindowHosting`, `hostedWindows()`, `hostedWindowDidClose`, `hostedWindow(_:didResizeTo:)`,
`hostedWindowDidBecomeKey`). The browser and headless hosts keep the painted windows inside
the main view. `NativeTextAndWindowTests.windowPresentationsOpenAsRealWindows`.

`Tools/Host` opens bundles by double click: `scripts/build-host-app.sh` wraps `swiftui-host`
as `dist/SwiftUIHost.app`, which owns the `.swiftuiweb` package type (a built package
directory renamed) and takes bundle folders as an alternate handler; each bundle the Finder
opens (or that is dropped on the app) gets a window and a server of its own, and the command
line's bundle is served once (AppKit hands it to the open event as well).

## Open

- Real browser windows for `openWindow` (the runtime would need a second host with shared
  state), restoring documents and `Codable` window values, `ReferenceFileDocument`, the
  standard menus' own items natively (Edit's Undo/Cut/Copy/Paste rows come from the responder
  commands, not the menu bar); on the native host, a hosted window's own text input client
  (keys route through the main view), its own toolbar and menu bar focus, and drags between
  windows.
