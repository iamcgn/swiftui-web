# What is next

Generated from `Docs/todo.json` by `scripts/gen-progress.py`; edit the JSON, not this file. The same data is shown on the progress page. Priorities: **next** is Phase 8 of `Docs/ROADMAP.md` in order, **soon** the gap sweep after it (what ordinary apps hit), **later** what needs a decision, a subsystem or a platform that does not exist yet. Kinds: *missing* (no API), *accepted* (compiles, no behaviour), *approximate* (behaves, pixels or motion differ), *verify* (behaves, never measured against Apple), *infra* (tooling, docs, site). Marks: ☐ planned, ◐ in progress, ☑ done, ✕ a documented non-goal.

| Framework | Open items | next | soon | later |
|---|---|---|---|---|
| SwiftUI | 2 | 2 | 0 | 0 |
| UIKit | 1 | 1 | 0 | 0 |
| Platform | 10 | 5 | 1 | 4 |
| **All** | **13** | 8 | 1 | 4 |

## Next (Phase 8, in order)

### SwiftUI

- ☐ **NavigationStack inside a sheet** `sw-ios-sheet-nav` · iOS profile · approximate  
  On the iOS profile a sheet whose content is a NavigationStack: its navigationTitle replaces the presenting stack's bar title (`Runtime.navigationTitle` is one value for the window), no bar is drawn when the title is empty even with toolbar items (NavigationNodes.swift `bar(over:)` wants a title or a back button), and the stack's toolbar items are never painted (PresentationNodes drops the sheet toolbar when sheets fill the window). Scrumdinger's add/edit sheets lose their Dismiss and Add buttons. Also an image-only toolbar Button gets an empty accessibility label (SwiftUI derives it from the symbol name). Goldens: a sheet with an inline untitled bar and items, from the simulator. ([0021-real-apps.md](Docs/decisions/0021-real-apps.md))
- ◐ **Isolation annotations as Apple declares them** `sw-isolation-fidelity` · SwiftUI · approximate  
  A Swift 6 app compiles against this package as against Apple's only if every protocol, initializer and modifier carries the same isolation: the protocols Apple marks `@MainActor @preconcurrency` (ToolbarContent, the style protocols, Commands, Gesture, TabContent, the representables, AccessibilityRotorContent, DropDelegate) and not the ones it leaves nonisolated (ListStyle, PickerStyle, TextFieldStyle, DynamicViewContent, ScrollTargetBehavior); view initializers `nonisolated` (1 595 of Apple's are; 627 of ours were isolated), action parameters `@preconcurrency @MainActor` where Apple's are. Done 2026-10-12 for the protocols and for Button and Label (Scrumdinger's `ToolbarButton` and its `Button(_:symbol:)` wrappers would not compile); the sweep over the remaining initializers and modifiers against the SDK's swiftinterface is open. ([0021-real-apps.md](Docs/decisions/0021-real-apps.md))

### UIKit

