# Linux (pf-linux, 2026-10-12)

What runs on Linux and how it is built. The core, the headless renderer, UIKitWeb and the
fixtures have built and tested on Linux with Swift 6.3.3 since Phase 7 (the `linux` CI job in
the `swift:6.3.3` container); this item adds a painter and two hosts so an app shows a window
there too. Decision 0018 chose Cairo over Skia (the distribution ships it, `pkg-config` finds
it, no build of a renderer) and GTK4 for the window.

## The Cairo painter (`Packages/WebGraphics`, `WebGraphicsCairo`)

`CairoPainter` paints a `DisplayList` into a `cairo_t`: the same backend-neutral commands the
browser's canvas painter and the macOS CoreGraphics painter take (decision 0012), so nothing in
the runtime knows which one is drawing.

- Fills, strokes (caps, joins, dashes), clips (rects, rounded rects, paths — quadratic curves
  raised to cubics), transforms, gradients (linear and radial through cairo patterns; angular
  gradients approximated by a radial one of the same stops), images (PNGs through
  `cairo_image_surface_create_from_png`, cached per source; bitmaps converted to
  premultiplied BGRA) and text.
- Groups: opacity (`cairo_push_group` / `cairo_pop_group_to_source` with `paint_with_alpha`),
  blend modes (`cairo_operator_t`), masks (`cairo_mask`), shadows (an offset mask of the group
  at 0.6 alpha — an approximation of the blur), filters passed through unchanged.
- Text uses cairo's toy font API (`cairo_select_font_face` with the system family mapped to
  sans-serif, `cairo_show_text`), so glyph shapes and advances are the distribution's; the
  layout comes from the shared `TextLayouter` with `CairoTextEngine` supplying advances from
  `cairo_text_extents` and the heights from `SystemFontMetricsTables` (the same San Francisco
  line metrics the other engines use), which keeps the layout identical to the browser's and
  macOS's even where the glyphs differ.
- `CairoPainter.image(of:size:scale:background:)` renders a list to an image surface,
  `pixel(of:x:y:)` reads one back, `writePNG` writes a file: the tests paint fixtures' display
  lists and check pixels (`CairoPainterTests`: fills, clips, groups, paths, strokes, gradients,
  text, blend modes, masks; `CairoTextEngineTests`).

The system library target `CCairo` asks `pkg-config` for `cairo` (`libcairo2-dev` on Debian,
`brew install cairo` on macOS, where the painter builds and its tests run too — the macOS CI job
installs it).

## The GTK4 host (`Packages/LinuxHost`)

`SwiftUIWebGTK.GTKHost.launch(size:title:root:)` opens a `GtkApplication` window whose
`GtkDrawingArea` paints the runtime's display list with the Cairo painter on each draw and runs
the scene's frame clock from a GTK tick callback. Input goes through GTK4's event controllers:
`GtkGestureClick` (any button) for presses and releases, `GtkEventControllerMotion` for moves,
`GtkEventControllerScroll` for wheels and `GtkEventControllerKey` for keys, which `GTKSceneHost`
turns into the scene's `pressed` / `released` / `moved` / `scrolled` / `key(_:modifiers:)` with
Control standing for the command modifier; typing goes into the focused text field through
`HostedScene.textField(_:didChange:)` from a per-field text cache (there is no IME, selection or
caret of the toolkit's — the scene paints its own caret, as on macOS). Links open with
`xdg-open`. `GTKSceneHost.paint(into:size:)` paints into any `cairo_t`, so the test paints the
window's content into an image surface, presses a button and types into a field without a
display: `GTKHostTests` passes under `swift test` in the container (and on macOS with Homebrew's
gtk4).

`gtk-counter` is the Counter app in a GTK window: `swift run gtk-counter` in
`Packages/LinuxHost`.

## The WebKitGTK host (`Packages/WebKitHost`)

`gtk-host <package-dir>` is `Tools/Host` for Linux: it serves the package's `index.html` and
built wasm bundle from a small POSIX-socket static server on 127.0.0.1 (a MIME table for html,
js, wasm, json, images, css and fonts) and opens it in a `WebKitWebView` inside a GTK4
window; `--port`, `--path`, `--width`, `--height` and `--timeout` as in Tools/Host. It builds in
CI against `libwebkitgtk-6.0-dev`; it has not been run by hand under a display (the CI container
has none), so what the page looks like in WebKitGTK is unverified — the browser fidelity tier
still runs Chromium.

## Open

- The WebKitGTK host under a real display and an `xvfb` smoke run of it and `gtk-counter` in CI.
- Text through cairo's toy fonts: no font fallback, kerning or shaping; a Pango engine would be
  the next step and would give an IME to the GTK host.
- No Linux pixel tier: the goldens are Apple's, and the glyphs differ; `GTKHostTests` and
  `CairoPainterTests` check the painter structurally (pixels of fills, clips and groups).
- Drag and drop, the pasteboard and the share/open/save services in the GTK host (the hooks
  exist on `HostedScene`; the GTK host leaves them nil).
