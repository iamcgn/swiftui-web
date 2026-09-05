# AsyncImage

Apple docs: [AsyncImage](https://developer.apple.com/documentation/swiftui/asyncimage),
[AsyncImagePhase](https://developer.apple.com/documentation/swiftui/asyncimagephase).

## API surface

| API | Notes |
|---|---|
| `AsyncImage(url:scale:)` | implemented; the default placeholder is a 20 % grey fill (SwiftUI shows a system grey; approximate) |
| `AsyncImage(url:scale:content:placeholder:)` | implemented |
| `AsyncImage(url:scale:transaction:content:)`, `AsyncImagePhase` (`empty`, `success`, `failure`, `image`, `error`) | implemented; the transaction is accepted without effect (no phase animation) |
| `Runtime.imageLoader` (`_ImageLoading`), `Runtime.imageLoadDidFinish()` | the host hook: the browser host loads with `Image` elements, the native host with `Data(contentsOf:)` off the main thread |
| Image caching, cancellation on unmount, `URLSession` configuration | missing |

## Behaviour

`AsyncImageNode` asks the runtime's loader for the URL's state when it mounts and whenever a
load finishes (`imageLoadDidFinish`, which the host calls for every completed fetch): `loading`
keeps the empty phase, `loaded` mounts the content with an `Image` whose source is the URL and
its pixel size (drawn by the painters through the same path as catalog images; the browser
painter loads absolute URLs as they are, the native painter gets the decoded `CGImage` from the
loader), `failed` mounts the failure content with `AsyncImageLoadingError`. A nil URL stays in
the empty phase and asks the loader nothing; without a loader every URL stays empty. `scale`
divides the pixel size as for catalog images. The content is re-evaluated only when the state
changes; re-rendering with the same URL keeps the phase, and a new URL starts over.

## Measured (macOS 26.2, `asyncimage/phases`, 2026-09-04)

| Property | Value |
|---|---|
| Nil URL | the empty phase, never a failure |
| A URL that cannot be reached | the empty phase until the load fails, which arrives asynchronously (the capture 50 ms after layout still shows "Loading") |
| Layout | the phase's content lays out as itself; nothing is reserved for the image before it loads |

The golden holds only the empty phase (a non-routable address never resolves in any tier);
loaded and failed images are checked in the browser against the gallery's own served asset and
a missing file (`probe/asyncimage`, browser-only, no golden).

## Verification (2026-09-04)

`asyncimage/phases`: Tier A exact, Tier C 0.00 %, Tier B exact frames. `Playwright/asyncimage-probe.mjs`
loads the served badge asset (the display list draws it by URL), sees a missing file fail, and a
nil URL keep its placeholder. `AsyncImageTests` drive a fake loader through loading, loaded (with
the pixel size and scale) and failed, and cover nil URLs, the default content and a runtime
without a loader.

## Not yet covered

The default placeholder's exact colour, phase transitions with the transaction, cancelling loads
of unmounted views, sharing loads between views of the same URL (the browser caches by URL; the
native loader caches states), and `Image(nsImage:)`/`Image(cgImage:)`.