- ☐ **UIApplicationDelegateAdaptor and app-level UIKit** `uk-app-delegate-adaptor` · App · missing  
  `@UIApplicationDelegateAdaptor` (and the `UISceneConfiguration.delegateClass` / `UIWindowSceneDelegate` route to a scene delegate), `UIApplication.keyboardWillShowNotification` / `keyboardWillHideNotification` with `UIResponder.keyboardFrameEndUserInfoKey` (the host's text input focus), `UIApplication.openSettingsURLString`, `UIBackgroundFetchResult`, `UIMenuBuilder` and `UIMenu.Identifier` as accepted. A non-final `UIApplicationDelegate` still needs `required init()` and `#selector` has no equivalent (documented). ([0021-real-apps.md](Docs/decisions/0021-real-apps.md))

### Platform

- ☐ **Speech, audio and notifications for the web** `pf-non-web-frameworks` · wasm · missing  
  Superseded 2026-10-12 (the apps run unmodified or not at all; nothing on the app's side is swapped): the frameworks Scrumdinger and the Countries app reach for get real web behaviour in modules of the same name — `pf-avfoundation-audio`, `pf-speech`, `pf-usernotifications`. What stays out of reach is the compiler, not the web: `@objc` and `#selector` are rejected for wasm ("Objective-C interoperability is disabled"; forcing `-enable-objc-interop` crashes the frontend), see `ap-app-ports`. ([0021-real-apps.md](Docs/decisions/0021-real-apps.md))
- ◐ **Open-source apps as a check** `ap-app-ports` · Examples · infra  
  The four upstream trees (the three apps and the Countries app's EnvironmentOverrides dependency) are git submodules at pinned commits under `Apps/upstream/`, with a SHA-256 manifest per tree; `Apps/Package.swift` mirrors each upstream target (sources, language mode, excludes and resources) and links this package's products, nothing else (`Apps/README.md`). `scripts/check-apps.sh` verifies the pins and that no upstream file differs, then builds each app for wasm; CI runs it. Done: the baseline and the script. Open: the apps build and run (the rows below), a Playwright flow per app, and SwiftUI-2048's `AppDelegate.swift`, which the wasm compiler refuses (`@objc`, `#selector`) — a platform blocker to decide on, not a patch. ([0021-real-apps.md](Docs/decisions/0021-real-apps.md))
- ☐ **AVAudioPlayer, AVAudioSession, AVAudioEngine** `pf-avfoundation-audio` · Platform · missing  
  Scrumdinger's AudioService and SpeechService as written: `AVAudioPlayer(contentsOf:)`, `prepareToPlay`, `play`, `currentTime` over an HTMLAudioElement on the bundle's `ding.wav`; `AVAudioSession.sharedInstance()` with `setCategory(_:mode:options:)` and `setActive(_:options:)` accepted, `AVAudioApplication.requestRecordPermission` over `getUserMedia`; `AVAudioEngine` whose `inputNode` is the microphone (`outputFormat(forBus:)`, `installTap(onBus:bufferSize:format:)` delivering `AVAudioPCMBuffer`s from an AudioWorklet, `removeTap`, `prepare`, `start`, `stop`). The module exists (`AVPlayer` for AVKit); the native host plays through AVFoundation itself. ([0021-real-apps.md](Docs/decisions/0021-real-apps.md))
- ☐ **Speech over the Web Speech API** `pf-speech` · Platform · missing  
  A `Speech` module: `SFSpeechRecognizer(locale:)`, `requestAuthorization`, `isAvailable`, `recognitionTask(with:resultHandler:)`, `SFSpeechAudioBufferRecognitionRequest` (`shouldReportPartialResults`, `taskHint`, `addsPunctuation`, `append(_:)`), `SFSpeechRecognitionTask.cancel()`, `SFSpeechRecognitionResult.bestTranscription.formattedString` and `isFinal`, over the browser's `SpeechRecognition` with interim results. The browser recognises from the microphone directly: buffers the app appends from its audio tap are accepted and not what is transcribed (a stated deviation; in Chrome the audio goes to Google's service, Safari's is on-device). Availability follows the browser (`isAvailable` false where there is no `SpeechRecognition`). ([0021-real-apps.md](Docs/decisions/0021-real-apps.md))
- ☐ **Asset catalogs in the bundle** `pf-xcassets` · Platform · infra  
  `.process("Media.xcassets")`: the colorsets (light and dark, display-P3 or sRGB components) and imagesets (scale and appearance variants) of an app target's asset catalog compiled into the bundle so `Color(_:bundle:)` and `Image(_:bundle:)` resolve them as on iOS (Scrumdinger's sixteen theme colours, the Countries app's accent). `scripts/build-wasm.sh` copies processed resources and skips xcassets today. ([0021-real-apps.md](Docs/decisions/0021-real-apps.md))

## Soon (the gap sweep)

### Platform

- ☐ **IME, autofill and VoiceOver by hand** `pf-browser-sessions` · Browser · verify  
  Japanese and Chinese IMEs and Safari autofill through the overlay input (spike 0.12's risk), a VoiceOver session in Safari; the findings recorded per browser in the matrix. ([ROADMAP.md](Docs/ROADMAP.md))

## Later (needs a decision, a subsystem or a platform)

### Platform

- ☐ **URLSession over fetch** `pf-urlsession` · wasm · missing  
  No `URLSession` anywhere: `URLSession.shared` and `URLSession(configuration:)` with `data(for:)`, `data(from:)`, the completion-handler forms and `dataTaskPublisher`, `URLRequest` (method, headers, body), `HTTPURLResponse` (statusCode, headers), `URLError` and `URLSessionConfiguration`, over the browser's fetch (CORS applies) on wasm and Foundation's own elsewhere. The Countries app's web repositories are unreachable without it; most apps load something. ([0021-real-apps.md](Docs/decisions/0021-real-apps.md))
- ☐ **SwiftData** `pf-swiftdata` · wasm · missing  
  `@Model`, `@Attribute`, `@Relationship`, `#Predicate` and `@ModelActor` macros, `ModelContainer`, `ModelContext` (insert, delete, fetch, save), `FetchDescriptor` with sort and predicate, `@Query` and `.modelContainer(for:)`: a macro package plus an in-memory store persisted to IndexedDB on wasm (decision needed: scope of the predicate language). The Countries app and Backyard Birds are built on it. ([0021-real-apps.md](Docs/decisions/0021-real-apps.md))
- ☐ **Durable files on wasm** `pf-persistence` · wasm · accepted  
  Partly done 2026-10-12 with pf-foundation-module: `FileManager`'s directories, `Data.write(to:)`/`Data(contentsOf:)` on file URLs and `UserDefaults` persist through the browser host in localStorage (a few MB in all). Open: `@AppStorage` and `@SceneStorage` do not exist yet (over UserDefaults, with the scene's id), the origin private file system for large files and binary data without base64, `FileManager` attributes, dates and enumerators, `UserDefaults.didChangeNotification` and key-value observing. Originally: `FileManager.default.urls(for: .documentDirectory)`, `Data.write(to:)` and `Data(contentsOf:)`, `UserDefaults` and `@AppStorage` compile on wasm but nothing survives a reload (Scrumdinger's FileService loads 'The file doesn't exist' and could not save). A document directory backed by the origin private file system (or localStorage for small files), and UserDefaults over localStorage. ([0021-real-apps.md](Docs/decisions/0021-real-apps.md))
- ☐ **UserNotifications over the Notification API** `pf-usernotifications` · Platform · missing  
  `UNUserNotificationCenter.current()`, `requestAuthorization(options:)`, `notificationSettings()`/`getNotificationSettings`, `UNAuthorizationStatus`, delegate for a foreground presentation, over `Notification.requestPermission` and `new Notification`; `UIApplication.registerForRemoteNotifications` accepted with the delegate's failure callback (no push service). The Countries app's `UserPermissionsInteractor` and `PushNotificationsHandler`. ([0021-real-apps.md](Docs/decisions/0021-real-apps.md))

## Landed

- ☑ 2026-10-12 **Measure the macOS presentation looks** `sw-mac-presentation-looks` · SwiftUI · Presentation
- ☑ 2026-10-12 **UIAppearance proxies** `uk-appearance` · UIKit · Views
- ☑ 2026-10-12 **Scenes and app lifecycle** `uk-scenes` · UIKit · App
- ☑ 2026-10-12 **Hardware keyboard and the focus system** `uk-keyboard` · UIKit · Events
- ☑ 2026-10-12 **UITextInput for custom text views** `uk-text-input` · UIKit · Text
- ☑ 2026-10-12 **Slider images, segment images, stepper repeat** `uk-controls-rest` · UIKit · Controls
- ☑ 2026-10-12 **Tab bar badges and the More tab** `uk-tabbar` · UIKit · Navigation
- ☑ 2026-10-12 **Table view corners** `uk-table-rest` · UIKit · Table view
- ☑ 2026-10-12 **Collection view corners** `uk-collection-rest` · UIKit · Collection view
- ☑ 2026-10-12 **Drag and drop interactions** `uk-dragdrop` · UIKit · Events
- ☑ 2026-10-12 **UISplitViewController** `uk-splitviewcontroller` · UIKit · Containers
- ☑ 2026-10-12 **Share and document pickers** `uk-system-sheets` · UIKit · Presentation
- ☑ 2026-10-12 **First frame and large lists** `pf-perf` · Platform · Performance
- ☑ 2026-10-12 **NSViewRepresentable and NSViewControllerRepresentable** `ix-appkit` · Interop · AppKit
- ☑ 2026-10-12 **Native text selection, IME and windows** `pf-native-text` · Platform · Native macOS
- ☑ 2026-10-12 **Linux: build, CI, painter and host** `pf-linux` · Platform · Linux
- ☑ 2026-10-12 **Charts, Map, VideoPlayer, WebView** `sw-frameworks` · SwiftUI · Other frameworks
- ☑ 2026-10-12 **`import Foundation` on wasm** `pf-foundation-module` · Platform · wasm
- ☑ 2026-10-12 **`import Combine` on wasm** `pf-combine-module` · Platform · wasm
- ☑ 2026-10-12 **contentShape and the Shape shortcuts** `sw-shape-shortcuts` · SwiftUI · Shape
- ☑ 2026-10-12 **API the surveyed apps reach for** `sw-app-api-gaps` · SwiftUI · View composition
- ☑ 2026-10-12 **Scene environment modifiers** `sw-scene-environment` · SwiftUI · App
- ☑ 2026-10-11 **Dynamic Type** `sw-dynamic-type` · SwiftUI · Text
- ☑ 2026-10-11 **Subviews-based ForEach and Group** `sw-subviews` · SwiftUI · View composition
- ☑ 2026-10-11 **Layout protocol corners** `sw-custom-layout` · SwiftUI · Layout
- ☑ 2026-10-11 **Safe area corners** `sw-safe-area` · SwiftUI · Position
- ☑ 2026-10-11 **Shape corners: strokedPath, container shapes, roles** `sw-shapes` · SwiftUI · Shape
- ☑ 2026-10-11 **Elliptical and mesh gradients** `sw-gradients` · SwiftUI · Gradient
- ☑ 2026-10-11 **Animated effects and drawing groups** `sw-effects` · SwiftUI · Effects
- ☑ 2026-10-11 **Image catalog forms and rendering** `sw-images` · SwiftUI · Image
- ☑ 2026-10-11 **SF Symbols fidelity** `sw-symbols` · SwiftUI · Image
- ☑ 2026-10-11 **AsyncImage caching and transactions** `sw-asyncimage` · SwiftUI · AsyncImage
- ☑ 2026-10-11 **Selecting text** `sw-text-selection` · SwiftUI · Text
- ☑ 2026-10-11 **TextEditor: selection, find, long content** `sw-texteditor` · SwiftUI · TextEditor
- ☑ 2026-10-11 **Context-dependent labels and formatted values** `sw-label-forms` · SwiftUI · Label
- ☑ 2026-10-11 **ContentUnavailableView in containers** `sw-content-unavailable` · SwiftUI · ContentUnavailableView
- ☑ 2026-10-11 **Slider styles and stepper repeat** `sw-slider-stepper` · SwiftUI · Slider and Stepper
- ☑ 2026-10-11 **A real colour panel** `sw-colorpicker` · SwiftUI · ColorPicker
- ☑ 2026-10-11 **Hover effects on controls** `sw-hover-looks` · SwiftUI · Hover
- ☑ 2026-10-11 **Contrast and per-presentation schemes** `sw-dark` · SwiftUI · Dark mode
- ☑ 2026-10-11 **Timeline modes and pausing** `sw-timeline` · SwiftUI · TimelineView
- ☑ 2026-10-11 **Rendering previews** `sw-previews` · SwiftUI · Preview
- ☑ 2026-10-11 **ShareLink items and previews** `sw-sharelink` · SwiftUI · ShareLink
- ☑ 2026-10-11 **Toolbar modifiers with an effect** `sw-toolbar` · SwiftUI · Toolbar
- ☑ 2026-10-11 **NavigationSplitView chrome** `sw-splitview` · SwiftUI · Navigation
- ☑ 2026-10-11 **Window commands, dragging and documents** `sw-windows` · SwiftUI · Windows
- ☑ 2026-10-11 **Table columns, styles and interaction** `sw-table` · SwiftUI · Table
- ☑ 2026-10-11 **Drags across the app boundary** `sw-dragdrop-os` · SwiftUI · Drag and drop
- ☑ 2026-10-11 **List editing: the rest** `sw-list-editing-rest` · SwiftUI · List
- ☑ 2026-10-11 **List looks: the rest** `sw-list-looks-rest` · SwiftUI · List
- ☑ 2026-10-11 **iOS presentations and bars: the rest** `sw-ios-presentation-rest` · SwiftUI · iOS profile
- ☑ 2026-10-09 **Search results, clear button and hiding on scroll** `uk-searchbar` · UIKit · Bars
- ☑ 2026-10-09 **UIImage data, tinting and animation** `uk-images` · UIKit · Images
- ☑ 2026-10-09 **UIRefreshControl** `uk-refresh` · UIKit · Scrolling
- ☑ 2026-10-09 **Zooming, inset adjustment and scroll-to-top** `uk-scroll-rest` · UIKit · Scrolling
- ☑ 2026-10-09 **UIPageViewController** `uk-pageviewcontroller` · UIKit · Containers
- ☑ 2026-10-09 **UIVisualEffectView and the glass** `uk-materials` · UIKit · Views
- ☑ 2026-10-09 **Layer corners, borders and shadows against pixels** `uk-view-pixels` · UIKit · Views
- ☑ 2026-10-09 **Trait overrides and observation** `uk-traits` · UIKit · Views
- ☑ 2026-10-09 **Gradient and text layers, display links, animation options** `uk-layers` · UIKit · Core Animation
- ☑ 2026-10-09 **Layout guides, animated constraints and stacks** `uk-autolayout-rest` · UIKit · Auto Layout
- ☑ 2026-10-09 **Blend modes, attributed drawing and CGPath** `uk-drawing-rest` · UIKit · Drawing
- ☑ 2026-10-09 **Accessibility notifications and custom actions** `uk-accessibility` · UIKit · Accessibility
- ☑ 2026-10-09 **UIPasteboard** `uk-pasteboard` · UIKit · App
- ☑ 2026-10-09 **WebFoundation's gaps against Foundation** `pf-web-foundation-gaps` · Platform · wasm
- ☑ 2026-10-09 **Right-to-left layout direction** `sw-rtl` · SwiftUI · Layout
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
