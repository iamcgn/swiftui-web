# 0018 — Phase 9: the later sweep, in dependency order

Date: 2026-10-09
Status: accepted

## Context

Phase 8's gap sweep (decision 0016) finished every `next` and `soon` item of `Docs/todo.json`
but `pf-browser-sessions`, which needs a person at a browser. The 48 `later` items were parked
because each needs a decision, a new subsystem or a platform; the project's owner has asked for
the whole backlog to be finished ("I want the whole thing done"), so the decisions those items
wait on are taken here, and the items are ordered by what unblocks what rather than by
framework.

## Decision

Phase 9 works the `later` items in the order below (one item per commit set, each through the
element workflow, each recorded in `Docs/support.json`, `Docs/todo.json` and the roadmap's Phase
9 table). An item whose detail names a decision gets it here:

- **Symbols** (`sw-symbols`): Lucide stays the glyph source (ISC licence; the catalog ships).
  Fidelity work is about layers, rendering modes, `variableValue` and the metrics table, not a
  new source. Apple's SF Symbols are not redistributable and are not an option.
- **AppKit representables** (`ix-appkit`): `NSViewRepresentable` and
  `NSViewControllerRepresentable` compile everywhere. The native macOS host (Tools/Host) hosts
  the real `NSView` in its window over the painted content; the browser and Linux hosts lay the
  representable out as an empty, sized view and record the gap in the support matrix. There is
  no AppKitWeb.
- **Other frameworks** (`sw-frameworks`): `Charts` becomes a package of its own over the display
  list (`Packages/Charts`, `import Charts` unmodified) with the marks apps reach for first
  (`BarMark`, `LineMark`, `PointMark`, `AreaMark`, `RuleMark`, axes, legends); `Map`,
  `VideoPlayer` and `WebView` are DOM elements positioned under the canvas by the host with
  their painted stand-ins in goldens. Each is its own support section; a tile source for `Map`
  is the browser's `<iframe>`-free OpenStreetMap raster tiles, fetched by the host (no key, no
  cost), documented as approximate.
- **Linux** (`pf-linux`): the Cairo painter (the display list is already backend-neutral) and a
  GTK4 window; the WebKitGTK host after it. Built and tested in CI's `swift:6.3.3` container
  with the distribution's cairo and gtk4 packages.
- **Browser sessions** (`pf-browser-sessions`): stays `planned` until a person runs the IME,
  autofill and VoiceOver sessions; nothing in Phase 9 claims those results.

### Order

