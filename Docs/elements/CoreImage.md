# Core Image (pf-core-image, 2026-11-05)

SwiftUIWeb's `WebCoreImage` module (in Packages/WebGraphics) gives apps and packages (Kingfisher's
image filters first) Core Image's images, filters and contexts on the web and on Linux. Apps import
it as `CoreImage`, the Shadows module that re-exports it on wasm with CoreGraphics's names; a root
module named `CoreImage` would shadow Apple's, which AppKit imports, in every macOS build.
Where CGImage is CoreGraphics's, on Apple platforms, `WebCoreImage` is empty.

UIKit re-exports it too, as Apple's does (UIKit's headers import Core Image): a file with only
`import UIKit` names `CIImage` and `CIFilter`, as Nuke's processors do. UIKit's side of the bridge
lives in UIKitWeb's CoreImageBridges.swift: `CIColor(color:)`, `UIColor(ciColor:)`,
`CIImage(image:)`, `UIImage(ciImage:)` and `UIImage.ciImage`, which is the recipe an image was
made from and nil for an image made any other way.

## How it draws

A `CIImage` is a recipe, as on Apple platforms: a source (a CGImage, or an endless plane of one
colour) and the steps over it, in Core Image's space (pixels, origin at the bottom left). A
`CIContext` does not compute pixels. `createCGImage(_:from:)` writes the recipe as display-list
commands into a CGImage recording the size of the rectangle, flipped to a top-left origin:

- a colour matrix filter becomes a `beginFilter(.colorMatrix)` group;
- a blur becomes a `beginFilter(.blur)` group whose extent grows by three sigma;
- a composite draws the background, then the image, in a blend group for a blend mode;
- a transform is a `concat`, a crop a clip.

The painters run those filters when the app shows the image, so a filtered image costs no wasm
pixel work. Like every recorded CGImage here, its `dataProvider` is nil.

## Filters

`CIFilter(name:)` knows these, with Apple's input keys and defaults; any other name gives nil.

- Colour: `CIColorControls` (saturation, then brightness, then contrast), `CIExposureAdjust`,
  `CIColorMatrix`, `CIColorInvert`, `CISepiaTone`, `CIPhotoEffectMono`, `CIPhotoEffectNoir`,
  `CIPhotoEffectTonal`.
- Blur: `CIGaussianBlur`.
- Composites: `CISourceOverCompositing`, `CIMultiplyCompositing`, `CISourceAtopCompositing`
  and the blend modes (`CIMultiplyBlendMode`, `CIScreenBlendMode`, `CIOverlayBlendMode` and
  the rest that the display list has).
- Generators and geometry: `CIConstantColorGenerator`, `CIQRCodeGenerator`, `CIAffineTransform`, `CICrop`.

`CIImage` also has `applyingFilter(_:parameters:)`, `composited(over:)`, `cropped(to:)`,
`transformed(by:)`, `oriented(_:)` and `applyingGaussianBlur(sigma:)`.

## QR codes

`CIQRCodeGenerator` encodes `inputMessage` (Data) at `inputCorrectionLevel` "L", "M" (the
default), "Q" or "H": the smallest version that holds it, in numeric, alphanumeric or byte mode,
with the mask of lowest penalty, drawn one pixel a module, black on white, with a one-module
margin (QRCode.swift, written from ISO/IEC 18004's description of the format).

`CIDetector(ofType: CIDetectorTypeQRCode, ...)` reads a code back (QRDetector.swift): the grey
levels become dark and light (one threshold for the picture, then a local one), the finder
patterns are found by their 1:1:3:1:1 runs, the bottom-right alignment pattern near where they
put it, and the modules are sampled through the perspective those points give; Reed-Solomon
corrects damaged codewords. A `CIQRCodeFeature` has the code's corners and bounds in the
image's coordinates, its `messageString` and a
`CIQRCodeDescriptor` with its data codewords, version, mask and level. The message is read in
the character set each ECI designator names (Latin-1, ISO 8859-15, Windows-1252, UTF-8, UTF-16
and ASCII); bytes with no designator, or one of another set, read as UTF-8, or as Latin-1 when
they are not UTF-8. The detector reads images
whose pixels are at hand: CGImages made from pixels (camera frames, generated codes), cropped,
transformed or composited over one another or a colour. An image of a file's bytes has its
pixels only in the browser, so nothing is found in one, and only the first code is reported.
Face, rectangle and text detectors are nil.

## UIKit

`CIColor(color:)`, `UIColor(ciColor:)`, `CIImage(image:)` and `UIImage(ciImage:)`. A UIImage
made from a CIImage renders it over its extent at once, so its `cgImage` is the recording; an
endless image (a bare colour) gives a clear one-pixel image.

## Open

- Generators that need their own pixels: barcode generators other than QR, gradients, checkerboards.
- Reading pixels back (`render(_:toBitmap:...)`); QR codes in images of files; face, rectangle
  and text detection.
- QR messages in Shift JIS (ECI 20 and Kanji mode) and the ECI sets not listed above are not
  turned into their characters.
- `CIFilterBuiltins` (the typed filter properties) and custom kernels.
