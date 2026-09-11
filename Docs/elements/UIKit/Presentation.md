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
  unless `isModalInPresentation`. Appearance callbacks run for presented controllers. A
  controller that is already presenting refuses a second `present` (UIKit logs "Attempt to
  present ... which is already presenting ..." and does the same); the first stays. The
  presentation container holds its controller weakly and leaves the window if the controller
  is released while presented.

## Measured (iOS 26, iPhone SE simulator, 320 × 500 window)

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

Open: alert text fields, the `severity` badge, the dismiss and present animations (the cards
appear at once), sheet detents and the grabber, `popover` on the iPhone (it becomes a sheet),
`UIActivityViewController`, `UIDocumentPickerViewController`.
- Text fields (`uikit/alert/textfield`, `uikit/alert/textfields`): a block under the header,
  34 per field and 12 below (46 for one, 80 for two), each field in a white box 270 wide 15 in
  with 7 pt corners and a 0.5 pt white ring, the 13 pt field 7.5 in and 7 down, its text line
  20.5 tall (19 for a secure field, whose box is 32 tall); the second row sits 33.5 lower. A
  title alone above fields ends 18 below its line (a 64 pt header) rather than 10.5. Three or
  more actions stack under the fields (the sign-in alert is 332 tall). Pixels 1.8 % and 1.5 %.
