# What is next

Generated from `Docs/todo.json` by `scripts/gen-progress.py`; edit the JSON, not this file. The same data is shown on the progress page. Priorities: **next** is Phase 8 of `Docs/ROADMAP.md` in order, **soon** the gap sweep after it (what ordinary apps hit), **later** what needs a decision, a subsystem or a platform that does not exist yet. Kinds: *missing* (no API), *accepted* (compiles, no behaviour), *approximate* (behaves, pixels or motion differ), *verify* (behaves, never measured against Apple), *infra* (tooling, docs, site). Marks: ☐ planned, ◐ in progress, ☑ done, ✕ a documented non-goal.

| Framework | Open items | next | soon | later |
|---|---|---|---|---|
| Interop | 1 | 0 | 0 | 1 |
| SwiftUI | 32 | 0 | 0 | 32 |
| UIKit | 20 | 0 | 9 | 11 |
| Platform | 5 | 0 | 1 | 4 |
| **All** | **58** | 0 | 10 | 48 |

## Next (Phase 8, in order)

## Soon (the gap sweep)

### UIKit

- ☐ **UIPageViewController** `uk-pageviewcontroller` · Containers · missing  
  Scroll and page-curl-as-scroll transition styles, the data source and delegate, the page indicator. ([Containers](Packages/UIKitWeb/Sources/UIKitWebCore/Containers))
- ☐ **UIVisualEffectView and the glass** `uk-materials` · Views · approximate  
  Blur and vibrancy effects as a display-list filter group over what lies beneath (the painters have blur); the iOS 26 glass in bars and the scroll pocket is a tint today. The floating tab bar over coloured content is opaque where iOS 26's glass tints what lies beneath (ios/representable/hostingsafearea-tabs is approximate, 5.6 %). ([Bars.md](Docs/elements/UIKit/Bars.md), [iOS.md](Docs/elements/iOS.md))
- ☐ **Layer corners, borders and shadows against pixels** `uk-view-pixels` · Views · verify  
  The painted corners (continuous too), borders and shadows of `uikit/view/*` compared with the simulator's pixels; the fixtures are frames-only where the look is unverified. ([UIView.md](Docs/elements/UIKit/UIView.md))
