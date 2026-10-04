# UIAlertController and modal presentation

`Packages/UIKitWeb/Sources/UIKitWebCore/Containers/UIAlertController.swift` (decision 0014,
Phase 4): `UIAlertController`, `UIAlertAction`, the alert card and its action buttons, and the
presentation container the scene puts in the window for every `present(_:animated:)` (a
dimming view and the presented view as the card its style calls for). Fixtures
`uikit/alert/basic` (steps present and dismiss), `uikit/alert/sheet`, `uikit/sheet/page`,
captured with the whole window (`UIKitFixture.capturesWindow()`: presentations live beside the
root controller's view), from the iPhone SE simulator on iOS 26.

## API

- `UIAlertController`: `init(title:message:preferredStyle:)` (`alert`, `actionSheet`),
  `message`, `actions`, `addAction`, `preferredAction`, `addTextField(configurationHandler:)`
  (the fields sit in the card and type through the host's text input; `textFields` reads
  them), presented with `present(_:animated:completion:)`; tapping an action dismisses the
  alert and runs its handler. `UIAlertAction`: `init(title:style:handler:)` (`default`, `cancel`,
  `destructive`), `isEnabled`.
- `UIViewController.present` / `dismiss` for any controller: `modalPresentationStyle`
  `pageSheet`, `formSheet` and `automatic` show the page sheet card; `fullScreen`,
  `overFullScreen` and the context styles fill the window; a tap outside a sheet dismisses it
  unless `isModalInPresentation`. Appearance callbacks run for presented controllers.
  Presented with `animated`, an alert scales in from 1.15 with a spring over 0.4 s while the
  dimming fades in, and leaves scaling to 0.9 and fading over 0.25 s; a sheet slides up from
  the bottom, eased out over 0.45 s, and back down over 0.4 s (followed, not measured: the
  goldens hold the end states, and the harness settles 1.2 s). `completion` and an alert
  action's handler run when the animation ends; `presentedViewController` clears at once. A
  controller that is already presenting refuses a second `present` (UIKit logs "Attempt to
  present ... which is already presenting ..." and does the same); the first stays. The
  presentation container holds its controller weakly and leaves the window if the controller
  is released while presented.
- Custom transitions (2026-10-04, `Containers/Transitioning.swift`): a presented controller's
  `transitioningDelegate` returning an animator from `animationController(forPresented:
  presenting:source:)` or `animationController(forDismissed:)` drives the presentation itself:
  `UIViewControllerAnimatedTransitioning.animateTransition(using:)` gets a
  `UIViewControllerContextTransitioning` whose `containerView` is the presentation container
  (its dimming is clear for the `custom` style, as the container lays out), with the
  controllers and views by key, `initialFrame(for:)` / `finalFrame(for:)` (the presented view's
  frame as the container laid it out) and `completeTransition`, after which `animationEnded`
  and the presenter's `completion` run and, for a dismissal, the container leaves the window.
  Interaction controllers and `UIPresentationController` are accepted and ignored (transitions
  run to completion; the container still places the presented view). `NavigationPolishTests`.

- Sheet detents, popovers and anchored action sheets (2026-10-04, `Containers/
  PresentationControllers.swift`): `presentationController` is a `UISheetPresentationController`
  for the sheet styles (`detents` with `.medium()`, `.large()` and `.custom(resolver:)`,
  `selectedDetentIdentifier`, `prefersGrabberVisible`, `preferredCornerRadius`,
  `animateChanges`, the delegate; `largestUndimmedDetentIdentifier` and the scrolling options
  accepted) and a `UIPopoverPresentationController` for `popover` and action sheets
  (`sourceView`/`sourceRect`, `barButtonItem`, `permittedArrowDirections`, `arrowDirection`,
  the delegate). A popover adapts to the page sheet on the iPhone unless its delegate answers
  `.none` from `adaptivePresentationStyle`; the adaptive delegate's `shouldDismiss`,
  `willDismiss`, `didDismiss` and `didAttemptToDismiss` run for taps outside a sheet or popover.
  `UIPresentationController` subclasses are accepted (the container lays out). The geometry is
  measured below (`uikit/sheet/medium` approximate to a hundredth, `uikit/popover/basic`,
  `uikit/popover/adapted`, `uikit/alert/anchored` exact). `SheetTests`. The alert `severity`
  badge is a Mac Catalyst look (iPhone alerts show none): accepted, not drawn.

## Measured (iOS 26, iPhone SE simulator, 320 × 500 window)

- Medium detent (`uikit/sheet/medium`): the card is 296 tall (0.592 of the window) ending a
  third of a point above the bottom, scaled 0.9713175 about its centre, so it floats 4.59 in
  from the sides and the bottom (310.82 × 287.51 at (4.59, 207.91)); every corner 39, the 20 %
  dim behind; the grabber is 34 × 5, 5.5 below the card's top, black at 25 % over the card.
  UIKit's medium detent sits higher than SwiftUI's floating medium sheet (`ios/sheet/medium`:
  263 tall, 6 in); the fractional geometry is fitted to a hundredth, not derived.
- Popover kept a popover (`uikit/popover/basic`): a card of the preferred content size (240 ×
  120) centred on the source, 13 above it, its frame spanning the 24 × 13 arrow pointing at the
  source's centre (133 tall), 34 pt corners, no dim, a soft shadow fading out over some 60 pt
  (approximated by the layer's shadow), the presenting view's tint dimmed (not modelled: the
  source's blue title stays). Without a delegate (`uikit/popover/adapted`) it is the page sheet.
- Action sheet anchored to a source (`uikit/alert/anchored`): a 240 pt card above the source
  with the arrow under it (outside the card's 189 pt frame), the title 15 pt 24 down in a 71 pt
  header, the actions 48 pt capsules 15.5 in, 8 apart and 14 from the bottom, no cancel action,
  the card (244, 244, 244) over the undimmed screen.

- Both alert styles are one centred card 300 wide (10 in) with 34 pt corners over a 20 % black
  dim; the card is white at 67 % over the dim ((238, 238, 238) on white).
- Alert: the title is 17 pt semibold, 28 in, 21.5 down, 24.5 tall; the message 15 pt, 4.5 below
  it, 23 tall per line; the header ends 10.5 under the message (84 for one line each). Two
  actions share a row 14 in from the card's edges and bottom: 48 pt capsules 8 apart, the
  cancel action on the left filled with the tint (white semibold title), the other in the
  tertiary fill ((223, 223, 224) over the card) with a 17 pt title 11 down in a 26.5 pt line.
  160 tall in all, at y 170.
- Action sheet: the title is 15 pt (secondary), 24 down in a 64 pt header; the actions stack
  full width (272), 48 tall, 8 apart, the cancel action last and filled; 252 tall for a title
  and three actions, at y 124.
- Page sheet: the presented view fills the width from 29.86875 down (a value UIKit holds after
  the presentation settles, in a 500 pt window without a status bar; its origin elsewhere is
  unmeasured) with 38 pt top corners over a 20 % dim; the presenting view stays as it is behind.

Open: the presenting view's dimmed tint under a popover, the medium sheet's drag between
detents, `UIActivityViewController`, `UIDocumentPickerViewController`. (Alert text fields and
the present and dismiss animations landed: below and in the API section.)
- Text fields (`uikit/alert/textfield`, `uikit/alert/textfields`): a block under the header,
  34 per field and 12 below (46 for one, 80 for two), each field in a white box 270 wide 15 in
  with 7 pt corners and a 0.5 pt white ring, the 13 pt field 7.5 in and 7 down, its text line
  20.5 tall (19 for a secure field, whose box is 32 tall); the second row sits 33.5 lower. A
  title alone above fields ends 18 below its line (a 64 pt header) rather than 10.5. Three or
  more actions stack under the fields (the sign-in alert is 332 tall). Pixels 1.8 % and 1.5 %.
