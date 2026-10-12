# UISlider, UISegmentedControl, UIStepper, UIProgressView, UIActivityIndicatorView, UIPageControl

`Packages/UIKitWeb/Sources/UIKitWebCore/Controls/MoreControls.swift` (decision 0014, Phase 4).
Fixture `uikit/controls/more` (each control sized to fit and placed by frame; a disabled
slider), exact in `UIKitGoldenFrameTests` and within 0.7 % in `UIKitPixelTests`, from the
iPhone SE simulator on iOS 26. `UISwitch` and `UITextField` have their own pages.

## API

- `UISlider`: `value`, `minimumValue`, `maximumValue`, `setValue(_:animated:)`, `isContinuous`,
  the track and thumb tint colours, `thumbRect(forBounds:trackRect:value:)`, `trackRect(forBounds:)`;
  a press or drag sets the value and sends `valueChanged`; adjustable in the semantics tree.
- `UISegmentedControl`: `init(items:)` (titles or images), `selectedSegmentIndex`,
  `numberOfSegments`, `insertSegment`, `removeSegment(at:)`, `removeAllSegments`,
  `setTitle(_:forSegmentAt:)`, `titleForSegment(at:)`, `isMomentary`,
  `selectedSegmentTintColor`; a tap selects and sends `valueChanged`.
- `UIStepper`: `value`, `minimumValue`, `maximumValue`, `stepValue`, `wraps`, `autorepeat`
  (accepted), `isContinuous`; a tap on either half steps and sends `valueChanged`.
- `UIProgressView`: `init(progressViewStyle:)`, `progress`, `setProgress(_:animated:)`, the
  tint colours.
- `UIActivityIndicatorView`: `init(style:)` (`medium`, `large`), `startAnimating`,
  `stopAnimating`, `isAnimating`, `hidesWhenStopped`, `color`. Eight fading spokes whose
  pattern turns on the scene's clock while animating (2026-09-18, `ActivityIndicatorTests`).
- `UIPageControl`: `numberOfPages`, `currentPage`, `hidesForSinglePage`, the indicator tint
  colours, `size(forNumberOfPages:)`; a tap on either half moves a page and sends `valueChanged`.

## Measured (iOS 26, iPhone SE simulator)

- Slider: 34 tall; a 6 pt track 14 down with 3 pt corners, black at 10 % (the filled part in the
  tint colour, as wide as the value's fraction of the width); a white 38 × 25 knob 4 down whose
  origin is the fraction of the width less 38, rounded. Disabled: the same geometry with the
  fill and knob at 50 %.
- Segmented control: 32 tall with 16 pt corners; every segment as wide as the widest title
  rounded up plus 19 (55 for "Three" at 35.5, 44 for "One" at 25; `uikit/autolayout/hugging`),
  the ground (115, 115, 123) at 12 %; a white lens 2 in under the
  Every segment is at least 32 wide; the intrinsic content size is the 31 pt alignment rect
  inside the 32 (`ios/representable/measure-controls`, `uikit/autolayout/hugging`). A slider and a progress view hug
  vertically (`defaultHigh`): they keep their heights in taller containers.
  selected segment (51 × 28 for a 55 pt segment); 13 pt titles 16 tall at 8, centred, the selected
  one medium.
- Stepper: 94 × 32 (UIKit hosts a SwiftUI stepper): the capsule (58, 58, 70) at 8.6 %, a 1 pt
  divider (59, 59, 67) at 36 %, black − and +.
- Progress view: 4 tall, the track (120, 120, 125) at 20 %, the fill the tint colour as wide as
  the progress times the width, rounded.
- Activity indicator: 20 × 20 (medium), 37 × 37 (large); animating, the spoke pattern steps one
  spoke every 1/8 s (a revolution per second: approximate, UIKit's rate is not measured; the
  goldens hold the still at phase 0, `uikit/controls/more`).
- Page control: 26 tall, 10 pt dots on an 18 pt pitch starting 14 in (92 wide for four pages);
  the dots are white (the current one opaque, the others at 45 %) over a material backdrop the
  capture leaves transparent, so on a white page they are as invisible here as in UIKit.

## The rest (uk-controls-rest, `uikit/controls/rest` on the iOS 27 simulator, 2026-10-12)

- Slider images: `minimumValueImage` sits at the leading edge and `maximumValueImage` at the
  trailing one, each at its own size centred on the track's middle (y 17 of 34); the track runs
  11 pt in from each image (28 → 249.5 for 17 and 27.5 pt symbols in 288) and the knob travels
  within it (`minimumValueImageRect`, `maximumValueImageRect`, `trackRect` with the insets).
  The images are drawn like a tinted template image. Tier A exact; pixels 1.6 % (iOS 27's lens
  is 37 × 24 at 5 where the iOS 26 goldens held 38 × 25 at 4; the model keeps 26's).
- Segment widths: an image segment is 40 wide with its image centred (symbols at their point
  size, `setImage`, `imageForSegment`); `setWidth(_:forSegmentAt:)` fixes a segment (100, 65,
  65 for "A", "Second", "C"), the automatic ones sharing the widest natural width, and
  `apportionsSegmentWidthsByContent` gives each its own (label + 19, at least 32: 32, 65, 32);
  a frame wider or narrower than the sum scales the automatic segments; `setEnabled(_:forSegmentAt:)`
  dims a segment to half and ignores its taps; taps land by the segment frames.
- Stepper autorepeat: the press steps at once, then — `autorepeat` — after 0.5 s and every
  0.1 s while held, twice as fast after ten repeats (approximate: UIKit's timing is not
  measured); `isContinuous` false sends one `valueChanged` on release; `wraps` as before.
- Page control: a tap on the trailing half goes forward, on the leading half back; with
  `allowsContinuousInteraction` a drag of 10 pt scrubs to the page under the finger.

`ControlsRestTests`. Open: spinning, custom page indicator images, `UIDatePicker`,
`UIPickerView`, `UITextView`, `UISearchBar`, `UIToolbar`.
