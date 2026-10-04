# UIKit gesture recognizers

Apple docs: [UIGestureRecognizer](https://developer.apple.com/documentation/uikit/uigesturerecognizer),
[UIGestureRecognizerDelegate](https://developer.apple.com/documentation/uikit/uigesturerecognizerdelegate),
[UIPinchGestureRecognizer](https://developer.apple.com/documentation/uikit/uipinchgesturerecognizer),
[UISwipeGestureRecognizer](https://developer.apple.com/documentation/uikit/uiswipegesturerecognizer),
[UIScreenEdgePanGestureRecognizer](https://developer.apple.com/documentation/uikit/uiscreenedgepangesturerecognizer).

Without an Objective-C runtime there is no `#selector`: recognizers take a closure handler
(`UITapGestureRecognizer { _ in }`) and `addTarget(_:action:)` accepts a closure.

## API surface

| API | Notes |
|---|---|
| `UIGestureRecognizer` (`state`, `view`, `isEnabled`, `cancelsTouchesInView`, `delegate`, `location(in:)`, `numberOfTouches`, `require(toFail:)`) | implemented; `delaysTouchesBegan`/`delaysTouchesEnded` accepted |
| `UITapGestureRecognizer` (`numberOfTapsRequired`), `UILongPressGestureRecognizer` (`minimumPressDuration`, `allowableMovement`), `UIPanGestureRecognizer` (`translation`, `setTranslation`, `velocity`) | implemented (Phase 1); long presses time on the scene's frame clock |
| `UIHoverGestureRecognizer` | implemented (`Docs/elements/UIKit/UIView.md`) |
| `UISwipeGestureRecognizer` (`direction` set, `numberOfTouchesRequired`) | implemented 2026-10-04: recognizes once the finger travelled 50 pt mostly along a permitted direction within half a second (the perpendicular travel at most half the main one); a slow or sideways move fails |
| `UIScreenEdgePanGestureRecognizer` (`edges`) | implemented 2026-10-04: a pan that must start within 20 pt of one of its edges of the window; elsewhere it fails at once |
| `UIPinchGestureRecognizer` (`scale`, `velocity`), `UIRotationGestureRecognizer` (`rotation`, `velocity`) | implemented 2026-10-04 from the host's pinch (`UIKitScene.pinch`: a trackpad's control-wheel or Safari gesture events, two touches); begin once the scale moved a hundredth or the fingers half a degree; `location(in:)` is the pinch's centre, `numberOfTouches` 2 while active |
| `UIGestureRecognizerDelegate` (`gestureRecognizerShouldBegin`, `shouldReceive`, `shouldRecognizeSimultaneouslyWith`, `shouldRequireFailureOf`, `shouldBeRequiredToFailBy`) | implemented 2026-10-04 (arbitration below) |
| `numberOfTouchesRequired` beyond 1, `UITouch` sets for pinches, `interactivePopGestureRecognizer` (uk-nav-polish) | missing: the host delivers one pointer and a pinch summary, not two touches |

## Behaviour

`TouchRouter` hit-tests the press, gathers the enabled recognizers on the hit view and its
superviews (those whose delegate accepts the touch), and delivers `touchesBegan` / `Moved` /
`Ended` / `Cancelled` to them before the view; a recognizer that has recognized with
`cancelsTouchesInView` cancels the view's touches. After every delivery `TouchRouter.arbitrate`
decides between the recognizers sharing the touch:

- **Failure requirements.** `require(toFail:)`, or a delegate answering `shouldRequireFailureOf`
  / `shouldBeRequiredToFailBy`, holds a recognizer's `began` or `ended` while the required
  recognizer is undecided; it goes through once the required ones failed and fails when one of
  them recognized. At the touch's end an undecided requirement counts as failed, so a single tap
  deferring to a double tap fires on the first tap and fails on the second (UIKit would hold the
  single tap for the double-tap interval; recorded as an approximation).
- **Exclusivity.** Only one recognizer recognizes a touch: once one has begun or recognized, the
  others still possible fail, and a recognizer trying to begin after another has recognized
  fails, unless either delegate answers `shouldRecognizeSimultaneouslyWith`. A recognizer that
  failed stays failed until the touch sequence ends.
- **Actions** run for `began`, `changed`, `ended` and `cancelled`; a failure is not reported
  (UIKit's behaviour; the hover and earlier gesture tests never listened for it).
- **The framework's own recognizers** (a scroll view's pan, a table's swipe pan and tap, a
  collection view's tap) run alongside any other, as UIKit's internal recognizers cooperate:
  each decides for itself whether a drag is its (`UIScrollView.ignoringPan`, the table's
  delegate methods), so a carousel inside a list and a row swipe inside a scrolling table keep
  working under arbitration.

Pinches reach `UIKitScene.pinch(_:scale:rotation:at:time:)` from the host (the same route as
SwiftUIWeb's `MagnifyGesture`, `Docs/elements/Gestures.md`): the scene fixes the pinch and
rotation recognizers on the view under the centre and its superviews when the pinch begins and
feeds them every phase; they arbitrate like touch recognizers (the first to begin wins unless a
delegate allows both). A tree hosted inside SwiftUIWeb (representables) does not receive pinches
yet.

## Verification (2026-10-04)

`GestureTests` (UIKitWeb): swipe directions and speed, screen-edge pans starting at and away
from the edge, pinch and rotation phases, values, velocity, location and exclusivity with and
without a delegate, a pan failing a long press, `require(toFail:)` between a single and a double
tap, and the delegate's failure requirement between a pan and a swipe. No pixels change: the
goldens are untouched.

## Not yet covered

Two-touch data on `UITouch`, holding a single tap for the double-tap interval, pinches into
hosted trees, `UIScreenEdgePanGestureRecognizer` driving the navigation controller's interactive
pop (uk-nav-polish).
