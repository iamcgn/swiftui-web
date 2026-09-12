# Custom drawing: draw(_:), UIBezierPath, the graphics context

`Packages/UIKitWeb/Sources/UIKitWebCore/Drawing/` (decision 0014, Phase 3): `UIBezierPath.swift`,
`GraphicsContext.swift`, `StringDrawing.swift`, `Gradients.swift`, `ImageRenderer.swift`.
Fixtures `uikit/draw/basic`, `text` and `gradient` (`Fixtures/UIKit/Draw`), compared by
pixels against the simulator (`UIKitPixelTests`); `DrawingTests` holds the mechanics.

## API

- `UIView.draw(_:)`: overridden by a view that draws itself; the runtime calls it every frame
  with a recording graphics context as the current one (`setNeedsDisplay` schedules a frame; the
  drawing is not cached).
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
  `strokeLineSegments`; `clip` (with a rule, to a rect, to rects); transparency layers.
  Accepted without effect: `setBlendMode`, antialiasing switches, `clear`.

## How it works

`UIView.drawContent` (what the built-in views override to paint) runs `draw(bounds)` for any
other view with a recorder pushed as the current context. The recorder keeps CoreGraphics's
state (transform, colours, line style, alpha, shadow) on a save/restore stack and emits display
list commands in absolute coordinates: paths are transformed by the current transform when
painted (stroke widths scale with it), clips become `save` + `clipPath` closed at the matching
`restoreGState`, shadows wrap each fill or stroke in a shadow group. The recorder is appended to
the layer's list after `draw(_:)` returns, so a view that draws nothing costs an empty recorder.

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

Open: blend modes, `CGPath`/`CGMutablePath` on Apple platforms (there `UIBezierPath.cgPath` is
the substrate's `Path`, not CoreGraphics's), tinting and `pngData()` of rendered images, caching
of drawn content between frames.
