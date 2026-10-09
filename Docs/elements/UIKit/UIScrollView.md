# UIScrollView

`Packages/UIKitWeb/Sources/UIKitWebCore/Controls/UIScrollView.swift`. The scroll view under
`UITableView`, `UICollectionView` and `UITextView`; no fixture of its own (the tables and
collections pin its geometry at rest).

## API

`contentSize`, `contentOffset` (the bounds origin), `contentInset`, `setContentOffset(_:animated:)`,
`scrollRectToVisible`, `isScrollEnabled`, `bounces`, `alwaysBounceVertical` / `Horizontal`,
`isPagingEnabled`, `showsVerticalScrollIndicator` / `Horizontal`, `indicatorStyle`,
`flashScrollIndicators`, `decelerationRate`, `isDragging`, `isDecelerating`,
`panGestureRecognizer`, `delegate` (`scrollViewDidScroll`, `WillBeginDragging`,
`DidEndDragging(willDecelerate:)`, `DidEndDecelerating`, `DidEndScrollingAnimation`). Wheel
scrolling from the host reaches the innermost scroll view that can move.

## Momentum, bounce, paging and indicators (2026-09-11)

- A pan that ends with velocity carries the content at UIKit's deceleration rate (the velocity
  keeps 0.998 of itself per millisecond, `DecelerationRate.fast` 0.99), stopping at an edge or
  under 4 pt/s; a touch stops it.
- Dragging past an edge shows UIKit's rubber band, `(1 - 1 / (over * 0.55 / dimension + 1)) *
  dimension` (46.5 for 100 pt past the top of a 300 pt view), on the axes the content overflows
  (or `alwaysBounceVertical` / `Horizontal`) while `bounces`; releasing springs back over 0.4 s
  with no momentum.
- `isPagingEnabled` snaps to the page the release and a tenth of a second of its velocity point
  at, over 0.3 s.
- Indicators (`uikit/textview/basic`'s dump): 3 pt bars with 1.5 pt corners, black at 35 %
  (white at 50 % for the white style), 3 from the far edge and 3 from each end of a track, as
  long as the visible fraction of the content along the track (at least 36), placed by the
  offset. They show while the finger or momentum moves the content and fade out over 0.25 s,
  0.3 s after it stops; hidden at rest, as UIKit hides them.

- `adjustedContentInset` (2026-09-12): the content inset plus the safe area the scroll view lies
  under, per `contentInsetAdjustmentBehavior` (`.never` nothing, `.always` all of it, `.automatic`
  and `.scrollableAxes` the axes the content scrolls on); the offset is clamped against it and
  content resting at the top moves with a change of it (a `UIScrollView` in a representable
  under a SwiftUI bar starts its content below the bar: `ios/representable/safearea-scroll-ignored`).

## Refresh control (`uikit/scroll/refresh`, iPhone SE simulator, iOS 26, 2026-10-09)

`Controls/UIRefreshControl.swift`; `UIScrollView.refreshControl` (tables included).
`isRefreshing`, `beginRefreshing()` (sends nothing, as UIKit's does not; it does not scroll
either, so the fixture moves the content down by the control's height as an app would),
`endRefreshing()`, `attributedTitle` (its string in 12 pt, the attributes not applied),
`tintColor` for the spinner, `valueChanged` / `primaryActionTriggered` when a pull releases it.

- The control is a subview at the content's top, 320 × 60 (84.5 with a title: a 12 pt label
  17.5 tall 60.75 down, 300 wide from 10, 6.25 above the bottom), hidden at rest. Refreshing it
  moves 60 above the content and the scroll view's adjusted inset grows by its height, so the
  content rests under it (the table's rows 60 down; the plain scroll view's content 84.5 down).
- The spinner: eight 3.5 × 10 spokes with 1.75 pt corners, 5 to 15 from a centre 30 down in
  the control, in the label colour; refreshing they are a fifth bigger (4.2 × 12, 6 to 18) and
  turn (a step every 1/8 s, approximate: the simulator's spokes turned between captures too,
  the step's pixels within 1.3 %), fading from the lead spoke. During a pull the spokes appear
  one by one and grow with the distance (approximate: unmeasured); the pull that starts a
  refresh is the control's height, 60.
- Pixels: at rest 0.5 %, refreshing 1.2 %, ended 0.5 %.

## Zooming, inset rules, keyboard dismissal, scroll-to-top, indicator insets (`uikit/scroll/zoom`, `uikit/nav/scroll-inset`, 2026-10-09)

- Zooming: the delegate's `viewForZooming(in:)` is scaled by `zoomScale` /
  `setZoomScale(_:animated:)` (within `minimumZoomScale` … `maximumZoomScale`) about the
  content's origin: its transformed frame keeps its origin at zero (the 80 × 60 photo is
  160 × 120 at 2, 40 × 30 at ½, not centred) and the content size follows it; the offset stays
  where it was, clamped. `zoom(to:animated:)` picks the scale that fits the rectangle and puts
  the offset at its scaled origin (a 100 × 75 rectangle at (50, 50) of a 200 × 150 view in a
  200 × 150 scroll view: scale 2, offset (100, 100)). A pinch (`pinchGestureRecognizer`) zooms
  about its centre, the content point under the fingers staying under them; `isZooming`,
  `scrollViewWillBeginZooming`, `scrollViewDidZoom`, `scrollViewDidEndZooming(_:with:atScale:)`.
  `bouncesZoom` is stored (no bounce past the limits). Pixels: `zoom` 0.2 %, `zoomOut` 0.1 %.
- `.automatic` inset adjustment: besides the scrollable-axes rule, a view controller's first
  scroll view takes the safe area even when its content is shorter than the view (the label
  of a 120 pt content under a 54 pt bar sits at 80: `uikit/nav/scroll-inset`, 0.6 %); `.never`
  leaves it at its frame.
- `keyboardDismissMode`: `.onDrag` and `.interactive` resign the first responder as a drag
  begins (the interactive mode's finger-tracking is not modelled).
- Scroll-to-top: `UIKitScene.scrollToTop()` stands in for the status bar tap (the browser has
  none): the key window's frontmost scroll view that scrolls vertically and has `scrollsToTop`
  goes to its top, asking `scrollViewShouldScrollToTop` and telling `scrollViewDidScrollToTop`.
- Indicator insets: `verticalScrollIndicatorInsets`, `horizontalScrollIndicatorInsets`
  (`scrollIndicatorInsets` sets both; `automaticallyAdjustsScrollIndicatorInsets` stored) take
  the place of the 3 pt margins on the edges they set: the bar's right edge sits 4 in with a
  right inset of 4 (the simulator's bar: x 190 in 200). The simulator placed the top of an
  inset bar 3 above its 10 pt inset (y 7); UIKitWeb keeps it at the inset (approximate).

## Open

Zoom bouncing past the limits, the interactive keyboard dismissal, the inset bar's 3 pt
offset, the pull's exact threshold and the spokes' growth and rate.
