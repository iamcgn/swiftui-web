# ShareLink

Apple docs: [ShareLink](https://developer.apple.com/documentation/swiftui/sharelink).

## API surface

| API | Notes |
|---|---|
| `ShareLink(item:)`, `ShareLink(items:)`, `ShareLink(_ title, item:)`, `ShareLink(item:label:)`, `ShareLink(items:label:)` with `subject`/`message` | implemented for `URL` and `String` items |
| `ShareLink(item:preview:)`, `ShareLink(items:preview:)`, `ShareLink(_ title, item:preview:)` and the `label:` forms for `Transferable` items; `SharePreview(_:image:icon:)` and the shorter forms | implemented 2026-10-11: an item becomes a `_ShareItem` from its representations in declaration order — a proxy to a `URL` or `String` as a link or text, data with its content type as a file (never imported across types); the preview's title travels, its image and icon are kept for the sheet (which the hosts own) |
| `ShareAction.systemHandler` (`_ShareRequest`: items, subject, message, preview title) | the host's sharer: the browser's Web Share (`navigator.share` with the subject as the title, the message before the texts, the first link as `url`, data as `File`s where `navigator.canShare` accepts them), the native host's `NSSharingServicePicker` (links, texts, the message, image data as `NSImage`s, other data as temporary files) |

## Behaviour

A `ShareLink` is a bordered `Button` whose default label is `Label("Share…", systemImage:
"square.and.arrow.up")`; a press hands a `_ShareRequest` (the items as links, texts or typed
data, the subject, the message, the preview title) to the host's share handler;
`_ShareRequest.files` names data items after the preview title with the content type's
extension and MIME type (PNG, JPEG, text, JSON; else octet-stream). Layout and looks are the
button's and the label's. A `Link` shows the pointing hand while hovered (`pointerStyle(.link)`;
macOS SwiftUI underlines nothing on hover).

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

The share sheet's own looks (the host's), the preview image and icon in a sheet of our own, a
link inside menus and toolbars. `UnavailableAndShareTests.shareLink` covers the request's items,
message, preview title and files, and the link's pointer.