| # | Item | Why here |
|---|---|---|
| 1 | `pf-web-foundation-gaps` | `String.Encoding`, `URLComponents`, named time zones, `DateFormatter`/`Date.FormatStyle`, `wrappingComponents`, `Data` slices: the formatting and calendar pieces that `sw-label-forms`, `sw-slider-stepper`, `sw-timeline`, `sw-table` and the UIKit pickers call. |
| 2 | `sw-rtl` | `layoutDirection` through the layout substrate before any more layout work (stacks, grids, custom layouts, shapes, text, alignment guides). |
| 3 | `sw-dynamic-type` | The text-style tables at every category and `ScaledMetric`; the text items after it build on them. |
| 4 | `sw-subviews` | `ForEach(subviews:)`, `Group(subviews:)`, `containerValues`; `sw-table` and `sw-custom-layout` use the container machinery. |
| 5 | `sw-custom-layout` | `Layout.Animatable`, cache invalidation, `GridLayout` as a value. |
| 6 | `sw-safe-area` | `GeometryProxy.safeAreaInsets`, per-element `safeAreaInset`, indicators at the inset. |
| 7 | `sw-shapes` | `strokedPath` as an outline, `ContainerRelativeShape`, `Shape.role`. |
| 8 | `sw-gradients` | Elliptical and mesh gradients, `ShapeStyle.in`, gradient opacity. |
| 9 | `sw-effects` | Effect values under animation, `drawingGroup` semantics. |
| 10 | `sw-images` | Catalog forms (PDF, SVG, slicing, dark variants), `Image(size:label:renderer:)`. |
| 11 | `sw-symbols` | Layers, rendering modes, `variableValue`, the full metrics table (Lucide stays). |
| 12 | `sw-asyncimage` | Cancellation, the URL cache, the phase transaction. |
| 13 | `sw-text-selection` | Drag selection over painted text, copy, the highlight; `sw-texteditor` needs it. |
| 14 | `sw-texteditor` | Selection binding, find, `lineLimit`, long content. |
| 15 | `sw-label-forms` | Context-dependent label styles, `LabeledContent(_:value:format:)` (item 1's formats). |
| 16 | `sw-content-unavailable` | Inside lists and navigation, iOS centring. |
| 17 | `sw-slider-stepper` | Slider styles, vertical sliders, stepper repeat and formats. |
| 18 | `sw-colorpicker` | `<input type=color>` and the native colour panel, `CGColor` binding. |
| 19 | `sw-hover-looks` | `hoverEffect`, hovered control looks, the tooltip. |
| 20 | `sw-dark` | `colorSchemeContrast`, per-presentation schemes, dark chrome verified. |
| 21 | `sw-timeline` | `lowFrequency`, pausing when hidden, calendar and time zone from the environment (item 1). |
| 22 | `sw-previews` | The `#Preview` macro keeping its body for the gallery, `PreviewModifier`, traits. |
| 23 | `sw-sharelink` | `Transferable` items, previews, `navigator.share` and the sharing picker. |
| 24 | `sw-toolbar` | `toolbarBackground`, roles, title display modes, customisation, `NSToolbar` natively. |
| 25 | `sw-splitview` | Sidebar material and toolbar, the draggable divider, collapsing, `preferredCompactColumn`. |
| 26 | `sw-windows` | `commands` and the menu bar natively, window dragging and resizing, `DocumentGroup`, restoration. |
| 27 | `sw-table` | Columns, groups, styles, resizing, context menus, scrolling. |
| 28 | `sw-dragdrop-os` | `DataTransfer` and `NSDraggingSession`, `FileRepresentation`, list drop indices. |
| 29 | `sw-list-editing-rest` | Swipe cell geometry, the Delete reveal, lifted rows, trackpad swipes. |
| 30 | `sw-list-looks-rest` | Focused selection, lazy rows, hover effects, pinned header shadows. |
| 31 | `sw-ios-presentation-rest` | Material blur in sheets and alerts, stacked alert buttons, `fullScreenCover`, five tabs, badges. |
| 32 | `sw-mac-presentation-looks` | Window-list capture in the AppKit golden host; the macOS panels measured. |
| 33 | `uk-appearance` | `UIAppearance` proxies applied on entering a window. |
| 34 | `uk-scenes` | `UIWindowScene`, `UISceneDelegate`, lifecycle notifications, several windows, feedback generators. |
| 35 | `uk-keyboard` | `UIKeyCommand`, presses, `UIFocusSystem` and the focus ring; `uk-text-input` needs the responder path. |
| 36 | `uk-text-input` | `UITextInput`, `UIKeyInput`, `UITextInteraction` through the host overlay. |
| 37 | `uk-controls-rest` | Slider images, segment images and widths, stepper repeat, page control interaction. |
| 38 | `uk-tabbar` | Badges, the More tab, `UITabBarAppearance`, customisation. |
| 39 | `uk-table-rest` | The grouped style, row animations, swipe widths, lifted rows, appearances, right-to-left (item 2). |
| 40 | `uk-collection-rest` | Estimated dimensions, supplementary items, paging, decorations, reordering, outlines. |
| 41 | `uk-dragdrop` | `UIDragInteraction`/`UIDropInteraction` and the table and collection delegates over the runtime's session (item 28). |
| 42 | `uk-splitviewcontroller` | Column styles, display modes, compact collapse; iPad geometry from the simulator. |
| 43 | `uk-system-sheets` | `UIActivityViewController`, `UIDocumentPickerViewController`, `UIImagePickerController` over the hosts' pickers. |
| 44 | `pf-perf` | First frame of the gallery and progress bundles, laziness, a frame budget probe in CI. |
| 45 | `ix-appkit` | Real `NSView`s in the native host, sized empty views elsewhere. |
| 46 | `pf-native-text` | Caret and selection painted natively, IME marked text, real windows, the menu bar, file dialogs. |
| 47 | `pf-linux` | Cairo painter, GTK4 window, WebKitGTK host. |
| 48 | `sw-frameworks` | `Charts` package, then `Map`, `VideoPlayer`, `WebView` as DOM elements. |

`Docs/todo.json` lists the planned items in this order; `Docs/TODO.md` groups them by framework
as before. An item that turns out to need the owner's authorisation (a new service, a cost, a
public release) is reported and skipped until it is given; the items after it continue.
