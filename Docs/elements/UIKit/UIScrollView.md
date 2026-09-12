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

## Open

Zooming, `.automatic`'s extra rules inside navigation controllers, keyboard dismissal,
scroll-to-top, the indicator insets, refresh controls.
