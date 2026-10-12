# UINavigationController and UITabBarController

`Packages/UIKitWeb/Sources/UIKitWebCore/Containers/` (decision 0014, Phase 4): `BarItems.swift`
(`UIBarItem`, `UIBarButtonItem`, `UITabBarItem`, `UINavigationItem`, `UIMenu`),
`UINavigationController.swift` (the controller, `UINavigationBar`, the platter buttons),
`UITabBarController.swift` (the controller, `UITabBar`, the tab buttons). Fixtures
`uikit/nav/basic`, `large`, `push` (steps push and pop), `items`, `uikit/tabs/basic`, all exact
in `UIKitGoldenFrameTests` and within 1.6 % in `UIKitPixelTests`, from the iPhone SE simulator
on iOS 26 (`scripts/gen-goldens-sim.sh uikit --dump uikit/nav/` shows UIKit's bar internals).

## API

- `UINavigationController`: `init(rootViewController:)`, `viewControllers`,
  `setViewControllers(_:animated:)`, `pushViewController`, `popViewController`,
  `popToRootViewController`, `popToViewController`, `topViewController`,
  `visibleViewController`, `navigationBar`, `isNavigationBarHidden` / `setNavigationBarHidden`,
  `delegate` (`willShow`, `didShow`). An animated push slides the new screen in from the
  trailing edge over 0.35 s (ease in-out) while the old one moves a third of the width behind
  a 10 % veil; a pop reverses it; the leaving screen stays in the hierarchy until the slide
  ends (`NavigationTests`). The timing is SwiftUI's measured slide, not UIKit's own.
- `UINavigationBar`: `items`, `topItem`, `backItem`, `prefersLargeTitles`, `isTranslucent`,
  `barTintColor`, `titleTextAttributes`, the appearance objects (accepted; the iOS 26 look is
  drawn as measured).
- `UINavigationItem`: `title`, `titleView`, `leftBarButtonItem(s)`, `rightBarButtonItem(s)`,
  `hidesBackButton`, `backButtonTitle`, `largeTitleDisplayMode`, `backBarButtonItem`.
  `UIViewController.navigationItem`, `navigationController`, `tabBarController`, `tabBarItem`,
  `hidesBottomBarWhenPushed`.
- `UIBarButtonItem`: title, image, system item (with the symbol or title each shows),
  `primaryAction` (`UIAction`), `isEnabled`, `style`; the classic `target:action:` initializers
  accept their arguments and cannot dispatch them (no Objective-C runtime).
- `UITabBarController`: `viewControllers`, `selectedIndex`, `selectedViewController`, `tabBar`,
  `delegate` (`shouldSelect`, `didSelect`). `UITabBar`: `items`, `selectedItem`, `delegate`.
  `UITabBarItem`: title, image, `selectedImage`, system items, `badgeValue` (stored).

## Measured (iOS 26, iPhone SE simulator, no status bar)

- The bar sits 10 below the safe area's top and is 54 tall (an inline title: bottom at 64,
  SwiftUI's inline bar height), 106.5 with a large title (bottom 116.5). It is translucent with
  no background or separator over a plain screen; the top controller's view fills the whole
  container (0, 0, 320, 400) under it, and only its safe area moves.
- The inline title is 17 pt semibold, 24.5 tall at y 9.75, centred to the quarter point
  (126.75 for 66.5 wide). The large title is 34 pt bold at (16, 54), 49 tall; the inline title
  is not drawn with it.
- Bar button items are glass platters 44 tall at the bar's top, 16 from the edges, 8 apart: 44
  wide for an image or the back chevron, the title's width plus 24 for a title (54.5 for "Edit"
  in 17 pt medium, the label 12 in and 24.5 tall at 9.5). A system image is 23 × 22 at
  (10.5, 11). The platter is (252, 252, 252) with a faint wide shadow; the back button is a
  platter with a 2.5 pt label-coloured chevron 9 × 18.
- After a push the previous screen's view leaves the hierarchy (its probes disappear) and
  returns on pop; the bar shows the new title and a back platter.
- The tab bar is an 83 pt band at the bottom; a floating platter 62 tall sits at its top,
  centred, 94 + 86 × (n − 1) + 8 wide (188 for two tabs): tab buttons 94 × 54 at 4 in,
  overlapping by 8. The selected tab has a (233, 234, 234) lens (corner 27), a tint-coloured
  symbol 28 tall at 5.5 and a 10 pt semibold title at 35 (12 tall); the others are label-coloured
  with 10 pt medium titles. The selected child's view fills the container; its safe area's
  bottom is the band.

## Interactive pop, large-title collapse, title views, hidden tab bars, custom transitions (2026-10-04)

