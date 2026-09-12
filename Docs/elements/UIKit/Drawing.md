# Custom drawing: draw(_:), UIBezierPath, the graphics context

`Packages/UIKitWeb/Sources/UIKitWebCore/Drawing/` (decision 0014, Phase 3): `UIBezierPath.swift`,
`GraphicsContext.swift`. Fixture `uikit/draw/basic` (`Fixtures/UIKit/Draw`), compared by
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

Open: gradients (`CGGradient`), `UIGraphicsImageRenderer` and image contexts, blend modes,
`CGPath`/`CGMutablePath` on Apple platforms (there `UIBezierPath.cgPath` is the substrate's
`Path`, not CoreGraphics's), caching of drawn content between frames.
