# UIToolbar and UISearchBar

`Packages/UIKitWeb/Sources/UIKitWebCore/Containers/UIToolbar.swift`,
`Controls/UISearchBar.swift`. Fixtures `uikit/toolbar/basic` (Cancel / Done at the top, Edit,
plus, trash and share with a fixed space at the bottom, a bar sized to fit one item) and
`uikit/search/basic` (a placeholder, text with a Cancel button, the minimal style),
`uikit/search/looks` (a prompt, the bookmark button, the clear button once a bar edits) and
`uikit/nav/search-results` (a search controller that hides on scroll, presents a results
controller and shares the bottom with toolbar items), measured on the iPhone SE simulator (iOS 26).

## API

- `UIToolbar`: `items`, `setItems(_:animated:)`, `barStyle`, `isTranslucent`, `barTintColor`,
  `tintColor`, `standardAppearance` / `scrollEdgeAppearance` (`UIToolbarAppearance`, accepted),
  `sizeThatFits`. Items are `UIBarButtonItem`s (titles, images, system items, flexible and fixed
  spaces with `width`) drawn as the navigation bar's glass platters; a `done` item is filled with
  the tint. An item's `primaryAction` fires once per tap.
- `UISearchBar`: `text`, `placeholder`, `prompt`, `searchBarStyle` (`default`,
  `prominent`, `minimal`), `showsCancelButton` / `setShowsCancelButton(_:animated:)`,
  `showsBookmarkButton`, `showsSearchResultsButton` (`isSearchResultsButtonSelected` stored),
  `searchTextField` (a `UISearchTextField`, the `UITextField` the bar edits), `delegate`
  (`textDidChange`, `searchBarSearchButtonClicked`, `searchBarCancelButtonClicked`,
  `searchBarBookmarkButtonClicked`, `searchBarResultsListButtonClicked`,
  `should/DidBegin/EndEditing`), `becomeFirstResponder`, `barTintColor`, `returnKeyType`,
  `keyboardType`, `autocapitalizationType`. Editing goes through the substrate's text input.
  Scope bar: `scopeButtonTitles`, `showsScopeBar` / `setShowsScope(_:animated:)`,
  `selectedScopeButtonIndex`, the delegate's `selectedScopeButtonIndexDidChange`.

## Measured

- A toolbar is 48 tall (`sizeToFit` keeps the width it had: a zero frame stays 0 wide, and its
  one item centres on it, 24 to the left). Its content runs 16 in from each side. Every item is
  a 48 pt platter: a title's width plus 24 (78 for "Cancel", 54.5 for "Edit", 66 for the
  semibold "Done"), 48 for an image. Titles are 17 pt medium in a 24.5 pt label 12 down;
  a `done` item is semibold and white on the tint (0, 136, 255). Images are centred at their
  own size (23 × 22 plus, 24 × 28 trash, 24.5 × 30 share).
- Platters sit 12 apart; a fixed space adds its `width` to that gap (36 for a 24 pt space);
  flexible spaces share what is left after the platters, the fixed spaces and the 12 pt gaps
  (14.75 each in the bottom bar) and positions round to the pixel (81.5, 165.5, 240). Without
  a flexible space the items are centred.
- A search bar is 64 tall. Its field is a 44 pt capsule 8 in and 10 down, as wide as the bar
  less 16 (304 in 320), 249 when the Cancel button shows: the button is a 44 pt glass circle 8
  from the right edge (x 268) with a light (184) cross 22.5 × 21.5 at (10.5, 11), and the field
  ends 11 before it. The magnifier (20.5 × 20) sits at (12, 11.5) in the field; the text and
  placeholder are 17 pt medium starting 39.5 in, the placeholder in the secondary label colour
  (137, 137, 141 over white). The default style draws a faint band (252) with 0.5 pt hairlines
  at the bar's top and bottom; the minimal style draws no band and no capsule. The clear button
  UIKit lays out at the field's end is not drawn in the capture and not drawn here.
- Prompt (`uikit/search/looks`, 2026-10-09): a 34 pt band above the field (the bar 98 tall),
  its 14 pt label 18 tall 8 down, centred, in a dark slate (43, 62, 90). The bookmark button is
  the `book` symbol in a 22.5 × 17.5 image 38.5 before the field's end, 13 down, in the
  secondary label colour, shown while the field holds no text (the results list button the
  same with `list.bullet`); a tap calls the delegate. The clear button while editing is a 17 pt
  disc of the secondary label colour in a 20.5 button 34.5 before the field's end, 11.5 down;
  the text ends 44.5 before the capsule's edge beside it, 29.5 beside the bookmark, 7 alone.
