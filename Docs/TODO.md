# What is next

Generated from `Docs/todo.json` by `scripts/gen-progress.py`; edit the JSON, not this file. The same data is shown on the progress page. Priorities: **next** is Phase 8 of `Docs/ROADMAP.md` in order, **soon** the gap sweep after it (what ordinary apps hit), **later** what needs a decision, a subsystem or a platform that does not exist yet. Kinds: *missing* (no API), *accepted* (compiles, no behaviour), *approximate* (behaves, pixels or motion differ), *verify* (behaves, never measured against Apple), *infra* (tooling, docs, site). Marks: ☐ planned, ◐ in progress, ☑ done, ✕ a documented non-goal.

| Framework | Open items | next | soon | later |
|---|---|---|---|---|
| Site | 8 | 8 | 0 | 0 |
| Interop | 13 | 11 | 1 | 1 |
| SwiftUI | 58 | 1 | 29 | 28 |
| UIKit | 37 | 2 | 24 | 11 |
| Platform | 4 | 0 | 1 | 3 |
| **All** | **120** | 22 | 55 | 43 |

## Next (Phase 8, in order)

### Site

- ◐ **One source of truth for what works and what is next** `st-tracking` · Tracking · infra  
  Docs/support.json sections carry a `framework` (SwiftUI, UIKit, Interop); Docs/todo.json is this list; scripts/gen-progress.py renders Docs/support-matrix.md, Docs/TODO.md and the progress page's data; CI fails when the outputs are stale. ([0016-progress-page.md](Docs/decisions/0016-progress-page.md))
- ☐ **Support rows for every UIKit class** `st-uikit-rows` · Tracking · infra  
  UIKitWeb's classes have element docs but no support rows: add UIKit sections (views and layers, controls, text, containers, presentation, Auto Layout, drawing, animation, app and events) with a status, notes and the uikit/ fixtures for each, so the UIKit half of the matrix is as honest as the SwiftUI half. ([UIKit](Docs/elements/UIKit))
- ☐ **Audit the stale rows and doc notes** `st-row-audit` · Tracking · infra  
  Some rows and `Open:` lines predate the work that closed them (Transaction says it has no `animation` member; Text.md lists kerning and underline as missing; CollectionView.md and Presentation.md list done steps as open). Reconcile every row and `## Not yet covered` / `Open:` line with this list. ([support.json](Docs/support.json), [elements](Docs/elements))
- ☐ **A live example for every support row** `st-fixture-links` · Examples · infra  
  38 of 139 rows name no fixture. Link each to the fixtures that exercise it (state rows to button/ and foreach/, composition rows to layout/), and add golden-less `demo/` fixtures (like the browser-only `probe/` prefix) for behaviour no golden can capture: windows, pasteboard, previews. ([support.json](Docs/support.json), [Gallery](Examples/Gallery))
- ☐ **Publish the gallery next to the landing page** `st-gallery-deploy` · Examples · infra  
  A release build of Examples/Gallery at /gallery/ on Pages: every fixture with its source and its steps, SwiftUI and UIKit alike. Needs the landing page's loading screen, a `?filter=` parameter so a support row can link to a prefix, a link back to the site, and a size line in the deploy log. ([Gallery](Examples/Gallery), [build-landing.sh](scripts/build-landing.sh))
- ☐ **The progress page** `st-progress-page` · Progress page · infra  
  Examples/Progress, a SwiftUI app at /progress/: status counts per framework and section, the full matrix with filters and a search field, every row linking to its gallery examples and its element doc, and this list grouped by framework and priority with what landed recently. Generated data, the commit and the date on the page. ([0016-progress-page.md](Docs/decisions/0016-progress-page.md))
- ☐ **The landing page links to progress and examples** `st-landing-links` · Landing page · infra  
  Navigation links to /progress/ and /gallery/; the hero's stats come from the generated counts; the support matrix section becomes a summary card with the counts per framework and a link to the full page (a lighter landing bundle). README and the docs point at the same two pages. ([Landing](Examples/Landing))
