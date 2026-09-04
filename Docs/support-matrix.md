# SwiftUI support matrix

Generated from `Docs/support.json` by `scripts/support-matrix.py`. Anything not listed is not implemented.

| Status | Meaning |
|---|---|
| ✅ full | API complete, fixtures pass exact layout and pixel checks |
| 🟢 partial | Common usage works; listed gaps |
| 🟡 approximate | Works but rendering knowingly differs (e.g. SF Symbols substitute) |
| 🟠 stub | Compiles, no behaviour |
| ❌ missing | Not implemented |

## App lifecycle

| API | Status | Notes | Fixtures |
|---|---|---|---|
| `App / Scene / WindowGroup / @main` | 🟢 partial | App/Scene/WindowGroup/SceneBuilder API; main() mounts the first WindowGroup in the canvas host (wasm) or lays out headlessly; Tier B (Chromium) within tolerance |  |

## View composition

| API | Status | Notes | Fixtures |
|---|---|---|---|
| `View / ViewBuilder (if/else, optional, switch, #available, any child count)` | 🟢 partial | Runtime node tree with structural identity; no layout or painting yet; Tier B (Chromium) within tolerance |  |
| `EmptyView / TupleView / Group / _ConditionalContent / Optional` | 🟢 partial | Runtime nodes exist; no layout yet; Tier B (Chromium) within tolerance |  |
| `AnyView` | 🟢 partial | Runtime nodes exist; no layout yet; Tier B (Chromium) within tolerance |  |
| `ViewModifier / ModifiedContent / EmptyModifier / modifier(_:)` | 🟢 partial | Runtime nodes exist; no layout yet; Tier B (Chromium) within tolerance |  |
| `EnvironmentValues / EnvironmentKey / environment(_:_:) / transformEnvironment` | 🟢 partial | @Entry macro not provided; Tier B (Chromium) within tolerance |  |
| `Transaction / TransactionKey / withTransaction` | 🟠 stub | No `animation` member until the animation system exists |  |
| `id(_:) / IDView` | 🟢 partial | Identity change rebuilds the subtree; Tier B (Chromium) within tolerance |  |
| `ForEach (Identifiable, id:, Range<Int>, Binding collections) / DynamicViewContent` | 🟢 partial | Keyed reconciliation: state follows ids across insert/mutate/reorder/remove (foreach/identity, 4 steps); modifiers distribute per element; no editActions, onDelete/onMove, or Subviews-based forms; Tier B (Chromium) exact frames, ≤ 0.3 % pixels incl. every identity step | foreach/* |
| `Section (content/header/footer, title forms, deprecated argument orders)` | 🟢 partial | Transparent outside List/Form: header, content and footer flatten in order, exact against goldens; inside List: styled header/footer, spacing, pinned first header (list/sections); no Form styling, isExpanded or collapsible; Tier B (Chromium) exact frames, ≤ 0.3 % pixels | section/* |
| `DynamicProperty (custom, nested)` | 🟢 partial | update() and nested installation; Tier B (Chromium) within tolerance |  |
| `#Preview / PreviewTrait / PreviewProvider` | 🟠 stub | The macro expands to nothing (SwiftUIWebMacros, prebuilt swift-syntax) so preview blocks compile; nothing renders previews |  |

## Views

| API | Status | Notes | Fixtures |
|---|---|---|---|
| `Text (verbatim/localized/interpolation, concatenation with mixed styles)` | 🟢 partial | Layout exact with recorded metrics on 17 fixtures; default font is the 13 pt system font and bold() resolves per text style (decision 0010); concatenated parts keep font/weight/traits/colour; wrapping, character wrapping, hard newlines, lineLimit (Int, ranges, reservesSpace), truncationMode head/middle/tail, multilineTextAlignment, lineSpacing; no localization tables, kerning/tracking, attributed strings, height-pressure truncation; Tier B (Chromium) exact frames on all 17 text fixtures, pixels ≤ 1.9 % (system-font fallbacks 4.7 %); WebKit exact frames, text pixels ≤ 1.1 %; Firefox exact frames, pixels ≤ 3.5 % (hinting) | text/* |
| `lineLimit / multilineTextAlignment / truncationMode / lineSpacing (View + EnvironmentValues)` | 🟢 partial | All lineLimit overloads (lower bounds reserve lines); truncation at character granularity with spaces dropped next to the ellipsis; alignment shifts lines by drawn width; a text under height pressure does not drop lines yet; Tier B (Chromium) exact frames on all 17 text fixtures, pixels ≤ 1.9 % (system-font fallbacks 4.7 %); WebKit exact frames, text pixels ≤ 1.1 %; Firefox exact frames, pixels ≤ 3.5 % (hinting) | text/line-limit, text/truncation, text/alignment, text/line-spacing |
| `allowsTightening / minimumScaleFactor` | 🟠 stub | Environment values stored, not applied to layout |  |
| `VStack / HStack / ZStack` | 🟢 partial | Layout exact against goldens; no painting yet; Tier B (Chromium) within tolerance | layout/* |
| `Spacer` | 🟢 partial | Layout exact; no painting yet; Tier B (Chromium) within tolerance | layout/spacer, layout/spacer-min-length |
| `Button` | 🟢 partial | bordered (default), borderedProminent, plain exact in layout; borderless approximate (grey label in a window); custom ButtonStyle; press state; no roles/disabled; Tier B (Chromium) within tolerance | button/basic, button/styles |
| `Toggle (isOn:label:, title, image, systemImage, configuration) / ToggleStyle / ToggleStyleConfiguration / toggleStyle` | 🟢 partial | Checkbox (default), switch and button styles measured in layout and on/off pixels; activation on release inside; checkbox semantics (aria-checked); no pressed/hover/focus looks, keyboard, mixed state or Toggle(sources:) | toggle/basic, toggle/styles, toggle/steps |
| `Label (title:icon:, image, systemImage) / LabelStyle (automatic, titleAndIcon, titleOnly, iconOnly) / labelStyle` | 🟢 partial | Icon centred on half the cap height above the title's baseline, 8 pt spacing (measured); systemImage is the stub symbol; the automatic style is not context sensitive | label/basic |
| `List (content, selection, data/id/Range forms) / ListStyle (automatic, inset, plain, bordered, sidebar) / listStyle` | 🟢 partial | macOS row geometry, separators, section headers/footers with the pinned first header, styles, single and multiple selection by press, labels' icon slot and tint measured; no outline lists, edit actions, keyboard selection, focused (accent) highlight, alternating backgrounds or custom styles | list/basic, list/sections, list/styles, list/modifiers, list/steps |
| `NavigationStack (root, NavigationPath and collection path bindings) / NavigationPath / NavigationLink (destination, value forms)` | 🟢 partial | Content-sized stack (macOS hosted window), pushed views centred with earlier views laid out beneath, bordered-button links outside lists and plain row links inside, Runtime.navigateBack() for hosts; no back button/title chrome, animation, NavigationSplitView, toolbars, navigationDestination(item:) | nav/basic, nav/list, nav/title, nav/sizing, nav/steps |
| `Picker (title, string, custom label) / PickerStyle (automatic, menu, segmented, radioGroup, inline, palette) / pickerStyle / tag` | 🟢 partial | macOS pop-up button, segmented control and radio group geometry measured; segmented and radio selection by press; the pop-up opens a menu through the presentation layer (approximate look); text options only in the pop-up and segmented styles | picker/basic, picker/forms, picker/steps |
| `Slider (value, range, step, label, min/max value labels, onEditingChanged)` | 🟢 partial | 16 pt flexible track with a 22 × 16 knob, ticks when stepped, body label and footnote value labels pixel-aligned; presses jump and drags follow; no keyboard control or vertical sliders | slider/basic, slider/steps |
| `Stepper (value/step/bounds and closure forms, onEditingChanged)` | 🟢 partial | 20 × 26 chevron button pair 8 pt after the body label; top half increments, bottom half decrements within bounds; no press-and-hold repeat or keyboard control | stepper/basic, stepper/steps |
| `Form / FormStyle (automatic, columns, grouped) / formStyle` | 🟢 partial | Columns layout with a label column and measured control spacing (exact), grouped cards with padded rows and separators, form-aware TextField/Toggle/Picker/Slider/Stepper rows; no LabeledContent, DisclosureGroup, GroupBox; grouped section headers unverified | form/basic, form/sections, form/styles, form/steps |
| `Layout protocol (custom layouts, caches, LayoutSubviews/LayoutSubview, LayoutValueKey) / AnyLayout / HStackLayout / VStackLayout / ZStackLayout` | 🟢 partial | Custom layouts written on the public API match Apple's frames exactly; AnyLayout switches layouts keeping subview state; no Animatable layout parameters or right-to-left direction | customlayout/flow, customlayout/radial, customlayout/values, customlayout/any |
| `Grid / GridRow / gridCellColumns / gridColumnAlignment / gridCellAnchor / gridCellUnsizedAxes` | 🟢 partial | Column sizing, spans, flexible sharing, spacing from cell preferences, alignment and anchors match Apple's frames exactly; no GridLayout value or lazy grids | grid/basic, grid/spacing, grid/modifiers, grid/alignment, grid/flexible |
| `Canvas / GraphicsContext (fill, stroke, text, transforms, opacity, clip, drawLayer) / ResolvedText` | 🟢 partial | Immediate-mode drawing recorded into the display list (a concat op for rotated text); pixels within 0.11 % of Apple's; gradient shadings, images, blend modes, filters or symbols | canvas/basic, canvas/sizing |
| `Gradient / LinearGradient / RadialGradient / AngularGradient / HierarchicalShapeStyle (fills, strokes, backgrounds, text, Canvas shading)` | 🟢 partial | Display-list gradient ops painted by Canvas2D, stops blended in Oklab (≤ 0.08 % pixels); text foreground gradients through an offscreen mask; Canvas gradient shadings; .primary keeps the inherited style; no elliptical or mesh gradients, image gradients | gradient/basic, gradient/text |
| `Menu / MenuStyle / menuIndicator / contextMenu` | 🟢 partial | Pull-down and split buttons exact; menus, submenus and context menus through the presentation layer (rows, separators; no hover highlight, checked items, section headers or keyboard navigation) | menu/basic |
| `onKeyPress / onMoveCommand / onExitCommand / onDeleteCommand / keyboardShortcut / focusable / KeyEquivalent / EventModifiers / KeyPress` | 🟢 partial | Key presses dispatched from the focused view outwards, then menus, shortcuts and Escape; general focus with a ring for buttons and focusable views; list arrow-key selection and menu keyboard navigation (looks unverified); no key-up phases, onKeyPress(characters:), focus sections or default focus | keyboard/basic |
| `ProgressView (value/total, labels, currentValueLabel) / ProgressViewStyle (automatic, linear, circular) / ControlSize / controlSize(_:) / tint(_:)` | 🟢 partial | Determinate bars and rings measured exactly (inactive-window greys); the indeterminate spinner and bar are the animation's first frame; tint accepted without effect; no Progress objects or timer intervals | progress/basic, progress/indeterminate |
| `TimelineView / TimelineSchedule (periodic, everyMinute, explicit, animation, custom)` | 🟢 partial | Wakes through main-actor Task.sleep (no Foundation timers on wasm); the animation schedule follows host frames; no lowFrequency distinction or Timer APIs | timeline/basic |
| `TextField (title/prompt/label forms) / SecureField / TextFieldStyle (automatic, roundedBorder, squareBorder, plain) / textFieldStyle` | 🟢 partial | Bezel, insets, baseline, placeholder, bullets and disabled look measured; editing through the host's transparent <input> (browser caret/selection/IME); no @FocusState, multi-line (axis), formatted values or custom styles | textfield/basic, textfield/styles, textfield/steps |
| `Divider` | 🟢 partial | Layout exact (1pt); no painting yet; Tier B (Chromium) within tolerance | layout/divider |
| `Color (as a view)` | 🟢 partial | macOS light system colour table; painting via display list; Tier B (Chromium) within tolerance | paint/system-colors |
| `Layout protocol / custom layouts / layoutValue` | 🟢 partial | sizeThatFits, placeSubviews, spacing, explicitAlignment, cache; no RTL; Tier B (Chromium) within tolerance |  |
| `Font (text styles, system(size:weight:design:), bold/weight/italic/monospaced)` | 🟢 partial | macOS text-style table; bold() is a per-style trait; italic keys; Tier B (Chromium) within tolerance | text/styles, text/system-fonts, text/modifiers |
| `Rectangle / RoundedRectangle (circular, continuous) / UnevenRoundedRectangle / Circle / Ellipse / Capsule` | ✅ full | Paths identical to Apple's element for element (74 recorded paths, PathGoldenTests): continuous corner curves, radius limits, start points; Tier B pixels ≤ 0.24 % Chromium, ≤ 0.11 % WebKit | shape/builtin, shape/layout, paint/shapes |
| `Path (move/line/curves, addArc/addRelativeArc, rects, ellipses, rounded rects, description and init?(_:), applying, contains, trimmedPath, forEach)` | ✅ full | Element order, arc sweep rules and trimming match Apple; addArc(tangent1End:…) implemented from CGPath's definition, unverified; no cgPath | shape/path, shape/modifiers |
| `Path.strokedPath(_:)` | 🟡 approximate | Oriented polygons per segment, join and cap (a nonzero fill unions them), dashes honoured; Apple computes the offset outline. Painters stroke natively, so this only affects clipping and hit testing with a stroked shape | shape/modifiers |
| `Shape.fill / stroke, StrokeStyle (caps, joins, miter limit, dash, phase), FillStyle (eoFill), FillShapeView / StrokeShapeView / StrokeBorderShapeView chaining` | ✅ full | antialiased flags stored without effect (canvas always antialiases); Tier B within tolerance in three browsers | shape/stroke, shape/path, shape/steps |
| `InsettableShape / inset(by:) / strokeBorder` | ✅ full | Rounded rectangles shrink their radii by the inset like Apple; an inset shape lays out like a plain shape (measured) | shape/stroke, shape/modifiers |
| `Shape modifiers: trim / offset / scale / rotation / transform / size / stroke(style:) as a Shape, AnyShape` | ✅ full | Only trim and stroke keep the base shape's layout (a trimmed circle stays square); the others take the proposal (measured) | shape/modifiers, shape/layout |
| `ContainerRelativeShape` | 🟡 approximate | A rectangle; container shapes are not modelled |  |
| `Shape boolean operations (union / intersection / subtracting / symmetricDifference / lineIntersection / lineSubtraction)` | ❌ missing |  |  |
| `Angle` | ✅ full | radians/degrees, Comparable, Animatable | shape/path |
| `GeometryReader / GeometryProxy (size, frame(in:), bounds(of:))` | 🟢 partial | No safe area or anchors; Tier B (Chromium) within tolerance | all (probe implementation) |
| `ScrollView (axes, showsIndicators) / ScrollViewReader / ScrollViewProxy.scrollTo` | 🟢 partial | Fills the proposal along its axes and is exactly content-sized across them, implicit VStack content, clipping, defaultScrollAnchor, scrollTo with/without anchor resolved at layout; wheel scrolling with chaining, touch pan + momentum (0.998/ms), overlay indicators while scrolling (approximate geometry); no bounce, keyboard scrolling, scrollPosition/scrollTargetBehavior, contentMargins or lazy stacks; Tier B exact frames in Chromium, WebKit and Firefox (17/17 renders each) | scroll/* |
| `Image(_:bundle:) / Image(decorative:bundle:) / Image(_:bundle:label:) from asset catalogs` | 🟢 partial | scripts/assets.py reads *.xcassets into a manifest (decision 0011): image sets with 1x/2x/3x, mac/universal idiom, light/dark appearance, folder namespaces, template intent; PNG/JPEG/GIF. Rigid at pixels ÷ scale; missing name is 0 × 0. Tier A exact; Tier B exact frames in Chromium, WebKit and Firefox. Open: PDF/SVG sets, slicing metadata, dark-appearance goldens, bundle: ignored (absent on wasm) | image/intrinsic, image/stack-spacing, image/swap |
| `Image.resizable(capInsets:resizingMode:) / renderingMode / interpolation / antialiased` | 🟢 partial | Stretch, nine-part stretch, tile and nine-part tile; template tint from the foreground style; interpolation(.none) is nearest neighbour, other levels smooth; antialiased stored only. Cap insets with .tile draw all nine parts where AppKit drops the bottom row (1.6 % pixels in image/tiling) | image/resizable, image/template, image/tiling |
| `Image(systemName:) / Image.Scale / imageScale(_:) / View.fontWeight / View.bold` | 🟢 partial | Measured SF Symbol layout (240 symbols at the text-style sizes, 13 pt weights and image scales; scaled elsewhere) with Lucide icons (ISC) standing in for the glyphs, 1551 names; no rendering modes, variants or effects | symbol/basic, symbol/catalog-13 |
| `Image(nsImage:) / Image(cgImage...) / Image(size:label:renderer:) / AsyncImage` | ❌ missing | No CGImage/NSImage on wasm |  |
| `Color(_:bundle:) from asset catalog colour sets / ColorScheme / colorScheme environment` | 🟢 partial | sRGB components in float, hex and integer spellings; the light or dark variant per environment.colorScheme (default light; nothing else reads it yet). Display P3 components are used as sRGB. A missing name is clear (assumed) | color/named |

## State

| API | Status | Notes | Fixtures |
|---|---|---|---|
| `@State` | 🟢 partial | Box per node; writes coalesce; no animation transactions yet; Tier B (Chromium) within tolerance |  |
| `@Binding` | 🟢 partial | get/set, constant, dynamic member lookup, optional and collection projections; Tier B (Chromium) within tolerance |  |
| `@Environment` | 🟢 partial | Key-path and Observable-object forms (`Environment(Model.self)`, optional variant); `.environment(object)`; Tier B (Chromium) within tolerance |  |
| `@Observable / @Bindable` | 🟢 partial | Per-body withObservationTracking; only reading nodes invalidate. Bindable via ReferenceWritableKeyPath; Tier B (Chromium) within tolerance |  |
| `ObservableObject / @Published / @StateObject / @ObservedObject / @EnvironmentObject` | 🟢 partial | Combine-free implementation (ObservableObjectPublisher, AnyCancellable, @Published through the enclosing-instance subscript); typealiases in the SwiftUI shim shadow Foundation's Combine re-export on macOS; no onReceive or Combine operators (Docs/elements/ObservableObject.md) | observable/object |
| `ObservableObject / ObservableObjectPublisher / AnyCancellable / @Published / @StateObject / @ObservedObject / @EnvironmentObject / environmentObject` | 🟢 partial | Combine-free implementation: closure subscribers, enclosing-instance @Published, per-identity state objects, re-subscription on replacement; no Combine operators or onReceive | observable/object |
| `@FocusState (Bool, optional Hashable) / focused(_:) / focused(_:equals:)` | 🟢 partial | Text fields only; state and browser focus mirror each other in both directions (click, Tab, blur, programmatic); no focusable(), FocusedValue, key handling; focus on buttons and focusable views too (Docs/elements/Keyboard.md) | focus/basic |

## Modifiers

| API | Status | Notes | Fixtures |
|---|---|---|---|
| `padding` | 🟢 partial | Layout exact; Tier B (Chromium) within tolerance | layout/padding-default, layout/padding-edges |
| `frame` | 🟢 partial | Fixed and flexible forms exact; Tier B (Chromium) within tolerance | layout/frame-fixed, layout/frame-flex |
| `background / overlay` | 🟢 partial | View, style and shape forms; layout exact, display-list painting; Tier B (Chromium) within tolerance; one layer per element when applied to a list (foreach/modifier, section/modifier) | paint/background-overlay |
| `foregroundStyle / foregroundColor` | 🟢 partial | Flat colours only; Tier B (Chromium) within tolerance |  |
| `fixedSize / layoutPriority / alignmentGuide` | 🟢 partial | Layout exact; Tier B (Chromium) within tolerance | layout/fixed-size, layout/hstack-priority, layout/alignment-guide |
| `font(_:)` | 🟢 partial | Environment font; Tier B (Chromium) within tolerance | text/modifiers |
| `opacity / clipShape / clipped / cornerRadius` | 🟢 partial | Display-list groups and clips; Tier B (Chromium) within tolerance; applied per element on lists | paint/clipping |
| `preference / transformPreference / onPreferenceChange / coordinateSpace` | 🟢 partial | Bottom-up reduction after layout; no anchorPreference or overlayPreferenceValue yet; Tier B (Chromium) within tolerance |  |
| `onTapGesture` | 🟢 partial | Single tap via the pointer arena; count ignored; Tier B (Chromium) within tolerance |  |
| `scrollIndicators / scrollDisabled / scrollBounceBehavior / scrollClipDisabled / defaultScrollAnchor` | 🟢 partial | Environment-backed; scrollBounceBehavior is stored but has no effect (no rubber band); defaultScrollAnchor sets the initial offset only | scroll/modifiers, scroll/anchor-bottom |
| `onChange(of:initial:_:) (two- and zero-argument actions), deprecated onChange(of:perform:)` | 🟢 partial | Actions run from the scheduler's action queue after the update that changed the value; sibling onChange order is inner first | scroll/scroll-to |
| `aspectRatio(_:contentMode:) / aspectRatio(_ size:contentMode:) / scaledToFit / scaledToFill / ContentMode` | ✅ full | Ratio explicit or from the content's ideal size; the content is proposed the fitted or filling rectangle and keeps the last word (rigid images stay rigid). Exact against goldens for full, partial and absent proposals | image/aspect-ratio |
| `border(_:width:)` | ✅ full | An inset rectangle stroke overlaid on the content; no layout change (measured) | shape/border |
| `labelsHidden()` | ✅ full | Controls drop their label and its spacing (measured on Toggle) | toggle/basic, toggle/styles |
| `disabled(_:) / EnvironmentValues.isEnabled` | 🟢 partial | Blocks activation of buttons and toggles; toggles dim their control and label (measured), buttons do not dim yet | toggle/basic |
| `onSubmit(_:) / onSubmit(of:_:) / SubmitTriggers` | 🟢 partial | Return in a text field runs the action; triggers ignored |  |
| `autocorrectionDisabled(_:)` | 🟠 stub | Stored only |  |
| `listRowInsets / listRowBackground / listRowSeparator / listRowSeparatorTint` | 🟢 partial | Per-row insets, edge-to-edge background, bottom separator visibility and tint (top edge ignored); apply per element through a ForEach or Section | list/modifiers |
| `listSectionSeparator / listSectionSeparatorTint / listItemTint` | 🟠 stub | Stored only |  |
| `navigationDestination(for:) / navigationDestination(isPresented:) / navigationTitle` | 🟢 partial | Destinations registered by type with the enclosing stack, isPresented pushes and pops through observation, the title is recorded on the runtime (window chrome on macOS) | nav/basic, nav/steps |
| `navigationSubtitle / navigationBarBackButtonHidden` | 🟠 stub | Stored only |  |
| `onAppear / onDisappear / task(priority:) / task(id:priority:)` | 🟢 partial | Actions run through the scheduler after the update that inserts or removes the view; tasks start on appear, cancel on disappear and restart on an id change; no onReceive or scene-phase actions | lifecycle/appear |
| `Animation (linear, ease curves, timingCurve, springs, delay/speed/repeat) / withAnimation / Transaction.animation` | 🟢 partial | Curves evaluated per frame; frames, opacity and Color fills tween; no transforms, shape/text colour, Animatable custom data, completion callbacks or blending | animation/frame, animation/implicit |
| `animation(_:value:) / transaction(_:) / transition(_:) / AnyTransition (identity, opacity, move, slide, offset, combined, asymmetric)` | 🟢 partial | Scopes take precedence over the transaction for their subtree; removed views linger as ghosts through their transition; .scale fades (no transforms yet) | animation/implicit, animation/transition |
| `sheet / popover (isPresented and item forms) / alert / confirmationDialog / dismiss environment action` | 🟡 approximate | Presented over the window by the runtime's presentation layer (modal sheets and alerts, popovers and menus dismissed outside); the looks approximate macOS (separate windows there, no goldens); no fullScreenCover, detents, Menu, contextMenu | presentation/basic |
| `accessibilityLabel / Hint / Value / Identifier / Hidden / AddTraits / RemoveTraits / accessibilityElement(children:)` | 🟢 partial | Applied on the semantics tree that the canvas host mirrors as an ARIA DOM overlay (headings, images, groups, switches, range inputs, spinbuttons); no custom actions, sort priority or rotors | accessibility/basic |
| `offset / rotationEffect / scaleEffect / transformEffect / AnyTransition.scale` | 🟢 partial | Painted through the display list's concat op about their anchors, parameters animate, offsets move hit testing; no hit testing through rotation/scale, no GeometryEffect or 3D | transform/basic, transform/steps |
