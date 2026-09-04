# ShareLink

Apple docs: [ShareLink](https://developer.apple.com/documentation/swiftui/sharelink).

## API surface

| API | Notes |
|---|---|
| `ShareLink(item:)`, `ShareLink(items:)`, `ShareLink(_ title, item:)`, `ShareLink(item:label:)`, `ShareLink(items:label:)` with `subject`/`message` | implemented for `URL` and `String` items |
| `ShareAction.systemHandler` | the host's sharer: the browser's Web Share (`navigator.share`, where offered), the native host's `NSSharingServicePicker` |
| `Transferable` items, previews (`SharePreview`), `message` in the sheet | missing |

## Behaviour

A `ShareLink` is a bordered `Button` whose default label is `Label("Share…", systemImage:
"square.and.arrow.up")`; a press hands the items (URLs as strings) and the subject to the host's
share handler. Layout and looks are the button's and the label's.

## Measured (macOS 26.2, `sharelink/basic`, 2026-09-04)

| Property | Value | Probe |
|---|---|---|
| Default button | 92 × 25.58: 12 + the 14.5 × 17.5 symbol + 8 + "Share…" (45.5) + 12; the label's 17.5 + 8 | `plain`, pixels |
| Titled | 77.5 wide with "Send" (31) | `titled` |
| Custom label | a 24 pt `Label` makes a 103 × 32 button | `custom`, `customLabel` |

## Verification (2026-09-04)

Tier A: `sharelink/basic` exact. Tier B: Chromium 0.56 %, WebKit 0.50 %, Firefox 0.57 % (the
symbol is the Lucide stand-in). Tier C: 0.39 %. `UnavailableAndShareTests` cover the size and the handler.

## Not yet covered

The share sheet's own looks, `Transferable` and previews, a link inside menus and toolbars.