- ☐ **The element workflow records progress** `st-workflow` · Tracking · infra  
  ELEMENT_WORKFLOW step 6 gains: mark the todo item done with the date, add the new gaps as items, run scripts/gen-progress.py, commit the outputs. Pages redeploys on every push to main that touches the data. ([ELEMENT_WORKFLOW.md](Docs/ELEMENT_WORKFLOW.md), [landing.yml](.github/workflows/landing.yml))

### Interop

- ☐ **layoutOptions and safe areas through the seam** `ix-layout-options` · Representables · accepted  
  `_PlatformViewRepresentableLayoutOptions` (`propagatesSafeArea`): a representable's UIKit tree gets the SwiftUI safe area as its window's insets, and `UIHostingController.safeAreaRegions` (accepted today) hands the controller's safe area to the hosted runtime. Fixtures on the simulator under a navigation bar. ([Representable.md](Docs/elements/Representable.md))
- ☐ **Environment to trait collection** `ix-traits` · Representables · missing  
  colorScheme becomes userInterfaceStyle, dynamicTypeSize the content size category, layoutDirection and the size classes follow; `updateUIView` runs when they change. A dark twin of ios/representable/controls. ([Representable.md](Docs/elements/Representable.md))
- ☐ **Hover inside a representable** `ix-hover` · Representables · missing  
  SwiftUI's pointer moves reach the hosted tree as `UIHoverGestureRecognizer` events and `UIPointerInteraction` styles; the host cursor follows. Depends on uk-hover. ([Representable.md](Docs/elements/Representable.md), [Hover.md](Docs/elements/Hover.md))
- ☐ **Wheel scrolling of a hosted UIScrollView** `ix-wheel` · Representables · verify  
  Routed but never measured: a fixture with a scroll view in a representable, a Playwright probe that wheels over it, and the frames compared after the scroll. ([Representable.md](Docs/elements/Representable.md))
- ☐ **Animations across the seam** `ix-transaction` · Representables · verify  
  `context.transaction` carries the SwiftUI animation into `updateUIView`; a `withAnimation` that resizes a representable tweens the UIKit frame; `UIView.animate` inside `updateUIView` runs on the outer clock. Tests on the headless clock. ([Representable.md](Docs/elements/Representable.md))
- ☐ **Representables in lists, forms, scroll views and sheets** `ix-containers` · Representables · verify  
  Fixtures on the simulator for a representable as a List row, in a grouped Form, inside a ScrollView (both scrolling) and in a sheet; the row heights and the hosted view's frame compared exactly. ([Representable.md](Docs/elements/Representable.md))
- ☐ **Dismantle and coordinator lifecycle tests** `ix-lifecycle` · Representables · verify  
  `RepresentableTests`: make, update, dismantle order on removal and identity change; the coordinator outlives updates and dies with the node; `makeCoordinator` once per node. ([SwiftUIWebUIKit](Sources/SwiftUIWebUIKit))
- ☐ **UIHostingConfiguration: margins, self-sizing, configuration state** `ix-hosting-config` · UIHostingConfiguration · approximate  
  The vertical margins above one-line content (hidden by the 56 pt floor today), hosted content in self-sizing collection cells, and `updated(for:)` with the cell's configuration state (selected, highlighted). ([Representable.md](Docs/elements/Representable.md))
- ☐ **UIHostingController in containers** `ix-hosting-controller` · UIHostingController · missing  
  A hosting controller pushed on a navigation controller or in a tab sees the bars' safe area; `sizingOptions.intrinsicContentSize`; `rootView` changes animate under a transaction; `navigationItem` driven by the SwiftUI `navigationTitle` and `toolbar` (as Apple bridges them). ([Representable.md](Docs/elements/Representable.md))