- ☐ **Trait overrides and observation** `uk-traits` · Views · missing  
  `overrideUserInterfaceStyle` on a view (the window's and `traitOverrides` work), `registerForTraitChanges` and `traitCollectionDidChange` on every change, size classes from the host size, dark samples of the wheels and of presentations other than the alert. ([Dark.md](Docs/elements/UIKit/Dark.md))
- ☐ **Gradient and text layers, display links, animation options** `uk-layers` · Core Animation · missing  
  `CAGradientLayer`, `CATextLayer`, `CADisplayLink` on the scene's clock, `CAAnimationGroup` playback, keyframes through every value, additive animations, `repeat`/`autoreverse`/`beginFromCurrentState` on `UIView.animate` (accepted), `delayFactor`, `scrubsLinearly` and spring velocity on property animators. ([Animation.md](Docs/elements/UIKit/Animation.md))
- ☐ **Layout guides, animated constraints and stacks** `uk-autolayout-rest` · Auto Layout · verify  
  Frames of app-made `UILayoutGuide`s, constraint changes animated by `layoutIfNeeded` inside `UIView.animate`, hugging defaults per control verified, `UIStackView.fillProportionally` and overflow compression against UIKit, spacing after hidden views, solver performance on large trees. ([AutoLayout.md](Docs/elements/UIKit/AutoLayout.md), [UIStackView.md](Docs/elements/UIKit/UIStackView.md))
- ☐ **Blend modes, attributed drawing and CGPath** `uk-drawing-rest` · Drawing · accepted  
  `setBlendMode` and `UIImage.draw` with blend modes (accepted), antialiasing switches and `clear`, per-range attributes with underline and strikethrough, `NSMutableAttributedString`, `CGPath`/`CGMutablePath` on Apple platforms, caching drawn content between frames. ([Drawing.md](Docs/elements/UIKit/Drawing.md))
- ☐ **Accessibility notifications and custom actions** `uk-accessibility` · Accessibility · missing  
  `UIAccessibility.post`, `accessibilityCustomActions`, `accessibilityElements` ordering, `isAccessibilityElement` and traits verified against the overlay the SwiftUI walk produces; a VoiceOver pass over Examples/UIKitSettings. ([Accessibility.md](Docs/elements/Accessibility.md))
- ☐ **UIPasteboard** `uk-pasteboard` · App · missing  
  `UIPasteboard.general` over the runtime pasteboard and the host clipboard writer SwiftUI's `copyable` uses. ([DragDrop.md](Docs/elements/DragDrop.md))

### Platform

- ☐ **IME, autofill and VoiceOver by hand** `pf-browser-sessions` · Browser · verify  
  Japanese and Chinese IMEs and Safari autofill through the overlay input (spike 0.12's risk), a VoiceOver session in Safari; the findings recorded per browser in the matrix. ([ROADMAP.md](Docs/ROADMAP.md))

## Later (needs a decision, a subsystem or a platform)

### Interop

- ☐ **NSViewRepresentable and NSViewControllerRepresentable** `ix-appkit` · AppKit · missing  
  Apps written for the macOS profile reach for AppKit representables; there is no AppKitWeb to host them. Out of scope until a decision says whether an AppKitWeb is worth building or the API should compile as an empty view; recorded here so the choice is visible. ([0014-uikitweb.md](Docs/decisions/0014-uikitweb.md))

### SwiftUI

- ☐ **iOS presentations and bars: the rest** `sw-ios-presentation-rest` · iOS profile · approximate  
  After sw-ios-sheets: the materials' blur (sheets, alerts, the dialog and the tab bar are painted as their colour over the dimmed ground, shadows as rings), alerts with three or more buttons (iOS stacks them) or long titles, a sheet offering both detents and dragging between them, `fullScreenCover`, a dialog without room above its source, bars of four or five tabs, badges and the pill's selection animation, a tap on a date pill opening iOS's calendar popover, the disabled compact picker's undimmed label, selection in edit mode and multiple selection. ([iOS.md](Docs/elements/iOS.md))
- ☐ **Measure the macOS presentation looks** `sw-mac-presentation-looks` · Presentation · approximate  
  The sheet, popover, alert and menu looks on macOS are by eye (separate windows the golden harness cannot capture). A window-list capture (CGWindowListCreateImage over the app's windows after a step presents) in the AppKit golden host would pin the panel geometry, materials and shadows the way `capturesWindow` does on iOS. ([Presentation.md](Docs/elements/Presentation.md))
- ☐ **List editing: the rest** `sw-list-editing-rest` · List · approximate  
  The swipe cells' geometry, colours and easing, the Delete button iOS reveals after a press on the edit circle, the lifted row and the animation while reordering, macOS trackpad swipe actions, the refresh spinner's look and the pull's rubber band, editing across sections, `onInsert` by drop. ([List.md](Docs/elements/List.md))
- ☐ **List looks: the rest** `sw-list-looks-rest` · List · approximate  
  The focused accent selection (the golden window is never key), lazy rows, listRowHoverEffect, the pinned header's gradient shadow, ListSectionSpacing.compact, the section separator tint macOS draws grey, a header-less card's custom section spacing on iOS (derived, not measured), outline chevron presses limited to the chevron. ([List.md](Docs/elements/List.md))
- ☐ **Dynamic Type** `sw-dynamic-type` · Text · missing  
  `dynamicTypeSize` and the content size categories: the text-style tables at every category (measured on the simulator), `ScaledMetric`, the environment from the host's setting. ([Text.md](Docs/elements/Text.md), [iOS.md](Docs/elements/iOS.md))
- ☐ **TextEditor: selection, find, long content** `sw-texteditor` · TextEditor · missing  
  A selection binding, `findNavigator`/`findDisabled`/`replaceDisabled`, `lineLimit` on editors, scrolling of long content, and the NSTextView wrapping parity (texteditor/basic is approximate). ([TextEditor.md](Docs/elements/TextEditor.md))
- ☐ **Selecting text** `sw-text-selection` · Text · accepted  
  `textSelection(.enabled)` only sets the I-beam: drag selection over painted text, copy, the selection highlight in the display list, on both hosts. ([TextScale.md](Docs/elements/TextScale.md))
- ☐ **NavigationSplitView chrome** `sw-splitview` · Navigation · approximate  
  The sidebar's material and toolbar, dragging the divider, collapsing by drag, the styles (accepted), `preferredCompactColumn` in the iOS profile; the splitview/ fixtures out of the 9 % approximate bound. ([NavigationSplitView.md](Docs/elements/NavigationSplitView.md))
- ☐ **Toolbar modifiers with an effect** `sw-toolbar` · Toolbar · accepted  
  `toolbarBackground`, `toolbarRole`, `toolbarTitleDisplayMode` (accepted today), `toolbar(id:)` customisation, `ToolbarCommands`, sheet toolbars, a real `NSToolbar` in the native host. ([Toolbar.md](Docs/elements/Toolbar.md))
- ☐ **Window commands, dragging and documents** `sw-windows` · Windows · missing  
  `commands` on scenes and a menu bar in the native host, dragging and resizing the in-host windows, per-window focus and keyboard routing, `DocumentGroup`, restoration, the accepted scene modifiers (`windowResizability`, `windowStyle`, `defaultPosition`). ([Windows.md](Docs/elements/Windows.md))
- ☐ **Slider styles and stepper repeat** `sw-slider-stepper` · Slider and Stepper · missing  
  `sliderStyle`, tick labels, vertical sliders, the knob shadow; the stepper's press-and-hold repeat and its `formatter`/`format` forms. ([Slider.md](Docs/elements/Slider.md), [Stepper.md](Docs/elements/Stepper.md))
- ☐ **A real colour panel** `sw-colorpicker` · ColorPicker · approximate  
  The browser's `<input type=color>` and the native colour panel behind the well (the preset popover stands in, unverified), a `CGColor` binding, keyboard activation, dropping colours. ([ColorPicker.md](Docs/elements/ColorPicker.md))
- ☐ **Context-dependent labels and formatted values** `sw-label-forms` · Label · missing  
  `Label`'s automatic style by context (icon only in toolbars), multi-line titles, `LabeledContent(_:value:format:)`, the secondary value colour in grouped forms (unmeasured). ([Label.md](Docs/elements/Label.md), [LabeledContent.md](Docs/elements/LabeledContent.md))
- ☐ **ContentUnavailableView in containers** `sw-content-unavailable` · ContentUnavailableView · verify  
  Inside lists and navigation, the iOS vertical centring, the symbol above the title on other platforms. ([ContentUnavailableView.md](Docs/elements/ContentUnavailableView.md))
- ☐ **ShareLink items and previews** `sw-sharelink` · ShareLink · missing  
  `Transferable` items, `SharePreview`, `message`; the browser's `navigator.share` and the native sharing service picker behind it; hover looks for `Link`. ([ShareLink.md](Docs/elements/ShareLink.md), [Link.md](Docs/elements/Link.md))
- ☐ **Right-to-left layout direction** `sw-rtl` · Layout · missing  
  `layoutDirection` through stacks, grids, custom layouts, `layoutDirectionBehavior` on shapes, alignment guides and the text layouter; goldens from a right-to-left locale. ([Layout.md](Docs/elements/Layout.md), [CustomLayout.md](Docs/elements/CustomLayout.md))
- ☐ **Layout protocol corners** `sw-custom-layout` · Layout · missing  
  `Layout.Animatable` (animating layout parameters), `updateCache` reuse across passes and invalidation on environment changes, `GridLayout` as a `Layout` value, rows with more cells than the widest earlier row combined with spans. ([CustomLayout.md](Docs/elements/CustomLayout.md), [Grid.md](Docs/elements/Grid.md))
- ☐ **Shape corners: strokedPath, container shapes, roles** `sw-shapes` · Shape · approximate  
  `Path.strokedPath` as the offset outline (polygons per segment today), `ContainerRelativeShape` following its container, `Shape.role` (stub), `Path(cgPath:)` on Apple platforms. ([Shape.md](Docs/elements/Shape.md))
- ☐ **Elliptical and mesh gradients** `sw-gradients` · Gradient · missing  
  `EllipticalGradient`, `MeshGradient`, `ShapeStyle.in(_:)`, gradient `opacity`, repeat and mirror options (accepted), gradients on images and symbols, the hierarchical fade levels (approximate). ([Gradient.md](Docs/elements/Gradient.md))
- ☐ **Animated effects and drawing groups** `sw-effects` · Effects · accepted  
  Effect values under animation, `drawingGroup(opaque:colorMode:)` (accepted), filtering of content painted outside its frame, `drawingGroup`'s rasterisation semantics. ([Effects.md](Docs/elements/Effects.md))
- ☐ **SF Symbols fidelity** `sw-symbols` · Image · approximate  
  Lucide stands in for every glyph: rendering modes (accepted), multicolour and hierarchical layers, `variableValue`, sizes and names beyond the 240 measured (a full metrics table from the catalog goldens), symbol effects by layer; decision needed on a symbol source with a licence that allows shipping. ([Image.md](Docs/elements/Image.md), [SymbolEffect.md](Docs/elements/SymbolEffect.md))
- ☐ **Image catalog forms and rendering** `sw-images` · Image · missing  
  PDF and SVG catalog sets, slicing metadata, dark-appearance image variants, Display P3 (used as sRGB), `Image(size:label:renderer:)`, `luminanceToAlpha` and `colorMultiply` on images, redaction placeholders for catalog images (approximate). ([Image.md](Docs/elements/Image.md), [Redaction.md](Docs/elements/Redaction.md))
- ☐ **AsyncImage caching and transactions** `sw-asyncimage` · AsyncImage · accepted  
  Cancellation on unmount, a cache keyed by URL, the phase transaction (accepted), the default placeholder colour (approximate). ([AsyncImage.md](Docs/elements/AsyncImage.md))
- ☐ **Safe area corners** `sw-safe-area` · Position · missing  
  `GeometryProxy.safeAreaInsets`, `safeAreaInset` applied per list element, scroll indicators stopping at the inset; the keyboard region is a documented non-region in a browser. `ignoresSafeArea` on a view whose safe-area modifier hugs it on every edge extends on every edge by the geometric rule (PositionTests): a consequence, not a measurement. ([Position.md](Docs/elements/Position.md))
- ☐ **Timeline modes and pausing** `sw-timeline` · TimelineView · accepted  
  `lowFrequency` (accepted), pausing when the page is hidden, content reading the environment's calendar and time zone. ([TimelineView.md](Docs/elements/TimelineView.md))
- ☐ **Rendering previews** `sw-previews` · Preview · accepted  
  A macro that keeps the `#Preview` body so the gallery can show an app's previews, `PreviewModifier`, `previewLayout`, `previewDisplayName`; the traits are stubs today. ([Preview.md](Docs/elements/Preview.md))
- ☐ **Contrast and per-presentation schemes** `sw-dark` · Dark mode · missing  
  `colorSchemeContrast`, `preferredColorScheme` per presentation, gauge and date picker chrome verified in dark, the focus ring in dark. ([DarkMode.md](Docs/elements/DarkMode.md))
- ☐ **Hover effects on controls** `sw-hover-looks` · Hover · missing  
  `hoverEffect` and the hovered looks of macOS controls (none change today), the tooltip's measured look. ([Hover.md](Docs/elements/Hover.md))
- ☐ **Drags across the app boundary** `sw-dragdrop-os` · Drag and drop · missing  
  Drags to and from the browser page (`DataTransfer`) and other native apps (`NSDraggingSession`), `FileRepresentation`, `dropDestination` on `List` rows with insertion indices, `exportableToServices`, `importsItemProviders`. ([DragDrop.md](Docs/elements/DragDrop.md))
- ☐ **Table columns, styles and interaction** `sw-table` · Table · missing  
  `TableColumnForEach`, column groups, `TableRow` builders, `tableStyle`, `tableColumnHeaders`, `alternatingRowBackgrounds`, disclosure rows, column resizing by drag, row context menus, horizontal scrolling of overflowing columns, scrolling rows; the band look (approximate). ([Table.md](Docs/elements/Table.md))
- ☐ **Subviews-based ForEach and Group** `sw-subviews` · View composition · missing  
  `ForEach(subviews:)`, `ForEach(sections:)`, `Group(subviews:)`, `containerValues`; the iOS 18 container APIs. ([ForEach.md](Docs/elements/ForEach.md))
- ☐ **Charts, Map, VideoPlayer, WebView** `sw-frameworks` · Other frameworks · missing  
  Separate Apple frameworks. `Charts` is the one apps reach for most and could be a package of its own over the display list; `Map` would need a tile source; `VideoPlayer` and `WebView` need DOM elements under the canvas. Decision needed before any of them starts. ([support.json](Docs/support.json))

### UIKit

- ☐ **Tab bar badges and the More tab** `uk-tabbar` · Navigation · missing  
  `UITabBarItem.badgeValue`, the More tab past five items, `UITabBarAppearance` (accepted), tab bar customisation. ([Navigation.md](Docs/elements/UIKit/Navigation.md))
- ☐ **Share and document pickers** `uk-system-sheets` · Presentation · missing  
  `UIActivityViewController` over `navigator.share` and the native sharing picker; `UIDocumentPickerViewController` over the browser's file input and `NSOpenPanel`; `UIImagePickerController` likewise. What the host cannot offer is documented per host. ([Presentation.md](Docs/elements/UIKit/Presentation.md))
- ☐ **UITextInput for custom text views** `uk-text-input` · Text · missing  
  The `UITextInput` protocol and `UITextInteraction` so an app's own text view can take input through the host overlay; `UIKeyInput` for the simple form. ([TextView.md](Docs/elements/UIKit/TextView.md))
- ☐ **Slider images, segment images, stepper repeat** `uk-controls-rest` · Controls · missing  
  `UISlider` minimum and maximum images, `UISegmentedControl` images and per-segment widths, `UIStepper.autorepeat` (accepted), `UIPageControl` taps and continuous interaction. ([Controls.md](Docs/elements/UIKit/Controls.md))
- ☐ **UISplitViewController** `uk-splitviewcontroller` · Containers · missing  
  The column styles, display modes and the compact collapse; the iPad geometry from a simulator of that idiom. ([Containers](Packages/UIKitWeb/Sources/UIKitWebCore/Containers))
- ☐ **Table view corners** `uk-table-rest` · Table view · approximate  
  The grouped (non-inset) style's geometry, the `RowAnimation` kinds (every animation fades and slides today), swipe button widths and fonts, the lifted row's shadow, the tracking background while touched, `imageProperties`, catalog images in list content (the UIKit harness has no asset catalog), sidebar and `plainHeader` appearances, right-to-left. ([TableView.md](Docs/elements/UIKit/TableView.md))
- ☐ **Collection view corners** `uk-collection-rest` · Collection view · missing  
  Estimated dimensions in compositional layouts, item supplementary items, `groupPagingCentered`, `visibleItemsInvalidationHandler`, decorations in orthogonal sections, pinned footers, the scroll pocket blur, drag reordering, `UICollectionViewLayout` animation hooks, the diffable move detection when an item also changes section, outline disclosure options and reordering, the sidebar appearance. ([CollectionView.md](Docs/elements/UIKit/CollectionView.md))
- ☐ **UIAppearance proxies** `uk-appearance` · Views · missing  
  `appearance()` and `appearance(whenContainedInInstancesOf:)` applied when a view enters a window. ([Views](Packages/UIKitWeb/Sources/UIKitWebCore/Views))
- ☐ **Hardware keyboard and the focus system** `uk-keyboard` · Events · missing  
  `UIKeyCommand` on responders, `pressesBegan`/`pressesEnded`, `UIFocusSystem` with the focus ring for keyboard navigation across controls, table and collection cells. ([Events](Packages/UIKitWeb/Sources/UIKitWebCore/Events))
- ☐ **Drag and drop interactions** `uk-dragdrop` · Events · missing  
  `UIDragInteraction`/`UIDropInteraction`, the table and collection drag and drop delegates over the runtime's drag session (SwiftUI's `draggable` shares it). ([DragDrop.md](Docs/elements/DragDrop.md))
- ☐ **Scenes and app lifecycle** `uk-scenes` · App · missing  
  `UIWindowScene`, `UISceneDelegate` and `UIApplication` lifecycle notifications from page visibility and activation; several windows in the host; `UIFeedbackGenerator` as no-ops. ([App](Packages/UIKitWeb/Sources/UIKitWebCore/App))

### Platform

- ☐ **WebFoundation's gaps against Foundation** `pf-web-foundation-gaps` · wasm · missing  
  The wasm stand-ins (decision 0017) cover what the frameworks and ordinary apps call. Missing: `String.Encoding` and `String(data:encoding:)`, `URLComponents` and international host names, named time zones and daylight saving (`TimeZone.current` is the browser's fixed offset), calendars other than proleptic Gregorian, `DateFormatter` and `FormatStyle`, `wrappingComponents`, `Data` slices that keep their indices. Grow them as apps hit them; each FoundationEssentials type used instead costs the whole library. ([0017-web-foundation.md](Docs/decisions/0017-web-foundation.md))
- ☐ **Linux: build, CI, painter and host** `pf-linux` · Linux · infra  
  The native headless build and tests are supported on Linux with Swift 6.3.3, alongside wasm cross-compilation. Remaining: a Skia or Cairo painter, a GTK window and the WebKitGTK host. ([ROADMAP.md](Docs/ROADMAP.md))
- ☐ **Native text selection, IME and windows** `pf-native-text` · Native macOS · missing  
  A caret and selection painted inside the text (the browser's for now), IME marked text, several real windows, the menu bar and window commands, file dialogs, opening bundles by double click in Tools/Host. ([0012-native-painter.md](Docs/decisions/0012-native-painter.md))
- ☐ **First frame and large lists** `pf-perf` · Performance · infra  
  The gallery and progress bundles' first frame on a slow connection, laziness in lists and lazy stacks (sw-lazy, sw-list-looks), a frame budget probe in CI over Examples/Landing. ([landing-perf.mjs](Playwright/landing-perf.mjs))

## Landed

- ☑ 2026-10-09 **Search results, clear button and hiding on scroll** `uk-searchbar` · UIKit · Bars
- ☑ 2026-10-09 **UIImage data, tinting and animation** `uk-images` · UIKit · Images
- ☑ 2026-10-09 **UIRefreshControl** `uk-refresh` · UIKit · Scrolling
- ☑ 2026-10-09 **Zooming, inset adjustment and scroll-to-top** `uk-scroll-rest` · UIKit · Scrolling
- ☑ 2026-10-08 **Date picker popovers, calendars and wheels** `uk-datepicker` · UIKit · Controls
- ☑ 2026-10-04 **NavigationStack gaps** `sw-navigation` · SwiftUI · Navigation
- ☑ 2026-10-04 **Scroll content under the iOS 26 bar** `sw-ios-nav-scroll` · SwiftUI · Navigation
- ☑ 2026-10-04 **The Tab API, page style and badges** `sw-tabview` · SwiftUI · TabView
- ☑ 2026-10-04 **Menu rows, sections and navigation** `sw-menu` · SwiftUI · Menu
- ☑ 2026-10-04 **Picker options and looks** `sw-picker` · SwiftUI · Picker
- ☑ 2026-10-04 **Search suggestions, scopes and tokens** `sw-search` · SwiftUI · Toolbar
- ☑ 2026-10-04 **Button roles, sizes and states** `sw-button-looks` · SwiftUI · Button
- ☑ 2026-10-04 **Toggle sources, mixed state and looks** `sw-toggle` · SwiftUI · Toggle
- ☑ 2026-10-04 **Animated progress and gauges** `sw-progress` · SwiftUI · ProgressView
- ☑ 2026-10-04 **DatePicker editing and calendars** `sw-datepicker` · SwiftUI · DatePicker
- ☑ 2026-10-04 **Disclosure animation and outlines** `sw-disclosure` · SwiftUI · DisclosureGroup
- ☑ 2026-10-04 **Grouped form constants** `sw-form` · SwiftUI · Form
- ☑ 2026-10-04 **ViewThatFits** `sw-viewthatfits` · SwiftUI · Layout
- ☑ 2026-10-04 **Canvas images, symbols and filters** `sw-canvas` · SwiftUI · Canvas
- ☑ 2026-10-04 **3D and projection transforms** `sw-transform3d` · SwiftUI · Transform
- ☑ 2026-10-04 **Animation completion, blending and reduce motion** `sw-animation` · SwiftUI · Animation
- ☑ 2026-10-04 **onReceive, scene phase and URLs** `sw-lifecycle` · SwiftUI · Lifecycle
- ☑ 2026-10-04 **The @Entry macro** `sw-entry-macro` · SwiftUI · Environment
- ☑ 2026-10-04 **Simultaneous, pinch and rotate gestures** `sw-gestures` · SwiftUI · Gestures
- ☑ 2026-10-04 **Focused values, sections and commands** `sw-focus` · SwiftUI · Focus and keyboard
- ☑ 2026-10-04 **Custom actions, rotors and a VoiceOver session** `sw-accessibility` · SwiftUI · Accessibility
- ☑ 2026-10-04 **Pinch, rotation, swipe and edge pans** `uk-gestures` · UIKit · Events
- ☑ 2026-10-04 **Interactive pop, large-title collapse, custom transitions** `uk-nav-polish` · UIKit · Navigation
- ☑ 2026-10-04 **Sheet detents, popovers and custom presentations** `uk-sheets` · UIKit · Presentation
- ☑ 2026-10-04 **UIMenu presentation** `uk-menus` · UIKit · Menus
- ☑ 2026-10-04 **UIButton images, subtitles and states** `uk-button` · UIKit · Controls
- ☑ 2026-10-04 **UILabel attributed text and fitting** `uk-label` · UIKit · Text
- ☑ 2026-10-04 **Custom, italic and monospaced fonts; Dynamic Type** `uk-fonts` · UIKit · Text
- ☑ 2026-10-04 **UITextField borders, buttons and views** `uk-textfield` · UIKit · Text
- ☑ 2026-10-04 **UITextView attributed text, selection and links** `uk-textview` · UIKit · Text
- ☑ 2026-10-03 **TextField forms and the painted caret** `sw-textfield` · SwiftUI · TextField
- ☑ 2026-10-03 **allowsTightening and minimumScaleFactor** `sw-text-fit` · SwiftUI · Text
- ☑ 2026-10-03 **AttributedString, markdown, dates and images in Text** `sw-attributed-text` · SwiftUI · Text
- ☑ 2026-10-03 **Custom fonts** `sw-custom-fonts` · SwiftUI · Text
- ☑ 2026-09-19 **List styles, spacing and outline forms** `sw-list-looks` · SwiftUI · List
- ☑ 2026-09-19 **Scroll position, targets and geometry** `sw-scroll-apis` · SwiftUI · ScrollView
- ☑ 2026-09-19 **Real laziness and pinned headers** `sw-lazy` · SwiftUI · Lazy stacks and grids
- ☑ 2026-09-18 **One source of truth for what works and what is next** `st-tracking` · Site · Tracking
- ☑ 2026-09-18 **Support rows for every UIKit class** `st-uikit-rows` · Site · Tracking
- ☑ 2026-09-18 **Audit the stale rows and doc notes** `st-row-audit` · Site · Tracking
- ☑ 2026-09-18 **A live example for every support row** `st-fixture-links` · Site · Examples
- ☑ 2026-09-18 **Publish the gallery next to the landing page** `st-gallery-deploy` · Site · Examples
- ☑ 2026-09-18 **The progress page** `st-progress-page` · Site · Progress page
- ☑ 2026-09-18 **The landing page links to progress and examples** `st-landing-links` · Site · Landing page
- ☑ 2026-09-18 **The element workflow records progress** `st-workflow` · Site · Tracking
- ☑ 2026-09-18 **Hover inside a representable** `ix-hover` · Interop · Representables
- ☑ 2026-09-18 **Wheel scrolling of a hosted UIScrollView** `ix-wheel` · Interop · Representables
- ☑ 2026-09-18 **Animations across the seam** `ix-transaction` · Interop · Representables
- ☑ 2026-09-18 **Representables in lists, forms, scroll views and sheets** `ix-containers` · Interop · Representables
- ☑ 2026-09-18 **UIHostingConfiguration: margins, self-sizing, configuration state** `ix-hosting-config` · Interop · UIHostingConfiguration
- ☑ 2026-09-18 **UIHostingController in containers** `ix-hosting-controller` · Interop · UIHostingController
- ☑ 2026-09-18 **Image(uiImage:) for rendered images** `ix-rendered-images` · Interop · Bridging
- ☑ 2026-09-18 **The unmeasured sizing corners** `ix-measure-rest` · Interop · Representables
- ☑ 2026-09-18 **Decide whether SwiftUI keeps re-exporting UIKit unconditionally** `ix-size-gate` · Interop · Size
- ☑ 2026-09-18 **iOS sheets, tab bars and date pickers from the simulator** `sw-ios-sheets` · SwiftUI · iOS profile
- ☑ 2026-09-18 **Presentation looks and options** `sw-presentations` · SwiftUI · Presentation
- ☑ 2026-09-18 **List editing: onDelete, onMove, swipe actions, refreshable** `sw-list-editing` · SwiftUI · List
- ☑ 2026-09-18 **UIActivityIndicatorView spins** `uk-spinner` · UIKit · Controls
- ☑ 2026-09-18 **Hover and pointer interactions** `uk-hover` · UIKit · Events
- ☑ 2026-09-18 **Trim the wasm bundle: Foundation** `uk-size` · UIKit · Size
- ☑ 2026-09-12 **layoutOptions and safe areas through the seam** `ix-layout-options` · Interop · Representables
- ☑ 2026-09-12 **Environment to trait collection** `ix-traits` · Interop · Representables
- ☑ 2026-09-12 **Dismantle and coordinator lifecycle tests** `ix-lifecycle` · Interop · Representables

## Non-goals

- ✕ **Image(nsImage:) and Image(cgImage:)** `sw-nsimage` · SwiftUI: No CGImage or NSImage exists on wasm; `Image(cgImage:)` could work natively only. Non-goal for the browser; the native painter may add it with the AppKit decision (ix-appkit).
- ✕ **onDrag / onDrop with NSItemProvider** `sw-itemprovider` · SwiftUI: NSItemProvider and NSString do not exist on wasm; `draggable`/`dropDestination` are the portable forms. Non-goal.
- ✕ **Storyboards and nibs** `uk-storyboards` · UIKit: Interface Builder archives are undocumented binary formats; apps port their scenes to code. Non-goal.
