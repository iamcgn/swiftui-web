# Map, VideoPlayer and WebView (sw-frameworks, 2026-10-12)

The other Apple frameworks SwiftUI apps reach for (decision 0018): `import MapKit`, `import
AVKit` (and `AVFoundation`), `import WebKit` and `import CoreLocation` resolve to SwiftUIWeb's
own modules (`Sources/MapKit`, `AVKit`, `AVFoundation`, `WebKit`, `CoreLocation`), the way
`SwiftUI` and `UIKit` do. Charts has its own page (`Docs/elements/Charts.md`).

## Host elements

`VideoPlayer` and `WebView` are **host elements**: the view paints a stand-in (black with a
play glyph; white) and places a `_HostElementAnchor` that registers itself when painted, with
its frame and the clip it is visible through (`PaintContext.clipRect`, the scroll view's
bounds). After each render `HostedScene.hostElements()` lists them and the browser host keeps
a `<video>` or `<iframe>` over the canvas at the frame, inside a clipping wrapper at the
visible frame, in a layer between the canvas and the accessibility overlay
(`CanvasHost.updateHostElements`): elements take pointer events themselves, scrolled ones
clip, culled ones (outside the scroll view's margin, so not painted) go. The native macOS host
and the headless runtime show the stand-in only (the real `AVPlayerView` / `WKWebView` would
need the macOS host to import the frameworks the modules shadow). Anything the scene paints
over an element (a sheet, a menu) is under it in the browser: elements are DOM.

`Playwright/frameworks-probe.mjs` checks the elements' presence, frames, sources and
attributes in Chromium; `FrameworksTests` the runtime's reports.

## VideoPlayer (AVKit, AVFoundation)

| API | Status |
|---|---|
| `VideoPlayer(player:)`, `VideoPlayer(player:videoOverlay:)` | implemented: the host's `<video>` with controls, the overlay over it |
| `AVPlayer(url:)`, `AVPlayer(playerItem:)`, `play()`, `pause()`, `rate`, `isMuted`, `volume`, `replaceCurrentItem`, `currentItem`, `timeControlStatus`, `status` | implemented: the element follows the player's state each frame (`@Observable`) |
| `AVPlayerItem(url:)`, `AVAsset`, `AVURLAsset`, `AVQueuePlayer`, `AVPlayerLooper` (loops the element) | implemented (one item at a time) |
| `CMTime` (seconds), `seek(to:)`, `currentTime()`, `addPeriodicTimeObserver` | accepted: seeks are kept, not applied; the observer never fires; `duration` is invalid |
| Playback state back from the element (ended, buffering, the time), picture in picture, AirPlay, `AVPlayerViewController` | missing |

## WebView (WebKit)

| API | Status |
|---|---|
| `WebView(url:)`, `WebView(_ page:)` | implemented: the host's `<iframe>` (sandboxed: scripts, same-origin, forms, popups) |
| `WebPage` (`load(URL)`, `load(URLRequest)` off wasm, `load(html:baseURL:)` as `srcdoc`, `url`, `isLoading`, `reload`, `goBack`, `goForward`) | implemented for loading; navigation state is not reported back (`title` is the host name) |
| `webViewScrollPosition`, `webViewContentBackground`, `webViewLinkPreviews`, the gestures | accepted, no effect |
| `WKWebView` (the UIKit view, `import WebKit`; in a representable or `SFSafariViewController`) | implemented (2026-10-29): a host element like `WebView`'s — the representable tree reports its `_UIHostElementProviding` views after painting, with their frames in window space and the clips of the ancestors that clip; `load(_:)`, `loadHTMLString`, the navigation delegate's start, commit and finish for the load the view began |
| The Open link | every framed page carries an **Open ↗** link over its corner (`<a target="_blank">`): a site that refuses framing (`X-Frame-Options`, `frame-ancestors`) paints nothing in the frame and the page around it cannot tell, so the link is the way to it; the frame is transparent, so what the view drew beneath (the `WKWebView`'s URL and hint) shows there |
| Navigation inside the frame, JavaScript evaluation on another origin, the page's cookies | missing by the browser's rules (a frame of another origin is closed to the page around it) |

## Map (MapKit, CoreLocation)

The map is painted: OpenStreetMap's standard raster tiles (`tile.openstreetmap.org/z/x/y.png`),
fetched by the host like any image URL (`AsyncImage`), placed by Web Mercator at the zoom
fitting the region in the view (fractional zooms scale the next lower level's tiles), with
markers and annotations over them. The look is OpenStreetMap's, not Apple Maps' (recorded as
approximate; `frameworks/map` is frames-only in the pixel tiers). Tiles load through the
network under the host's user agent; OpenStreetMap's usage policy applies to apps that ship
this (heavy use needs a tile provider of one's own; `_MapTiles.tileURL`).

| API | Status |
|---|---|
| `Map(initialPosition:)`, `Map(position: Binding)`, `Map(coordinateRegion:)`, `MapCameraPosition.region/.camera/.automatic/.item`, `MKCoordinateRegion` (span or metres), `MKCoordinateSpan`, `MapCamera` (distance) | implemented: the region fits the view; `.automatic` fits the markers (2 km around one, the world with none) |
| `Marker(_:coordinate:)`, `Marker(_:systemImage:coordinate:)`, `Marker(item:)`, `tint` | implemented: a 28 × 36 balloon (Apple's marker red or the tint, a white dot or the symbol) with its tip on the coordinate and the title below |
| `Annotation(_:coordinate:anchor:content:)` | implemented: the content centred on the coordinate (the anchor is accepted) |
| `ForEach` of map content, `MapContentBuilder` | implemented |
| `CLLocationCoordinate2D`, `CLLocation` (`distance(from:)`), `MKMapItem`, `MKPlacemark`, `MapStyle`, `mapStyle`, `mapControls`, `MapCompass` and the other controls, `UserAnnotation`, `MapPolyline`, `MapCircle`, `onMapCameraChange`, `MapCameraBounds` | accepted: styles, controls, overlays and the user's location paint nothing; the camera never changes |
| Panning, zooming and rotating by gestures, the camera binding written back, imagery and hybrid tiles, polylines and polygons, selection, look-around, geocoding, `CLLocationManager` | missing |

## Open

- Native real views for the macOS host (an `AVPlayerView` / `WKWebView` through
  `Runtime.nativeViewHost`, which the shadowing module names prevent today).
- Map gestures and the camera binding; vector tiles or a styled provider closer to Apple's look.
- Playback events from the element back to `AVPlayer`; `WebPage`'s navigation state.