- ☐ **Image(uiImage:) for rendered images** `ix-rendered-images` · Bridging · missing  
  A `UIImage` from `UIGraphicsImageRenderer` (a recording) drawn by SwiftUI's `Image`, with `withTintColor` and `pngData()` (the recording rasterised by the host). ([Drawing.md](Docs/elements/UIKit/Drawing.md))
- ☐ **Decide whether SwiftUI keeps re-exporting UIKit unconditionally** `ix-size-gate` · Size · infra  
  Decision 0014 left this to the size gate: Counter is 2.84 MB brotli with UIKitWeb linked (budget 3 MB). Either trim the substrate tables (uk-size) or make the re-export a product option; record the outcome in the decision. ([0014-uikitweb.md](Docs/decisions/0014-uikitweb.md), [0006-binary-size.md](Docs/decisions/0006-binary-size.md))

### SwiftUI

- ☐ **iOS sheets, tab bars and date pickers from the simulator** `sw-ios-sheets` · iOS profile · verify  
  Open since the simulator arrived: capture the window (as the UIKit generator does) for `sheet`, `alert`, `confirmationDialog`, `TabView`'s bar and `DatePicker` in the iOS profile, and pin their geometry and looks; list selection looks too. ([iOS.md](Docs/elements/iOS.md), [Presentation.md](Docs/elements/Presentation.md))

### UIKit

- ☐ **UIActivityIndicatorView spins** `uk-spinner` · Controls · approximate  
  A still of eight spokes today: rotate the spokes on the scene's clock at UIKit's rate, `startAnimating`/`stopAnimating`, `hidesWhenStopped`. ([Controls.md](Docs/elements/UIKit/Controls.md))
- ☐ **Hover and pointer interactions** `uk-hover` · Events · missing  
  `UIHoverGestureRecognizer`, `UIPointerInteraction` with the pointer styles the host cursor can show, `UIButton`'s pointer effect. Feeds ix-hover. ([UIButton.md](Docs/elements/UIKit/UIButton.md))

## Soon (the gap sweep)

### Interop

- ☐ **The unmeasured sizing corners** `ix-measure-rest` · Representables · verify  
  `alignmentRectInsets` on controls other than the switch, a label's baseline at sizes other than 17 pt, a `sizeThatFits` that returns a size on one axis and the intrinsic on the other; one grid fixture on the simulator. ([Representable.md](Docs/elements/Representable.md))

### SwiftUI

- ☐ **Presentation looks and options** `sw-presentations` · Presentation · approximate  
  macOS sheets, popovers and alerts are separate windows the harness cannot capture, so the looks are by eye: measure them through a window-list capture spike or accept them as approximate in the row. `presentationDetents`, `interactiveDismissDisabled`, `attachmentAnchor` beyond the bounds, scrolling inside sheets, several presentations from one view. ([Presentation.md](Docs/elements/Presentation.md))
- ☐ **List editing: onDelete, onMove, swipe actions, refreshable** `sw-list-editing` · List · missing  
  `ForEach.onDelete`/`onMove`, `editActions:` bindings, `deleteDisabled`/`moveDisabled`, `editMode`, `swipeActions`, `refreshable`; the iOS looks from the simulator, macOS's from goldens where the harness can capture them. ([List.md](Docs/elements/List.md), [ForEach.md](Docs/elements/ForEach.md))
- ☐ **List styles, spacing and outline forms** `sw-list-looks` · List · missing  
  `List(data, children:)` and `OutlineGroup`, `.inset(alternatesRowBackgrounds:)` / `.bordered`, `listRowSpacing`, `listSectionSpacing`, `alternatingRowBackgrounds`, `scrollContentBackground`, `headerProminence`, `listItemTint` and the section separator modifiers (stored today), the accent focused look, headers pinning as the content scrolls, lazy rows. ([List.md](Docs/elements/List.md))
