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

Open: text drawing (`NSString.draw(at:withAttributes:)`, `NSAttributedString`), `UIImage.draw`,
gradients (`CGGradient`), `UIGraphicsImageRenderer` and image contexts, blend modes,
`CGPath`/`CGMutablePath` on Apple platforms (there `UIBezierPath.cgPath` is the substrate's
`Path`, not CoreGraphics's), caching of drawn content between frames.
