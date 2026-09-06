// Painting the layer tree into the display list (decision 0014: UIKit views are painted
// leaves of the same display list SwiftUI views use). A layer paints its background, border and
// shadow, its view's content, then its sublayers in order; opacity and shadows are groups;
// `masksToBounds` clips. Frame edges are rounded to the pixel grid like SwiftUIWeb's.

extension CALayer {
    /// Paints this layer and its sublayers. `context.origin` is the absolute position of the
    /// superlayer's bounds origin; the layer's own transform, if any, is concatenated.
    func paint(into list: inout DisplayList, context: PaintContext, style: UIUserInterfaceStyle) {
        guard !isHidden, opacity > 0 else { return }
        let effective = view?.effectiveStyle(style) ?? style
        // The layer's origin in the superlayer's space, without the transform.
        let origin = CGPoint(x: position.x - bounds.width * anchorPoint.x, y: position.y - bounds.height * anchorPoint.y)
        var child = context.child(at: CGRect(origin: origin, size: bounds.size))
        let transformed = !transform.isIdentity
        if transformed {
            list.append(.save)
            let anchor = CGPoint(x: context.origin.x + position.x, y: context.origin.y + position.y)
            let t = CGAffineTransform(translationX: -anchor.x, y: -anchor.y)
                .concatenating(transform.affine)
                .concatenating(CGAffineTransform(translationX: anchor.x, y: anchor.y))
            list.append(.concat(t))
        }
        let rect = child.absoluteRect(CGRect(origin: .zero, size: bounds.size))
        var groups = 0
        if opacity < 1 {
            list.append(.beginGroup(opacity: Double(opacity)))
            groups += 1
        }
        if shadowOpacity > 0, let shadowColor, let color = RGBA(cgColor: shadowColor) {
            list.append(.beginShadow(color.multiplyingAlpha(by: Double(shadowOpacity)), radius: shadowRadius, offset: CGSize(width: shadowOffset.width, height: shadowOffset.height)))
            groups += 1
        }
        let radius = cornerRadius > 0 && maskedCorners == .all ? min(cornerRadius, min(rect.width, rect.height) / 2) : 0
        if let backgroundColor, let color = RGBA(cgColor: backgroundColor), color.alpha > 0 {
            if cornerRadius > 0, maskedCorners != .all {
                list.append(.fillPath(Self.cornerPath(rect, radius: cornerRadius, corners: maskedCorners, curve: cornerCurve), color))
            } else if radius > 0 {
                if cornerCurve == .continuous {
                    list.append(.fillPath(Path(roundedRect: rect, cornerRadius: radius, style: .continuous), color))
                } else {
                    list.append(.fillRRect(rect, cornerRadius: radius, color))
                }
            } else {
                list.append(.fillRect(rect, color))
            }
        }
        if masksToBounds {
            list.append(.save)
            if cornerRadius > 0, maskedCorners != .all {
                list.append(.clipPath(Self.cornerPath(rect, radius: cornerRadius, corners: maskedCorners, curve: cornerCurve)))
            } else if radius > 0 {
                list.append(cornerCurve == .continuous ? .clipPath(Path(roundedRect: rect, cornerRadius: radius, style: .continuous)) : .clipRRect(rect, cornerRadius: radius))
            } else {
                list.append(.clipRect(rect))
            }
        }
        // The content is scrolled by the bounds origin.
        child.origin = CGPoint(x: child.origin.x - bounds.minX, y: child.origin.y - bounds.minY)
        if let shape = self as? CAShapeLayer {
            shape.paintShape(into: &list, context: child)
        }
        view?.drawContent(into: &list, context: child, style: effective)
        for layer in (sublayers ?? []).sorted(by: { $0.zPosition < $1.zPosition }) {
            layer.paint(into: &list, context: child, style: effective)
        }
        if masksToBounds { list.append(.restore) }
        if borderWidth > 0, let borderColor, let color = RGBA(cgColor: borderColor), color.alpha > 0 {
            // The border is drawn inside the bounds, centred on a line half the width in.
            let inset = rect.insetBy(dx: borderWidth / 2, dy: borderWidth / 2)
            let path: Path
            if cornerRadius > 0, maskedCorners != .all {
                path = Self.cornerPath(inset, radius: max(0, cornerRadius - borderWidth / 2), corners: maskedCorners, curve: cornerCurve)
            } else if radius > 0 {
                path = Path(roundedRect: inset, cornerRadius: max(0, radius - borderWidth / 2), style: cornerCurve == .continuous ? .continuous : .circular)
            } else {
                path = Path(inset)
            }
            list.append(.strokePath(path, style: StrokeStyle(lineWidth: borderWidth), color))
        }
        for _ in 0..<groups { list.append(.endGroup) }
        if transformed { list.append(.restore) }
    }

    /// A rectangle with only some corners rounded.
    static func cornerPath(_ rect: CGRect, radius: CGFloat, corners: CACornerMask, curve: CALayerCornerCurve) -> Path {
        let r = min(radius, min(rect.width, rect.height) / 2)
        let radii = RectangleCornerRadii(
            topLeading: corners.contains(.layerMinXMinYCorner) ? r : 0,
            bottomLeading: corners.contains(.layerMinXMaxYCorner) ? r : 0,
            bottomTrailing: corners.contains(.layerMaxXMaxYCorner) ? r : 0,
            topTrailing: corners.contains(.layerMaxXMinYCorner) ? r : 0)
        return Path(roundedRect: rect, cornerRadii: radii, style: curve == .continuous ? .continuous : .circular)
    }
}

extension CAShapeLayer {
    /// Fills and strokes the path in the layer's coordinates (absolute through the context).
    func paintShape(into list: inout DisplayList, context: PaintContext) {
        guard var path else { return }
        if strokeStart > 0 || strokeEnd < 1 { path = path.trimmedPath(from: strokeStart, to: strokeEnd) }
        let shift = CGAffineTransform(translationX: context.origin.x, y: context.origin.y)
        let absolute = path.applying(shift)
        if let fillColor, let color = RGBA(cgColor: fillColor), color.alpha > 0 {
            list.append(.fillPath(absolute, color, eoFill: fillRule == .evenOdd))
        }
        if let strokeColor, let color = RGBA(cgColor: strokeColor), color.alpha > 0, lineWidth > 0 {
            list.append(.strokePath(absolute, style: StrokeStyle(lineWidth: lineWidth, lineCap: lineCap, lineJoin: lineJoin, miterLimit: miterLimit,
                                                                 dash: lineDashPattern ?? [], dashPhase: lineDashPhase), color))
        }
    }
}