- ☐ **Scroll position, targets and geometry** `sw-scroll-apis` · ScrollView · missing  
  `scrollPosition`, `scrollTargetLayout`, `scrollTargetBehavior` (paging, view aligned), `contentMargins`, `onScrollGeometryChange`, `onScrollPhaseChange`, `defaultScrollAnchor(for:)`, `scrollIndicatorsFlash`, `scrollDismissesKeyboard`, `ScrollViewReader` inside `List`; the indicator geometry measured (marked unverified). ([ScrollView.md](Docs/elements/ScrollView.md))
- ☐ **Real laziness and pinned headers** `sw-lazy` · Lazy stacks and grids · accepted  
  Cells created on demand as they scroll into view (every cell is laid out today), `Section` headers and footers in lazy grids, `pinnedViews` (accepted) pinning while scrolling, `GridItem` alignment against the grid's. ([Lazy.md](Docs/elements/Lazy.md))
- ☐ **TextField forms and the painted caret** `sw-textfield` · TextField · missing  
  `TextField(_:value:format:)` and `formatter:`, `onEditingChanged`/`onCommit`, `axis: .vertical` (a stub today), `submitLabel`, `textContentType`, `keyboardType`, `textInputAutocapitalization`, `autocorrectionDisabled` (stored) reaching the overlay input, `lineLimit` on fields; the caret and selection painted into the display list so native and browser match. ([TextField.md](Docs/elements/TextField.md))
- ☐ **allowsTightening and minimumScaleFactor** `sw-text-fit` · Text · accepted  
  Stored environment values that never reach layout: shrink to fit measured on a grid of widths and factors. ([Text.md](Docs/elements/Text.md))
- ☐ **AttributedString, markdown, dates and images in Text** `sw-attributed-text` · Text · missing  
  `Text(AttributedString)` with per-run fonts, colours and links, markdown in string literals, `Text(date, style:)` and `Text(_:format:)`, `Text(Image)` inline, `Link` inside text. ([Text.md](Docs/elements/Text.md), [Link.md](Docs/elements/Link.md))
- ☐ **Custom fonts** `sw-custom-fonts` · Text · missing  
  `Font.custom` with a font file in the app bundle: metrics read from the file for layout, the face loaded by the browser and by CoreText; the recorded engine keyed by family. ([Text.md](Docs/elements/Text.md), [0005-text-metrics.md](Docs/decisions/0005-text-metrics.md))
