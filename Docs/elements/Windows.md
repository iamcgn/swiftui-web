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
| Scene modifiers: `windowResizability`, `windowStyle`, `defaultPosition`, `menuBarExtraStyle` | accepted and ignored |
| `DocumentGroup`, `WindowGroup` restoration, `commands` on scenes, window dragging and resizing, per-window focus and keyboard routing | missing |

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

## Open

- Real browser windows for `openWindow` (the runtime would need a second host with shared
  state), window moving and resizing, `DocumentGroup`, restoring windows on reload.