- Scope bar (`uikit/search/scope`, 2026-09-11): with `showsScopeBar` and titles the bar grows to
  111 (64 plus a 47 pt band) and holds a segmented control 8 in and 7 below the field (y 71),
  304 wide, its segments of equal width with 15 pt regular titles (18 tall at 7), the selected
  one under the lens; titles without `showsScopeBar` change nothing (64 tall).
- Pixels: `uikit/toolbar/basic` 0.7 %, `uikit/search/basic` 0.6 %, `uikit/search/scope`
  1.7 % and `uikit/search/looks` 1.6 % (both frames) off the simulator.

## In a navigation controller (`uikit/nav/toolbar`, `uikit/nav/search`)

- A navigation controller's `toolbar` shows the top controller's `toolbarItems` when
  `isToolbarHidden` is false: a bar floating over the bottom, 76 tall (the platters in its top
  48, 28 below), its content 28 in from the sides. The flexible spaces split the items into
  groups: one group leads, two lead and trail, three put the middle one centred (Edit at 28,
  plus centred at 136, share at 244 in 320); more spread evenly. iOS 26 never puts the
  `UIToolbar` itself in the view hierarchy, so the golden pins the platters by pixels. The
  content's safe area gains the 76 pt below.
- A navigation item's `searchController` (`UISearchController`: `searchBar`,
  `searchResultsUpdater`, `isActive`, `obscuresBackgroundDuringPresentation`) puts an empty
  60 pt `UISearchBar` band under the navigation bar (y 116.5 under a large title, so the content
  starts at 176.5) and floats the field over the bottom in a 48 pt glass capsule 28 in
  (264 wide in 320): the `searchTextField` is 38 tall 5 in, its magnifier at (13, 8.5) and its
  17 pt medium placeholder 41.5 in. The toolbar hides while a search field floats there. Typing
  activates the controller and asks the updater for results; resigning deactivates it.
- `hidesSearchBarWhenScrolling` (`uikit/nav/search-results`, 2026-10-09): while the top
  screen's content can scroll, the item's search bar is a 0 pt band under the title (y 116.5
  under a large title, 64 collapsed) with no floating field, and the toolbar's platters show
  (the plus 28 in at the bottom); a pull past the content's top brings the 60 pt band and the
  floating field back, scrolling away hides them again (the pull itself is unmeasured). A
  screen that cannot scroll keeps the field floating.
- An active search controller (`isActive`, or typing into the field): the navigation bar
  becomes a 60 pt band at 10 holding the search bar, its field 16 in and 44 tall 8 down (233
  wide in 320) with the clear button, and a 44 pt cancel circle 16 from the trailing edge with
  a dark 17 pt cross; the title and items hide. The results controller's view fills the
  container (its label at (16, 16) under the bar) while the text is not empty or
  `showsSearchResultsController` is set; otherwise the content is dimmed 20 % when
  `obscuresBackgroundDuringPresentation` (approximate: unmeasured). The toolbar's platters stay.
  Cancel (or `isActive = false`) dismisses; `UISearchControllerDelegate` hears both ends and
  the updater every change. The bar's glass over the results is not painted.
- Scrolling under a collapsing large title: the offset follows the shrunken inset, so the
  content rises by the collapse (52.5): rows that sat at 139.5 at rest sit at 112.5 − 342 after
  `setContentOffset(200)` (the first `scroll` step). The blurred scroll edges under the
  collapsed bar and the toolbar are not painted (`uk-materials`), so that step is frames-only.
- Pixels: `uikit/nav/toolbar` 0.6 %, `uikit/nav/search` 1.2 %, `uikit/nav/search-results`
  0.5 % and its `activate` step 0.3 % off the simulator.

## Open

The scope bar in a navigation controller's floating search, the pull that reveals a hidden
search bar (unmeasured), the bar's glass over results and the blurred scroll edges
(`uk-materials`), `hidesNavigationBarDuringPresentation = false`, a search controller
presented outside a navigation item, dark mode samples (the dark colours are the platter's).