- ☐ **NavigationStack gaps** `sw-navigation` · Navigation · missing  
  `navigationDestination(item:destination:)`, the codable `NavigationPath` representation, ⌘[ and Escape, macOS's back button and push animation parity, a destination-link entry left on top after a path change removes its view. ([Navigation.md](Docs/elements/Navigation.md))
- ☐ **The Tab API, page style and badges** `sw-tabview` · TabView · missing  
  `Tab(...)` (iOS 18), `tabViewStyle(.page)` and `.sidebarAdaptable`, badges, images in the macOS bar, disabled tabs, the bar's focus ring, the iOS bar from the simulator (sw-ios-sheets). ([TabView.md](Docs/elements/TabView.md))
- ☐ **Menu rows, sections and navigation** `sw-menu` · Menu · missing  
  `Toggle` and `Picker` rows with check marks, `Section` headers, `Label` icons in rows, keyboard navigation, hover highlight, `menuOrder` (accepted), `menuActionDismissBehavior`, `contextMenu(forSelectionType:)`; the split button's active look. ([Menu.md](Docs/elements/Menu.md))
- ☐ **Picker options and looks** `sw-picker` · Picker · missing  
  `Picker(sources:selection:)`, `tag(_:includeOptional:)`, option images, labels, dividers and sections in menus, keyboard navigation, the focused accent look of segmented and radio controls, the `palette` style, the pop-up's measured look. ([Picker.md](Docs/elements/Picker.md))
- ☐ **Search suggestions, scopes and tokens** `sw-search` · Toolbar · accepted  
  `searchSuggestions` (accepted), `searchScopes`, `searchable(text:tokens:)`, `searchCompletion`, `searchPresentationToolbarBehavior`, `isSearching` following focus. ([Toolbar.md](Docs/elements/Toolbar.md))
- ☐ **Button roles, sizes and states** `sw-button-looks` · Button · missing  
  `PrimitiveButtonStyle`, the destructive role look, the disabled look, `controlSize`, the pressed, hovered and focused looks (goldens come from an inactive window), the borderless look (approximate). ([Button.md](Docs/elements/Button.md))
- ☐ **Toggle sources, mixed state and looks** `sw-toggle` · Toggle · missing  
  `Toggle(sources:isOn:)`, `isMixed`, Space activation, the focus ring, hover, `controlSize`, `tint`, the switch knob's shadow, the active-window accent checkbox. ([Toggle.md](Docs/elements/Toggle.md))
- ☐ **Animated progress and gauges** `sw-progress` · ProgressView · approximate  
  The spinner's rotation and the indeterminate bar's motion (a fixed phase today), `ProgressView(timerInterval:)`, `ProgressView(_ progress:)`, `tint` (accepted), animated `Gauge` values, its marked value labels (accepted). ([ProgressView.md](Docs/elements/ProgressView.md), [Gauge.md](Docs/elements/Gauge.md))
- ☐ **DatePicker editing and calendars** `sw-datepicker` · DatePicker · missing  
  Typing into the fields, the compact popover calendar, greying days outside the range, dragging the clock's hands, the wheel style (iOS, from the simulator), locales and other calendars, both components on one graphical row. ([DatePicker.md](Docs/elements/DatePicker.md))
- ☐ **Disclosure animation and outlines** `sw-disclosure` · DisclosureGroup · missing  
  The expand and collapse animation, `DisclosureGroup` inside `List` as outline rows, the exact chevron glyph. ([DisclosureGroup.md](Docs/elements/DisclosureGroup.md))
- ☐ **Grouped form constants** `sw-form` · Form · verify  
  Section header, footer and spacing constants (unverified), the grouped picker, slider, stepper and button rows (laid out by rule, no golden), the card's fill and corners (approximate), the small switch, nested `formStyle`, `scrollContentBackground`, `GroupBox` insets inside a form. ([Form.md](Docs/elements/Form.md), [GroupBox.md](Docs/elements/GroupBox.md))
- ☐ **ViewThatFits** `sw-viewthatfits` · Layout · missing  
  Not implemented: the first child that fits the proposal on the chosen axes, measured against goldens over a grid of widths. ([Layout.md](Docs/elements/Layout.md))
- ☐ **Canvas images, symbols and filters** `sw-canvas` · Canvas · missing  
  `draw(Image)`, `resolveSymbol`, `addFilter`, `withCGContext`, `tiledImage`, the context's `blendMode`, `rendersAsynchronously`, invalidation on state read inside the renderer. ([Canvas.md](Docs/elements/Canvas.md))
- ☐ **3D and projection transforms** `sw-transform3d` · Transform · missing  
  `rotation3DEffect`, `projectionEffect`, `GeometryEffect` conformances, hit testing through rotations and scales, anchors for scale transitions. ([Transform.md](Docs/elements/Transform.md))
- ☐ **Animation completion, blending and reduce motion** `sw-animation` · Animation · missing  
  `withAnimation(_:completionCriteria:_:completion:)`, `blendDuration` and initial velocity, `accessibilityReduceMotion`, ghosts inside containers that paint their own children (List, Picker, grouped Form), `contentTransition` beyond text (`interpolate`, `symbolEffect`). ([Animation.md](Docs/elements/Animation.md), [Animator.md](Docs/elements/Animator.md))
- ☐ **onReceive, scene phase and URLs** `sw-lifecycle` · Lifecycle · missing  
  `onReceive` with Combine-free `Timer.publish` and `NotificationCenter.publisher`, `scenePhase` from page visibility and the app's activation, `onOpenURL`, `onContinueUserActivity`, appear ordering between siblings and parents. ([Lifecycle.md](Docs/elements/Lifecycle.md), [ObservableObject.md](Docs/elements/ObservableObject.md))
- ☐ **The @Entry macro** `sw-entry-macro` · Environment · missing  
  `@Entry` on `EnvironmentValues`, `FocusedValues` and `Transaction` extensions, in the existing macro target. ([SwiftUIWebMacros](Sources/SwiftUIWebMacros))
- ☐ **Simultaneous, pinch and rotate gestures** `sw-gestures` · Gestures · accepted  
  `simultaneousGesture` as true simultaneity (one node takes a press today), `GestureMask`, the `reset` closures and gesture transactions (accepted), `MagnifyGesture`/`RotateGesture` from trackpads and touches, tap counts through `onTapGesture`. ([Gestures.md](Docs/elements/Gestures.md))
- ☐ **Focused values, sections and commands** `sw-focus` · Focus and keyboard · missing  
  `FocusedValue`, `@FocusedBinding`, `focusSection`, `defaultFocus`, `prefersDefaultFocus`, focus restored after a sheet closes, `onCommand`, `onCopyCommand`/`onPasteCommand`, `onKeyPress(characters:)`, key-up phases, type-to-select and Cmd ranges in lists, the real focus ring look. ([Focus.md](Docs/elements/Focus.md), [Keyboard.md](Docs/elements/Keyboard.md))
- ☐ **Custom actions, rotors and a VoiceOver session** `sw-accessibility` · Accessibility · missing  
  `accessibilityAction`, `accessibilityAdjustableAction`, `accessibilitySortPriority`, `accessibilityRepresentation`, `accessibilityChildren`, `accessibilityFocused`, rotors, live regions, heading levels, `help` exposed to assistive technology; a VoiceOver session by hand in Safari and an IME session (spike 0.12). ([Accessibility.md](Docs/elements/Accessibility.md), [Hover.md](Docs/elements/Hover.md))

### UIKit

- ☐ **Pinch, rotation, swipe and edge pans** `uk-gestures` · Events · missing  
  `UIPinchGestureRecognizer`, `UIRotationGestureRecognizer`, `UISwipeGestureRecognizer`, `UIScreenEdgePanGestureRecognizer`; the delegate's simultaneous-recognition and failure-requirement methods honoured across all recognizers. ([Events](Packages/UIKitWeb/Sources/UIKitWebCore/Events))
- ☐ **Interactive pop, large-title collapse, custom transitions** `uk-nav-polish` · Navigation · missing  
  The edge-pan interactive pop, the large title collapsing as the content scrolls (SwiftUI's iOS profile has it), `titleView` sizing, `hidesBottomBarWhenPushed`, `UIViewControllerTransitioningDelegate` and animated transitioning, the appearance objects (accepted). ([Navigation.md](Docs/elements/UIKit/Navigation.md))
- ☐ **Sheet detents, popovers and custom presentations** `uk-sheets` · Presentation · missing  
  `UISheetPresentationController` with detents and the grabber, `popover` (a sheet on iPhone, an arrowed popover on iPad and Mac), the alert `severity` badge, action sheets anchored to bar items, `UIPresentationController` subclasses. ([Presentation.md](Docs/elements/UIKit/Presentation.md))
- ☐ **UIMenu presentation** `uk-menus` · Menus · accepted  
  `UIMenu` is a data holder today: `UIButton.menu` with `showsMenuAsPrimaryAction`, `UIBarButtonItem(menu:)`, `UIContextMenuInteraction` with previews, `UIEditMenuInteraction`; the iOS 26 menu card from the simulator. ([UIButton.md](Docs/elements/UIKit/UIButton.md), [Bars.md](Docs/elements/UIKit/Bars.md))
- ☐ **UIButton images, subtitles and states** `uk-button` · Controls · missing  
  Custom-type buttons' title font (17 pt assumed), `image` and `imagePlacement`, subtitles, `buttonSize`, the pressed and disabled looks, `UIButton.Configuration` update handlers. ([UIButton.md](Docs/elements/UIKit/UIButton.md))
- ☐ **UILabel attributed text and fitting** `uk-label` · Text · missing  
  `attributedText` with per-range attributes, `adjustsFontSizeToFitWidth` and `minimumScaleFactor`, `allowsDefaultTighteningForTruncation`, the ink position of a text-style line verified against the simulator's pixels. ([UILabel.md](Docs/elements/UIKit/UILabel.md))
- ☐ **Custom, italic and monospaced fonts; Dynamic Type** `uk-fonts` · Text · missing  
  `UIFont(name:size:)` from bundled files, `italicSystemFont`, `monospacedSystemFont`, `UIFontMetrics` scaling with the content size categories, `preferredContentSizeCategory` in the trait collection. ([UIFont.md](Docs/elements/UIKit/UIFont.md))
- ☐ **UITextField borders, buttons and views** `uk-textfield` · Text · missing  
  The `line` and `bezel` borders, the clear button, `leftView`/`rightView`, attributed placeholders, the text's vertical position verified against the simulator's pixels, the keyboard types reaching the overlay input. ([UITextField.md](Docs/elements/UIKit/UITextField.md))
- ☐ **UITextView attributed text, selection and links** `uk-textview` · Text · missing  
  `attributedText`, `selectedRange` and a painted selection, data detectors and links, `textContainer` exclusion paths, the Helvetica 12 default font, indicators after a scroll. ([TextView.md](Docs/elements/UIKit/TextView.md))
- ☐ **Date picker popovers, calendars and wheels** `uk-datepicker` · Controls · missing  
  The calendar and time popovers a compact picker presents, `UICalendarView` and the inline style, the count-down timer, `minimumDate`/`maximumDate`, locales and calendars, `valueChanged` from the wheels; `UIPickerView` spinning by touch, custom row views, the drum's perspective (approximate, frames-only today). ([DatePicker.md](Docs/elements/UIKit/DatePicker.md))
- ☐ **Search results, clear button and hiding on scroll** `uk-searchbar` · Bars · accepted  
  `searchResultsController` presented (stored today), the clear and bookmark buttons, `hidesSearchBarWhenScrolling`, `prompt` (stored), toolbar items beside a floating search field. ([Bars.md](Docs/elements/UIKit/Bars.md))
- ☐ **UIImage data, tinting and animation** `uk-images` · Images · missing  
  `UIImage(data:)` and `pngData()`/`jpegData()` through the host, `withTintColor`, `withRenderingMode` verified on image views, `UIImage.animatedImage` and `UIImageView.animationImages`, `UIImageView` content modes verified against the simulator. ([Drawing.md](Docs/elements/UIKit/Drawing.md))
- ☐ **UIRefreshControl** `uk-refresh` · Scrolling · missing  
  The pull-to-refresh control on scroll views and tables, its spinner (uk-spinner) and the iOS 26 geometry from the simulator. ([UIScrollView.md](Docs/elements/UIKit/UIScrollView.md))
- ☐ **Zooming, inset adjustment and scroll-to-top** `uk-scroll-rest` · Scrolling · missing  
  `viewForZooming` with pinch and `zoomScale`, `contentInsetAdjustmentBehavior`, `keyboardDismissMode`, scroll-to-top on a status bar tap, `scrollIndicatorInsets`. ([UIScrollView.md](Docs/elements/UIKit/UIScrollView.md))
- ☐ **UIPageViewController** `uk-pageviewcontroller` · Containers · missing  
  Scroll and page-curl-as-scroll transition styles, the data source and delegate, the page indicator. ([Containers](Packages/UIKitWeb/Sources/UIKitWebCore/Containers))
- ☐ **UIVisualEffectView and the glass** `uk-materials` · Views · approximate  
  Blur and vibrancy effects as a display-list filter group over what lies beneath (the painters have blur); the iOS 26 glass in bars and the scroll pocket is a tint today. ([Bars.md](Docs/elements/UIKit/Bars.md), [iOS.md](Docs/elements/iOS.md))
- ☐ **Layer corners, borders and shadows against pixels** `uk-view-pixels` · Views · verify  
  The painted corners (continuous too), borders and shadows of `uikit/view/*` compared with the simulator's pixels; the fixtures are frames-only where the look is unverified. ([UIView.md](Docs/elements/UIKit/UIView.md))
- ☐ **Trait overrides and observation** `uk-traits` · Views · missing  
  `overrideUserInterfaceStyle` on a view (the window's works), `registerForTraitChanges` and `traitCollectionDidChange` on every change, size classes from the host size, dark samples of the wheels and of presentations other than the alert. ([Dark.md](Docs/elements/UIKit/Dark.md))
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
- ☐ **Trim the substrate tables** `uk-size` · Size · infra  
  UIKitCounter is 2.24 MB brotli because the symbol and font tables come along whole; load the symbol glyphs the app names, split the metrics tables per platform profile. ([0014-uikitweb.md](Docs/decisions/0014-uikitweb.md), [0006-binary-size.md](Docs/decisions/0006-binary-size.md))

### Platform

- ☐ **IME, autofill and VoiceOver by hand** `pf-browser-sessions` · Browser · verify  
  Japanese and Chinese IMEs and Safari autofill through the overlay input (spike 0.12's risk), a VoiceOver session in Safari; the findings recorded per browser in the matrix. ([ROADMAP.md](Docs/ROADMAP.md))

## Later (needs a decision, a subsystem or a platform)

### Interop

- ☐ **NSViewRepresentable and NSViewControllerRepresentable** `ix-appkit` · AppKit · missing  
  Apps written for the macOS profile reach for AppKit representables; there is no AppKitWeb to host them. Out of scope until a decision says whether an AppKitWeb is worth building or the API should compile as an empty view; recorded here so the choice is visible. ([0014-uikitweb.md](Docs/decisions/0014-uikitweb.md))

### SwiftUI

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
  `GeometryProxy.safeAreaInsets`, `safeAreaInset` applied per list element, scroll indicators stopping at the inset; the keyboard region is a documented non-region in a browser. ([Position.md](Docs/elements/Position.md))
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

- ☐ **Linux: build, CI, painter and host** `pf-linux` · Linux · infra  
  WebGraphics does not build on Linux (the CoreGraphics shim is `#if os(WASI)` only), so the CI job is parked; then a Skia or Cairo painter, a GTK window and the WebKitGTK host. ([ROADMAP.md](Docs/ROADMAP.md))
- ☐ **Native text selection, IME and windows** `pf-native-text` · Native macOS · missing  
  A caret and selection painted inside the text (the browser's for now), IME marked text, several real windows, the menu bar and window commands, file dialogs, opening bundles by double click in Tools/Host. ([0012-native-painter.md](Docs/decisions/0012-native-painter.md))
- ☐ **First frame and large lists** `pf-perf` · Performance · infra  
  The gallery and progress bundles' first frame on a slow connection, laziness in lists and lazy stacks (sw-lazy, sw-list-looks), a frame budget probe in CI over Examples/Landing. ([landing-perf.mjs](Playwright/landing-perf.mjs))

## Non-goals

- ✕ **Image(nsImage:) and Image(cgImage:)** `sw-nsimage` · SwiftUI: No CGImage or NSImage exists on wasm; `Image(cgImage:)` could work natively only. Non-goal for the browser; the native painter may add it with the AppKit decision (ix-appkit).
- ✕ **onDrag / onDrop with NSItemProvider** `sw-itemprovider` · SwiftUI: NSItemProvider and NSString do not exist on wasm; `draggable`/`dropDestination` are the portable forms. Non-goal.
- ✕ **Storyboards and nibs** `uk-storyboards` · UIKit: Interface Builder archives are undocumented binary formats; apps port their scenes to code. Non-goal.
