# toolbar, ToolbarItem, ToolbarItemGroup, searchable

Apple docs: [toolbar(content:)](https://developer.apple.com/documentation/swiftui/view/toolbar(content:)-5w0tj),
[ToolbarItem](https://developer.apple.com/documentation/swiftui/toolbaritem),
[ToolbarItemGroup](https://developer.apple.com/documentation/swiftui/toolbaritemgroup),
[ToolbarItemPlacement](https://developer.apple.com/documentation/swiftui/toolbaritemplacement),
[toolbar(_:for:)](https://developer.apple.com/documentation/swiftui/view/toolbar(_:for:)),
[searchable(text:placement:prompt:)](https://developer.apple.com/documentation/swiftui/view/searchable(text:placement:prompt:)-18a8f).

## API surface

| API | Notes |
|---|---|
| `toolbar(content:)`, `toolbar(id:content:)` with `ToolbarContentBuilder` | implemented (customisation is not offered) |
| `ToolbarItem(placement:content:)`, `ToolbarItem(id:placement:showsByDefault:content:)`, `ToolbarItemGroup(placement:content:)` | implemented |
| `ToolbarItemPlacement` (`automatic`, `principal`, `navigation`, `primaryAction`, `secondaryAction`, `status`, `confirmationAction`, `cancellationAction`, `destructiveAction`, `keyboard`, `bottomBar`, `topBar*`, `navigationBar*`) | implemented: `navigation`/leading placements lead, `principal`/`status` centre, the rest trail; `keyboard` and `bottomBar` are dropped |
| `toolbar(_:for:)` with `Visibility` and `ToolbarPlacement` | implemented for the window toolbar |
| `toolbarBackground`, `toolbarRole`, `toolbarTitleDisplayMode`, `ToolbarRole`, `ToolbarTitleDisplayMode` | accepted without effect |
| Custom `ToolbarContent` types with a `body` | implemented |
| `searchable(text:placement:prompt:)` (`Text`, key and string prompts), `SearchFieldPlacement` | implemented: a search field at the trailing end of the bar on macOS, at the bottom of an iOS navigation stack (iOS 26, "iOS" below); every placement lands there |
| `searchable(text:isPresented:…)` | implemented (2026-10-04): the presentation is the field's focus; the binding follows and drives it |
| `isSearching`, `dismissSearch` environment | implemented inside the searchable view: `isSearching` while the field is presented (focused) or the query is non-empty; `dismissSearch` clears the query and ends the presentation |
| `searchSuggestions(_:)`, `searchCompletion(_ String)`, `searchCompletion(_ token:)` | implemented: the rows show while the search is presented, in place of the content on iOS (a plain list in the accent colour) and in a menu under the field on macOS (approximate); a completion row sets the query or adds the token |
| `searchSuggestions(_:for:)`, `SearchSuggestionsPlacement` | accepted without effect |
| `searchScopes(_:scopes:)`, `searchScopes(_:activation:scopes:)`, `SearchScopeActivation` | implemented: a segmented control of the tagged scopes; iOS shows it in a 44 pt band under the hidden bar while presented, macOS in a 30 pt row under the toolbar (approximate); `.automatic` is on text entry on iOS and on presentation on macOS |
| `searchable(text:tokens:…)` (with `isPresented`, `suggestedTokens`), `token` builder | implemented: tokens precede the text as grey tags (iOS 26's 28.5 pt tags; small ones in the macOS field); `suggestedTokens` is accepted without effect |
| `searchPresentationToolbarBehavior(_:)` | implemented: `.avoidHidingContent` keeps the iOS bar while presented (unmeasured); the automatic behaviour hides it |
| `searchToolbarBehavior(.minimize)` (iOS 26), `SearchFieldPlacement.navigationBarDrawer` | accepted without effect |
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

`searchable` is `SearchableNode` (Runtime/SearchNodes.swift), also transparent: it registers
its binding, prompt, tokens and presentation (`Runtime.searchField`, the first mounted one) and
hands its content `isSearching` and `dismissSearch`. The presentation is the field's focus: the
field view's `FocusState` turns it on and off, and an `isPresented` binding (read where the
modifier is built, so observation tracks it) drives the focus. `searchSuggestions`,
`searchScopes` and `searchCompletion` are transparent nodes registering with the runtime; the
chrome reads them. On macOS the bar shows `_SearchFieldView` after the trailing items: a
magnifier symbol, the token tags and a plain-style `TextField` in a 36 pt capsule, 120–325 pt
wide with layout priority over the spacers; an active scope bar adds a 30 pt row with a centred
segmented picker under the bar, and the suggestions open in a `.menu` presentation anchored to
the field while it is presented. Typing goes through the host's text input overlay as for any
text field, into the binding, so the searchable view's body filters on it.

## Measured (macOS 26.2, a titled `NSWindow` with an `NSHostingView`, 2026-09-04)

| Property | Value |
|---|---|
| Title bar + toolbar height | 52 pt (`NSTitlebarContainerView`; the content view starts below it) |
| Item platters | 36 pt tall, 8 pt from the bar's top, trailing group right-aligned with 8 pt gaps and an 8 pt margin (`NSToolbarPlatterView` frames 550.5–592 in a 600 pt window) |
| Item widths | the label plus 8 pt each side ("Action" 56, "One" 41.5, a symbol 37.5) |
| Navigation placement | leading, after the window buttons (x 96 with the traffic lights; this bar has none, so 8) |
| Title | after the leading items, bold, in the same row |
| Groups | `ToolbarItemGroup { One; Two }` produces two separate platters |
| Title font | 15 pt semibold (`_NSToolbarTitleField`) |
| Search field | a 36 pt platter at the trailing end after a flexible space, 264 pt wide in a 600 pt window (36.5–325 allowed), 13 pt text, the magnifier 10 pt in |

The measurement comes from an on-screen window (the window server composites the toolbar; a
`cacheDisplay` capture holds only the content view), so no golden can include the bar:
`toolbar/basic` records the content alone and hosts without chrome match it.

## Verification (2026-09-04)

`toolbar/basic` and `toolbar/searchable`: Tier A exact, Tier C 0.00 % and Tier B exact frames
(the bar off, as in the capture). `Playwright/toolbar-probe.mjs` opens the fixtures with `?chrome=1`
and checks the bar's 52 pt height, the 36 pt platters, the leading and trailing placement, the
content below the bar, that toolbar and group buttons run their actions, and that typing in the
search field filters the list. `ToolbarTests` cover item collection and
placement, the bar's frame and painting, the content's remaining area, hit testing, chrome off,
`toolbar(.hidden)`, items disappearing with their view, and the search field's placement,
binding and `isSearching`.

## iOS (iPhone SE simulator, iOS 26, `ios/search/*`, 2026-10-04)

iOS 26 puts a navigation stack's search field at the bottom of the screen. `NavigationStackNode`
finds the `searchable` in its top screen and takes the bands from the content; the field is
`_IOSSearchBarView` (a `TextField` in a capsule) laid out in the bottom band, and the scope bar
`_IOSSearchScopeBarView` (a segmented `Picker` with `_inSearchScopeBar`) in its own band.

| Property | Value |
|---|---|
| At rest (`basic`) | the content ends 76 above the window's bottom (the list 287.5 tall under the large title in 480); the field is a 46 pt capsule 28 in from both sides (264 wide in 320), 405–451, fill (250, 251, 254) over the grey ground (white at 80 %) with a soft shadow below; the magnifier 20 in (a 16 × 16.5 glyph), the 17 pt prompt 48 in in the secondary colour, its line centred |
| Presented (`active` `present`) | the bar hides and the content starts 10 down (the list keeps no top inset); the field moves to 420.5–466.5, 12 in and 236 wide, next to a 48 pt cancel circle at (260, 420) with a 17 pt `xmark`; the caret is 26 pt tall at the text's start; the content ends 60 above the bottom |
| Suggestions | replace the content: a plain list with a top separator 16 in from both sides, rows 56 apart with their text 16 in, in the accent colour (0, 136, 255) |
| Scope bar (`activation: .onSearchPresentation`) | a 44 pt band (10–54, about (248) over white) holding a 288 × 32 segmented control 16 in from 12: fill (252), the selected segment (234) 2 in, 15 pt regular labels in the label colour, a soft shadow under the control; the content starts at 54 |
| Typed (`typed`) | the suggestions filter; a 17 pt grey clear circle (142, 142, 147) with a white cross ends the text 21 before the capsule's right edge |
| Tokens (`tokens`) | grey (142, 142, 147) tags 28.5 tall with 17 pt white text 4.5 in each side, 3 apart, starting where the text would (48 in); the text follows 4 after the last; the clear circle is nearly invisible at rest |
| Automatic scope activation | on text entry: the bar is absent while the field is empty (`active` `present` was measured with `.onSearchPresentation`; the automatic fixture showed none) |

UIKit scrolls the hidden content list while the search presents (its rows report 54 higher in
`present`, their normal place in `typed`), so those probes are ignored in every tier.

## Verification (2026-10-04)

`ios/search/basic`, `ios/search/active` (`present`, `typed`) and `ios/search/tokens`: Tier A
exact (the hidden rows ignored), Tier C 0.4–1.0 %, Tier B exact frames. `SearchTests` cover the
band at rest, focus presenting the search (the bar hidden, the scope band, the cancel button
ending it and clearing the text), completions setting the query or adding a token, scope
selection, `isSearching`, `avoidHidingContent`, text-entry activation, and the macOS toolbar's
scope row and suggestion menu.

## Not yet covered

Toolbar customisation and identifiers, `ToolbarCommands`, toolbars of sheets and popovers,
`toolbarBackground` materials, the sidebar toggle item, a real `NSToolbar` in the native host,
the macOS scope row and suggestion menu's real look (uncapturable), the iOS field minimising on
scroll (`searchToolbarBehavior`), suggested tokens, the keyboard's room under a presented search.
