# Custom drawing: draw(_:), UIBezierPath, the graphics context

`Packages/UIKitWeb/Sources/UIKitWebCore/Drawing/` (decision 0014, Phase 3): `UIBezierPath.swift`,
`GraphicsContext.swift`, `StringDrawing.swift`, `Gradients.swift`, `ImageRenderer.swift`.
Fixtures `uikit/draw/basic`, `text` and `gradient` (`Fixtures/UIKit/Draw`), compared by
pixels against the simulator (`UIKitPixelTests`); `DrawingTests` holds the mechanics.

## API

- `UIView.draw(_:)`: overridden by a view that draws itself; the runtime calls it with a
  recording graphics context as the current one and keeps the recording until
  `setNeedsDisplay`, a size change or another appearance (2026-10-09; before, every frame).
- `UIGraphicsGetCurrentContext()`, `UIGraphicsPushContext`, `UIGraphicsPopContext`; `UIRectFill`,
  `UIRectFrame`, `UIRectClip`; `UIColor.setFill()`, `setStroke()`, `set()`.
- `UIBezierPath`: `init()`, `init(rect:)`, `init(ovalIn:)`, `init(roundedRect:cornerRadius:)`,
  `init(roundedRect:byRoundingCorners:cornerRadii:)`, `init(arcCenter:radius:startAngle:endAngle:clockwise:)`,
  `init(cgPath:)`; `move`, `addLine`, `addCurve`, `addQuadCurve`, `addArc`, `close`,
  `removeAllPoints`, `append`, `apply`, `cgPath` (the substrate's `Path`), `bounds`,
  `currentPoint`, `isEmpty`, `lineWidth`, `lineCapStyle`, `lineJoinStyle`, `miterLimit`,
  `setLineDash`, `usesEvenOddFillRule`; `fill()`, `stroke()`, the blend-mode-and-alpha forms,
  `addClip()`. `contains(_:)` tests the bounds only.
- The recording context (`UIGraphicsRecordingContext`; on wasm this is what `CGContext` names, on
  Apple platforms CoreGraphics keeps that name and `UIGraphicsGetCurrentContext()` returns this
  class): `saveGState`/`restoreGState`, `translateBy`, `scaleBy`, `rotate(by:)`, `concatenate`,
  `ctm`; `setFillColor`/`setStrokeColor` (a `CGColor`, components, or grey), `setLineWidth`,
  `setLineCap`, `setLineJoin`, `setMiterLimit`, `setLineDash`, `setAlpha`, `setShadow`;
  `beginPath`, `move`, `addLine(s)`, `addCurve`, `addQuadCurve`, `addRect(s)`, `addEllipse`,
  `addArc` (both forms), `addPath`, `closePath`; `fillPath` (with a fill rule), `strokePath`,
  `drawPath(using:)`, `fill`, `stroke` (with a width), `fillEllipse`, `strokeEllipse`,
  `strokeLineSegments`; `clip` (with a rule, to a rect, to rects); transparency layers;
  `setBlendMode` and `clear` (see "The rest"). Accepted without effect: the antialiasing
  switches (the painters always antialias).

## How it works

`UIView.drawContent` (what the built-in views override to paint) replays the view's recording
for any other view, running `draw(bounds)` with a recorder pushed as the current context when
there is none (`UIView.drawingCache`: the commands in the view's coordinates, the scale and
appearance they were made for, whether they blend). The recorder keeps CoreGraphics's state
(transform, colours, line style, alpha, shadow, blend mode) on a save/restore stack and emits
display list commands: paths are transformed by the current transform when painted (stroke
widths scale with it), clips become `save` + `clipPath` closed at the matching
`restoreGState`, shadows wrap each fill or stroke in a shadow group. At paint time the
commands move by the layer's absolute origin (a top-level `concat`, which string and image
drawing record under, folds the move in), so the list is the one an absolute recording gives.
The view's traits are current while it draws (`UIColor.label.setFill()` resolves them).
`setNeedsDisplay` (the view's, not the layer's, which only asks for a frame) drops the
recording; a view that draws nothing costs an empty recorder once.

