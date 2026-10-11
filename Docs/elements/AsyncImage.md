# AsyncImage

Apple docs: [AsyncImage](https://developer.apple.com/documentation/swiftui/asyncimage),
[AsyncImagePhase](https://developer.apple.com/documentation/swiftui/asyncimagephase).

## API surface

| API | Notes |
|---|---|
| `AsyncImage(url:scale:)` | implemented; the default placeholder is the placeholder ink filling the frame (measured 2026-10-11: black at 13.7 %, white at 13.7 % in the dark appearance — the ink of `redacted(reason: .placeholder)`) |
| `AsyncImage(url:scale:content:placeholder:)` | implemented |
| `AsyncImage(url:scale:transaction:content:)`, `AsyncImagePhase` (`empty`, `success`, `failure`, `image`, `error`) | implemented; a phase change applies with the transaction (its animation drives the content's transitions, 2026-10-11) |
| `Runtime.imageLoader` (`_ImageLoading`), `Runtime.imageLoadDidFinish()`, `_ImageLoading.cancel(_:)` | the host hook: the browser host loads with `Image` elements, the native host with `Data(contentsOf:)` off the main thread; `cancel` drops a load no view needs |
| Sharing and caching by URL, cancellation on unmount | implemented 2026-10-11: views of one URL share its load (the loaders cache by URL), the runtime counts the views per URL (`retainImageLoad`/`releaseImageLoad`) and the last to unmount while the URL is still loading cancels it (the browser clears the element's source; a later request starts over); a loaded URL stays cached |
| `URLSession` configuration | missing (the browser fetches with its own policy) |

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

## Corners (sw-asyncimage, 2026-10-11)

`asyncimage/phases` gained `defaultPlaceholder`: `AsyncImage(url:)` in a 60 × 40 frame fills it
with the placeholder ink (Tier A exact, Tier C 0.00 %, Tier B 0.11 %). `AsyncImageTests` drive
the shared-load count through two views of one URL (unmounting one keeps the load, changing the
other's URL releases the old one and cancels it while loading, a loaded URL is never cancelled)
and a `transaction:` with a one-second animation (the phase change starts it: the node sets the
runtime's update animation around the content update and keeps it pending for the layout).
`Playwright/asyncimage-probe.mjs` (local, against the served gallery) still loads the served
badge, fails on a missing file and keeps the placeholder for no URL.

## Not yet covered

`URLSession` configuration, and `Image(nsImage:)`/`Image(cgImage:)`.
