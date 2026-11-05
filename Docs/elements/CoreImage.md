# Core Image (pf-core-image, 2026-11-05)

SwiftUIWeb's `WebCoreImage` module gives apps and packages (Kingfisher's image filters first)
Core Image's images, filters and contexts on the web and on Linux. Apps import it as
`CoreImage`, the Shadows module that re-exports it on wasm with CoreGraphics's names; a root
module named `CoreImage` would shadow Apple's, which AppKit imports, in every macOS build.
Where CGImage is CoreGraphics's, on Apple platforms, `WebCoreImage` is empty.

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
- Generators and geometry: `CIConstantColorGenerator`, `CIAffineTransform`, `CICrop`.

`CIImage` also has `applyingFilter(_:parameters:)`, `composited(over:)`, `cropped(to:)`,
`transformed(by:)`, `oriented(_:)` and `applyingGaussianBlur(sigma:)`.

## UIKit

`CIColor(color:)`, `UIColor(ciColor:)`, `CIImage(image:)` and `UIImage(ciImage:)`. A UIImage
made from a CIImage renders it over its extent at once, so its `cgImage` is the recording; an
endless image (a bare colour) gives a clear one-pixel image.

## Open

- Generators that need their own pixels: QR and barcode generators, gradients, checkerboards.
- Reading pixels back (`render(_:toBitmap:...)`), face and feature detection.
- `CIFilterBuiltins` (the typed filter properties) and custom kernels.
