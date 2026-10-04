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
