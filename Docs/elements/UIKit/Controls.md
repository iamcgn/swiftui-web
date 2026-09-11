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
  `stopAnimating`, `isAnimating`, `hidesWhenStopped`, `color`. A still of eight fading spokes;
  it does not spin yet.
- `UIPageControl`: `numberOfPages`, `currentPage`, `hidesForSinglePage`, the indicator tint
  colours, `size(forNumberOfPages:)`; a tap on either half moves a page and sends `valueChanged`.

## Measured (iOS 26, iPhone SE simulator)

- Slider: 34 tall; a 6 pt track 14 down with 3 pt corners, black at 10 % (the filled part in the
  tint colour, as wide as the value's fraction of the width); a white 38 × 25 knob 4 down whose
  origin is the fraction of the width less 38, rounded. Disabled: the same geometry with the
  fill and knob at 50 %.
- Segmented control: 32 tall with 16 pt corners; every segment as wide as the widest title plus
  20 (55 for "Three" at 35.5), the ground (115, 115, 123) at 12 %; a white lens 2 in under the
  selected segment (51 × 28 for a 55 pt segment); 13 pt titles 16 tall at 8, centred, the selected
  one medium.
- Stepper: 94 × 32 (UIKit hosts a SwiftUI stepper): the capsule (58, 58, 70) at 8.6 %, a 1 pt
  divider (59, 59, 67) at 36 %, black − and +.
- Progress view: 4 tall, the track (120, 120, 125) at 20 %, the fill the tint colour as wide as
  the progress times the width, rounded.
- Activity indicator: 20 × 20 (medium), 37 × 37 (large).
- Page control: 26 tall, 10 pt dots on an 18 pt pitch starting 14 in (92 wide for four pages);
  the dots are white (the current one opaque, the others at 45 %) over a material backdrop the
  capture leaves transparent, so on a white page they are as invisible here as in UIKit.

Open: spinning, the slider's minimum and maximum images, segment images and per-segment widths,
`UIDatePicker`, `UIPickerView`, `UITextView`, `UISearchBar`, `UIToolbar`.