## Measured

`uikit/draw/basic` (shapes through UIBezierPath: a rounded rect, a stroked circle, a triangle, a
dashed line, an even-odd ring; the context: a rotated square, an ellipse clip, a shadow, a
stroked rect, a round-capped line) renders within 0.16 % of the simulator's pixels through the
CoreGraphics painter: the transforms, dashes, even-odd fills, clips and shadow match. UIKit's
`UIBezierPath.addArc(clockwise:)` runs clockwise on screen (y down), which is the substrate's
counter-clockwise flag.

## Strings and images (2026-09-11, `uikit/draw/text`)

`Drawing/StringDrawing.swift`. `draw(at:withAttributes:)` (unwrapped), `draw(in:withAttributes:)`
(wrapped to the rect's width, the lines that fit its height), `size(withAttributes:)` and
`boundingRect(with:options:attributes:context:)` on strings; `NSAttributedString.draw(at:)`,
`draw(in:)`, `size()` and `boundingRect` reading the attributes at the string's start
(`.font`, `.foregroundColor`, `.paragraphStyle`; the class is Foundation's on Apple platforms
and a one-dictionary stand-in on wasm); `NSParagraphStyle` / `NSMutableParagraphStyle` with
`alignment` and `lineBreakMode`; `UIImage.draw(at:)` and `draw(in:)` for symbols (the symbol
painter, tinted) and catalog images (an image draw). Everything is recorded between a concat of
the context's transform and a restore, inside the context's shadow group, with its alpha
(images under 1 in an opacity group). Defaults without attributes: the 12 pt system font in
black. Measured: a string's first baseline sits at the font's ascender below the point, lines
one line pitch apart; a right-aligned or centred paragraph places each line by its ink width in
the rect. The fixture (a semibold title with a line under its measured width, right-aligned and
centred lines, an attributed string, text wrapped to 150 pt, a rotated string, a 40 pt tinted
star) renders within 2.6 % of the simulator's pixels, the star's glyph shape from the symbol
table making most of the difference; the CoreText engine wraps the fox sentence on the same
words. Open: per-range attributes, underline and strikethrough, `NSMutableAttributedString`,
`UIImage.draw` with blend modes.

## Gradients and image contexts (2026-09-12, `uikit/draw/gradient`)

`Drawing/Gradients.swift`, `Drawing/ImageRenderer.swift`.

- `CGGradient(colorsSpace:colors:locations:)` (a `CFArray` of `CGColor`s, the locations as an
  array or nil for evenly spaced) and `init(colorSpace:colorComponents:locations:count:)`. The
  class is `UIGraphicsGradient` in `UIKitWebCore`; the thin `UIKit` module declares the
  `CGGradient` typealias beside its re-export of CoreGraphics, and Swift's shadowing rule (a
  module's declarations hide same-named ones in the modules it re-exports) makes a file that
  imports UIKit see only it, so `locations: nil` resolves (a real `CGGradient` cannot be read
  back; `CGGradientShadowTests`). A file that also imports `WebGraphics`, which re-exports
  CoreGraphics, sees both classes and must pass the locations as an array (`[0, 1]` picks the
  array overload over the pointer one; `nil` is ambiguous). On wasm the module also provides
  `CGColorSpace` (`CGColorSpaceCreateDeviceRGB()`, `CGColorSpaceCreateDeviceGray()`), `CFArray`
  (`[Any]`) and `CGGradientDrawingOptions`.
- `drawLinearGradient(_:start:end:options:)`, `drawRadialGradient(_:startCenter:startRadius:endCenter:endRadius:options:)`:
  each becomes one `fillGradient` of the region CoreGraphics paints, inside the current clip:
  the band between the perpendiculars through the two points (extended past either end by the
  options), or the end circle minus the start circle (even-odd; the options extend to the plane
  or fill the start circle). Points go through the current transform, radii by its magnitude.
  The stops are the colours as given: CoreGraphics blends them linearly in the colour space,
  as Canvas2D and the CoreGraphics painter do, so nothing is expanded in Oklab (SwiftUI's
  gradients are). A radial gradient whose circles have different centres is the display
  list's `focalRadial` kind (added for this; Canvas2D's `createRadialGradient` and
  CoreGraphics's `drawRadialGradient` take both circles). The context's alpha multiplies the
  stops; the shadow wraps the fill.
- `UIGraphicsImageRenderer(size:)` / `(bounds:)` / with a `UIGraphicsImageRendererFormat`
  (`scale`, `opaque`, `preferredRange`; `.default()` is the screen's scale): `image(actions:)`
  runs the block with a fresh recording context as the current one (the
  `UIGraphicsImageRendererContext` offers `cgContext`, `format`, `fill`, `stroke`, `clip(to:)`,
  `currentImage`) and returns a `UIImage` whose `drawing` (`UIImageDrawing`: commands, size,
  scale) is the recording. `UIGraphicsBeginImageContext(WithOptions)`,
  `UIGraphicsGetImageFromCurrentImageContext()` and `UIGraphicsEndImageContext()` do the same
  through a context stack. The image is a vector recording, not a bitmap: `draw(at:)`,
  `draw(in:)` and `UIImageView` replay it between a save, a concat scaling the recording into
  the rectangle, and a restore, so it stays sharp at any size; the rendering mode and tint
  do not apply to it (open), nor does `Image(uiImage:)` carry it into SwiftUI yet.

Measured: `uikit/draw/gradient` (a linear gradient clipped to a rect, a radial one with offset
centres in a clipped circle, a rendered badge drawn at its size and scaled) within 0.09 % of the
simulator's pixels. The radial highlight sits where the start centre is, as the simulator draws it.

Open: tinting of rendered images (`pngData()` works, below).

`UIImage.pngData()` (2026-09-18): a recorded drawing rasterised by the host's `ImageRasterizer`
(`UIKitScene.imageRasterizer`: the canvas host paints it into a canvas of its own and reads a
PNG data URL; the native host paints it with CoreGraphics); nil headless and for catalog
images and symbols. `jpegData` returns the same PNG.

## The rest (2026-10-09, `uikit/draw/rest`)

`Drawing/GraphicsContext.swift`, `StringDrawing.swift`, `CGPathBridge.swift`; the fixture
renders within 0.96 % of the simulator's pixels, the blend modes and `clear` exact.

- Blend modes: `setBlendMode` (the state, until the state is restored), `UIBezierPath.fill(with:alpha:)`
  / `stroke(with:alpha:)`, `UIImage.draw(at:blendMode:alpha:)` / `draw(in:blendMode:alpha:)`,
  `UIGraphicsImageRendererContext.fill(_:blendMode:)` / `stroke(_:blendMode:)`,
  `UIRectFillUsingBlendMode` / `UIRectFrameUsingBlendMode`. Every painted operation with a mode
  goes in a `beginBlend` group over its bounds (the shadow group inside), and a drawing that
  blends or clears is painted inside a group of the view's own, opened before the view's
  background: the modes composite against the background and the earlier drawing, as
  CoreGraphics composites in the layer's backing store, not against what lies beneath the view
  (a red circle multiplied over the view's half-transparent yellow ground is (255, 50, 30) on
  the simulator and here). CoreGraphics's `.clear` is the display list's `destinationOut`;
  `.copy`, `.sourceIn`, `.sourceOut`, `.destinationIn`, `.destinationAtop` and `.xor` composite
  normally (the display list has no group for them), and `.plusDarker` only natively (Canvas2D
  has no plus-darker operation: the browser composites it normally). `UIRectFill` and `UIRectFrame` composite
  normally whatever the context's mode, as UIKit's do (the simulator's orange rectangle under
  `setBlendMode(.multiply)` is the plain orange).
- `clear(_:)`: a `destinationOut` fill of the rectangle inside the view's group, so the view's
  background and drawing go and what lies beneath the view shows (the grey band behind the
  fixture's yellow view).
- Attributed strings draw every range in its own font and colour (the paragraph style read at
  the start), with `.underlineStyle` and `.strikethroughStyle` (any non-zero value; the
  `NSUnderlineStyle` option set is declared here, Foundation keeps it in UIKit and AppKit) in
  `.underlineColor` / `.strikethroughColor` or the text's colour; `NSMutableAttributedString`'s
  `append`, `addAttributes`, `setAttributes`, `removeAttribute`, `replaceCharacters`. Measured:
  UIKit's string drawing does not snap the lines to pixels (they antialias at fractional
  positions); the underline is at least a point thick (1 pt at 15 and 17 pt, the regular face's
  CoreText thickness at 24 pt bold: 2.23) with its top a whole number of points below the
  baseline (the table's centre less half the thickness, rounded: 2 pt at 15 and 17; 24 pt bold
  measures 2.58 where the regular table says 2.17, a half-point residue left open); the
  strikethrough centres on half the x-height, its thickness the table's. Unbounded entries per
  run join the recorded metrics (the recorded engine keys same-font runs merged).
- `CGPath` / `CGMutablePath`: on Apple platforms CoreGraphics's, converted through
  `applyWithBlock` for `UIBezierPath(cgPath:)`, `UIBezierPath.append(_:)`, the context's
  `addPath(_:)` and `CAShapeLayer.setPath(_:)` (`UIBezierPath.cgPath` stays the substrate's
  `Path`); on wasm the module's own classes over a `Path` (`init(rect:transform:)`,
  `init(ellipseIn:)`, `init(roundedRect:…)`, `move`, `addLine(s)`, `addCurve`, `addQuadCurve`,
  `addRect(s)`, `addEllipse`, `addRoundedRect`, both `addArc`s, `addPath`, `closeSubpath`,
  `boundingBox`, `currentPoint`, `contains`, copies). `clockwise` on a CGPath or CGContext arc
  is CoreGraphics's (y up) sense, so in the view's flipped space `false` runs through
  increasing angles, clockwise on screen — the opposite of `UIBezierPath.addArc`'s flag, which
  is the screen's (measured: a `clockwise: false` arc from π to 0 bulges downward). A
  pentagram (even-odd), an arc path filled and stroked, a rotated box with an ellipse cut out
  match the simulator.

## Images (2026-10-09, `uikit/imageview/modes`, `uikit/imageview/tints`)

`Controls/UIImageView.swift`. `UIImage(data:scale:)` reads the PNG or JPEG header for the
pixel size (a 40 × 40 PNG is 40 points at scale 1) and keeps the bytes; the painters load it as
a `data:` URL (the canvas host's image loader takes one, the native painter decodes the
base64 payload with ImageIO). `pngData()` returns those bytes for a PNG-made image (a
recorded drawing is still rasterised by the host), `jpegData` the bytes of a JPEG-made one.
`UIImage.animatedImage(with:duration:)` holds its frames; an image view given one plays it
at once, and `animationImages` / `animationDuration` / `animationRepeatCount` /
`startAnimating` / `stopAnimating` / `isAnimating` cycle frames on the scene's clock (a 30th
of a second per frame without a duration; the view shows `image` again when the repeats are
done; `highlightedAnimationImages` while highlighted).

Measured on the simulator: every content mode of a clipped 100 × 70 view holding the 80 × 60
photo and an unclipped aspect-fill view drawing past its frame (`modes`, 0.00 % off); the
template icon in the view's tint and as original, a plain image as a template in red and
`withTintColor(.systemGreen)`, a bold 32 pt symbol in orange, a 4 × 4 checker from PNG data
scaled to 48 with the simulator's interpolation, the badge through `pngData()` and back, a
view sized to its image (`tints`, 0.72 %). The real-UIKit fixture kit loads catalog images
from disk (`UIKitFixtureImage.named`), since the SwiftPM harness has no compiled catalog.

Open: `UIImage(contentsOfFile:)`, image orientation, `resizableImage` cap insets on image
views (the drawing side has them), `preferredSymbolConfiguration` on the view, HEIC and other
formats (the header parser knows PNG and JPEG).