- `interactivePopGestureRecognizer` is a `UIScreenEdgePanGestureRecognizer` on the left edge:
  with more than one controller on the stack the top screen follows the finger across, the one
  below slides in from a third of the width behind under a fading 10 % veil (the push slide's
  geometry); releasing past half the width, or faster than 300 pt/s, completes the pop over
  the slide's remaining time and then pops the model (the delegate hears `didShow`); a shorter,
  slower release settles the screens back. The bar updates when the pop completes (UIKit
  crossfades it during the drag: open).
- The large title collapses as the content scrolls: a `UIScrollView` inside the top screen
  reports its offset to the navigation controller through the responder chain
  (`contentDidScroll`); scrolled past the large title's height (52.5) the bar shrinks to the
  inline 54 pt bar and the content's safe area with it, the content under the bar staying put
  (a scroll view with the automatic inset adjustment keeps its offset); back at the top it
  expands again. This is SwiftUI's measured iOS behaviour (`ios/nav/scroll`, `Docs/elements/
  Navigation.md`), applied to UIKit's bar; the intermediate states (the title shrinking with
  the scroll) are not drawn: the bar flips between the two heights.
- `titleView` takes its intrinsic size (else what it says fits, else its frame), at most the
  room between the items, centred in the bar's content area and moved off centre only when it
  would cover an item.
- `hidesBottomBarWhenPushed` on a controller pushed above a tab's root hides the tab bar while
  it or anything above it is on the stack (the bar does not slide away with the push: open);
  the content's safe area bottom becomes 0.
- Custom transitions: a `UINavigationControllerDelegate` returning an animator from
  `navigationController(_:animationControllerFor:from:to:)` moves the screens itself through
  `UIViewControllerContextTransitioning` (`containerView` is the navigation view, the new
  screen is already in it under the bar, `finalFrame(for:)` the container's bounds); the
  leaving screen is removed and the appearance transitions end when the animator calls
  `completeTransition`. `Docs/elements/UIKit/Presentation.md` has the presentation side.
- `NavigationPolishTests` cover each; no golden changes (the resting looks are the same).

Open: the bar crossfading during an interactive pop, the title shrinking with the scroll, the
tab bar sliding away with a push, tab bar badges and the More tab, appearance objects
(accepted). (Toolbars and `UISearchController` in the bar landed: `Docs/elements/UIKit/Bars.md`,
`uikit/nav/toolbar`, `uikit/nav/search`.)

## UIPageViewController (`uikit/page/scroll`, `uikit/page/curl`, iPhone SE simulator, iOS 26, 2026-10-09)

`Containers/UIPageViewController.swift`. `init(transitionStyle:navigationOrientation:options:)`
(`OptionsKey.interPageSpacing`, `.spineLocation`), `transitionStyle`, `navigationOrientation`,
`spineLocation`, `isDoubleSided` (stored), `dataSource` (`viewControllerBefore` / `After`,
`presentationCount` / `presentationIndex` for the indicator), `delegate`
(`willTransitionTo`, `didFinishAnimating(_:previousViewControllers:transitionCompleted:)`,
`spineLocationFor`), `viewControllers`, `setViewControllers(_:direction:animated:completion:)`
(one page; the delegate hears a finished transition), `gestureRecognizers` (the scroll
view's pan).

- The scroll style keeps a paging scroll view of three slots, the view widened by the
  inter-page spacing (−10 … 330 for 20 in 320), the slots a page plus the spacing apart with
  the current page in the middle one (its label at (24, 24)); only the current page's
  controller is a child until a drag begins, when the data source's neighbours join the outer
  slots and the drag settles on one of them (the page then moves to the middle and the
  offset recentres; `didFinishAnimating` reports the previous page and whether it changed).
  An edge without a neighbour ends the content at the current page.
- With a data source giving `presentationCount` the indicator is a `UIPageControl` 26 tall
  centred at the bottom (74 wide for three pages at (123, 374) in 320 × 400) and the pages are
  374 tall above it; a tap on it pages. Without counts the pages fill the view.
- The page-curl style shows its page edge to edge with no indicator and scrolls like the
  scroll style between pages (the curl itself is not drawn); the vertical orientation
  stacks the slots vertically.
- Pixels: `scroll` 0.2 %, its `forward` step 0.2 %, `curl` 0.2 %.

Open: the curl animation, two-page spreads (`spineLocation.mid`, `isDoubleSided`), the
animated `setViewControllers` (immediate).

## Tab bar badges and the More tab (uk-tabbar, `uikit/tabs/more` on the iOS 27 simulator, 2026-10-12)

- The bar shows at most five tabs: with six or more controllers the first four get tabs and
  the fifth is More (an ellipsis symbol, the title "More"), whose `moreNavigationController`
  lists the rest (`_MoreListController`: a plain table of their tab items' images and titles
  with disclosure chevrons; a row pushes the controller onto More's stack).
  `selectedViewController = controller` for one of them selects More with it pushed.
  `customizableViewControllers` is accepted (no Edit screen).
- The platter keeps 21 pt margins (278 wide in 320): when 94 + 86 × (n − 1) + 8 would exceed
  the width less 42, the buttons shrink and their overlap grows by half the shrink — five tabs
  are 70 × 54 at a 50 pt pitch (the dump's `_UITabButton`s at 4, 54, 104, 154, 204).
- Badges (`UITabBarItem.badgeValue`, `badgeColor`): a system-red capsule 21.5 tall (corner
  10.75) whose centre sits 5.5 past the trailing edge of the 28 pt image box, 6 from the
  button's top, a 12 pt medium white label 4 in and 2 down; a count is round (21.5), text widens
  it (34 for "New"). The badge is the button's accessibility value.
- `UITabBarAppearance` stays accepted without effect (the glass platter is drawn as it is).

Tier A exact, UIKit Tier C 1.75 %, Tier B within tolerance. `NavigationPolishTests.moreTabAndBadges`.
Open: the Edit screen for reordering tabs, `UITabBarAppearance`'s colours, the badge in the
compact (landscape) bar.


## UISplitViewController (2026-10-12, `uikit/split/columns`, `triple`, `modes`, `compact`, `collapsed`, Phase 9 item 42)

`Containers/UISplitViewController.swift`: `init(style:)` (`.doubleColumn`, `.tripleColumn`,
`.unspecified` for the classic `viewControllers` pair), `setViewController(_:for:)` /
`viewController(for:)` over the `.primary`, `.supplementary`, `.secondary` and `.compact`
columns, `preferredDisplayMode` / `displayMode`, `preferredSplitBehavior` / `splitBehavior`,
`preferredPrimaryColumnWidth(Fraction)` with the minimum and maximum (the supplementary too),
`primaryEdge`, `show(_:)` / `hide(_:)`, `show(_:sender:)` / `showDetailViewController(_:sender:)`
(added to `UIViewController`: a navigation controller pushes, a split view's secondary takes
it, else the parent or a presentation), `displayModeButtonItem` and its visibility,
`isCollapsed`, `presentsWithGesture` and `showsSecondaryOnlyButton` (accepted), and
`UISplitViewControllerDelegate` (`topColumnForCollapsingToProposedTopColumn`,
`displayModeForExpandingToProposedDisplayMode`, `willShow` / `willHide` column,
`didCollapse` / `didExpand`, `willChangeTo displayMode`, `collapseSecondary:onto:`).

Measured on the iPad Pro 13-inch simulator (iOS 27, `IOS_DEVICE=ipad`; the harness gives
windows 500 pt and wider a regular width class, as UIKitWeb's scene and the gallery's hosted
fixtures do; a window past the screen's edge snapshots stale, so the fixtures are 800 and
1000 wide). The primary, supplementary and secondary controllers are wrapped in navigation
controllers (the compact column shows as it is). Two columns tiled (`.oneBesideSecondary`):
the sidebar 320 wide at the leading edge and the secondary spanning the whole width under it,
its bar's title centred in the uncovered part (the detail's title at 560 in 800) and no
separator line; the sidebar's bar carries the toggle (`sidebar.leading` in a 44 pt glass
platter) 10 from its trailing edge with its title centred; `.secondaryOnly` moves the toggle to
the secondary's leading edge, 10 in. Overlay (`.oneOverSecondary`, the `.overlay` or
`.displace` behaviour alike for two columns): the secondary spans the width under black at
20 %, the sidebar over it with its toggle 16 from the edge and its title 3 left of centre. A
preferred primary width (240) replaces the 320. Three columns: the primary 280 and the
supplementary 340 wide; at 1000 the three cannot tile (the secondary would keep under 420),
so the supplementary sits at 0 with the secondary at 341 after a 1 pt `opaqueSeparator` and
the primary overlays them both, dimmed; "one" beside the secondary is the supplementary
(`.oneBesideSecondary` hides the primary, whose toggle moves to the supplementary's leading
edge), "two" adds the primary. Compact widths (under 500, `uikit/split/compact`, `collapsed`
on the iPhone): a compact column stands in for every other and takes no push from
`show(.secondary)`; without one the secondary collapses onto the primary's stack and shows on
top with a back button (the delegate's `topColumnForCollapsing…` returning `.primary` or
`collapseSecondary:onto:` returning true keeps the primary on top), and expanding gives it
its column back. Frames exact in every state; UIKit Tier C ≤ 0.26 %, Tier B 11/11.
`SplitViewControllerTests`.

Open: the sidebar's pan gesture (`presentsWithGesture`), the inspector column,
`twoDisplaceSecondary`'s slide (laid out as tiled), the mode transitions' animation, the
sidebar background style, the primary's minimum and maximum from the width (automatic
dimensions are the measured constants), three tiled columns' exact threshold.
