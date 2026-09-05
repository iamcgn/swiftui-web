# toolbar, ToolbarItem, ToolbarItemGroup

Apple docs: [toolbar(content:)](https://developer.apple.com/documentation/swiftui/view/toolbar(content:)-5w0tj),
[ToolbarItem](https://developer.apple.com/documentation/swiftui/toolbaritem),
[ToolbarItemGroup](https://developer.apple.com/documentation/swiftui/toolbaritemgroup),
[ToolbarItemPlacement](https://developer.apple.com/documentation/swiftui/toolbaritemplacement),
[toolbar(_:for:)](https://developer.apple.com/documentation/swiftui/view/toolbar(_:for:)).

## API surface

| API | Notes |
|---|---|
| `toolbar(content:)`, `toolbar(id:content:)` with `ToolbarContentBuilder` | implemented (customisation is not offered) |
| `ToolbarItem(placement:content:)`, `ToolbarItem(id:placement:showsByDefault:content:)`, `ToolbarItemGroup(placement:content:)` | implemented |
| `ToolbarItemPlacement` (`automatic`, `principal`, `navigation`, `primaryAction`, `secondaryAction`, `status`, `confirmationAction`, `cancellationAction`, `destructiveAction`, `keyboard`, `bottomBar`, `topBar*`, `navigationBar*`) | implemented: `navigation`/leading placements lead, `principal`/`status` centre, the rest trail; `keyboard` and `bottomBar` are dropped |
| `toolbar(_:for:)` with `Visibility` and `ToolbarPlacement` | implemented for the window toolbar |
| `toolbarBackground`, `toolbarRole`, `toolbarTitleDisplayMode`, `ToolbarRole`, `ToolbarTitleDisplayMode` | accepted without effect |
| Custom `ToolbarContent` types with a `body` | implemented |
| Toolbar customisation, `ToolbarCommands`, search fields in toolbars, sheet toolbars | missing |

## Behaviour

On macOS the toolbar belongs to the window: SwiftUI hands the items to the window's unified
toolbar, above the content view. A browser page has no window chrome, so the runtime draws one
when the host asks (`Runtime.paintsWindowChrome`; the browser host does, the native host does too
but keeps the title out of it, `chromeShowsTitle`, since its window has a title bar; fixture pages
in the gallery leave it off unless opened with `?chrome=1`).

`ToolbarNode` (`toolbar`) is transparent to layout and registers its items with the runtime
while mounted (`Runtime.toolbarItems`, in tree order); `ToolbarVisibilityNode` (`toolbar(.hidden,
for:)`) hides the bar. In `layout(in:)` the runtime builds `ToolbarChromeNode` from `_ToolbarBarView`
(an `HStack`: leading items, the `navigationTitle` in 15 pt bold, a spacer, principal items, a
spacer, trailing items, 8 pt apart with an 8 pt margin) across the top of the window at
`Runtime.toolbarHeight` (52 pt), and lays the root content out in the rest of the window; the bar
paints after the content (window background, a 12 % ink hairline at its bottom, then the items),
before presentations, and is hit tested before the content. Buttons in the bar take
`_ToolbarButtonStyle`: the label in 13 pt semibold, 8 pt horizontal padding, a 36 pt capsule
platter (a 12 % grey standing in for the glass pill, 30 % while pressed). Groups are laid out as
their views, so each button in a group gets its own platter as on macOS. Hovering and keyboard
focus reach the bar through `interactiveNodes`.

## Measured (macOS 26.2, a titled `NSWindow` with an `NSHostingView`, 2026-09-04)

| Property | Value |
|---|---|
| Title bar + toolbar height | 52 pt (`NSTitlebarContainerView`; the content view starts below it) |
| Item platters | 36 pt tall, 8 pt from the bar's top, trailing group right-aligned with 8 pt gaps and an 8 pt margin (`NSToolbarPlatterView` frames 550.5–592 in a 600 pt window) |
| Item widths | the label plus 8 pt each side ("Action" 56, "One" 41.5, a symbol 37.5) |
| Navigation placement | leading, after the window buttons (x 96 with the traffic lights; this bar has none, so 8) |
| Title | after the leading items, bold, in the same row |
| Groups | `ToolbarItemGroup { One; Two }` produces two separate platters |

The measurement comes from an on-screen window (the window server composites the toolbar; a
`cacheDisplay` capture holds only the content view), so no golden can include the bar:
`toolbar/basic` records the content alone and hosts without chrome match it.

## Verification (2026-09-04)

`toolbar/basic`: Tier A exact, Tier C 0.00 % and Tier B exact frames (the bar off, as in the
capture). `Playwright/toolbar-probe.mjs` opens the fixture with `?chrome=1` and checks the bar's
52 pt height, the 36 pt platters, the leading and trailing placement, the content below the bar,
and that toolbar and group buttons run their actions. `ToolbarTests` cover item collection and
placement, the bar's frame and painting, the content's remaining area, hit testing, chrome off,
`toolbar(.hidden)`, and items disappearing with their view.

## Not yet covered

Toolbar customisation and identifiers, `ToolbarCommands`, search in the toolbar, toolbars of
sheets and popovers, `toolbarBackground` materials, the sidebar toggle item, and a real
`NSToolbar` in the native host.
