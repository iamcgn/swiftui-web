// Painting an SF Symbol stand-in glyph (`SystemSymbolGlyphs`) into a rectangle, shared by the
// image node and text with inline images (`Text(Image(systemName:))`).

package enum _SymbolPainter {
    /// Draws `symbol` fitted into `bounds` (absolute coordinates) in `color`, stroked at a width
    /// that follows the font weight.
    package static func paint(_ symbol: (glyph: SymbolGlyph, outline: SymbolGlyphOutline), in bounds: CGRect, weight: Int, color: RGBA, gradient: DisplayGradient? = nil, into list: inout DisplayList) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let (x0, y0, x1, y1) = symbol.outline.bounds
        let outlineWidth = CGFloat(x1 - x0), outlineHeight = CGFloat(y1 - y0)
        guard outlineWidth > 0, outlineHeight > 0 else { return }
        let scale = min(bounds.width / outlineWidth, bounds.height / outlineHeight)
        let origin = CGPoint(x: bounds.midX - (CGFloat(x0) + outlineWidth / 2) * scale, y: bounds.midY - (CGFloat(y0) + outlineHeight / 2) * scale)
        let ops = symbol.outline.ops
        func path(_ range: Range<Int>) -> Path {
            var path = Path()
            var i = range.lowerBound
            func point() -> CGPoint {
                defer { i += 2 }
                return CGPoint(x: origin.x + CGFloat(ops[i]) * scale, y: origin.y + CGFloat(ops[i + 1]) * scale)
            }
            while i < range.upperBound {
                let op = ops[i]; i += 1
                switch op {
                case 0: path.move(to: point())
                case 1: path.addLine(to: point())
                case 2: let c1 = point(), c2 = point(), to = point(); path.addCurve(to: to, control1: c1, control2: c2)
                default: path.closeSubpath()
                }
            }
            return path
        }
        let weightFactor: CGFloat = weight >= 700 ? 1.2 : weight >= 600 ? 1.0 : weight < 400 ? 0.6 : 0.8
        let style = StrokeStyle(lineWidth: 2 * scale * weightFactor, lineCap: .round, lineJoin: .round)
        let knockout = RGBA(red: 1, green: 1, blue: 1, alpha: 1)
        // A foreground gradient spans the symbol's frame (as a text's spans its frame).
        func fill(_ path: Path) -> DisplayCommand { gradient.map { .fillGradient(path, $0) } ?? .fillPath(path, color, eoFill: false) }
        func stroke(_ path: Path) -> DisplayCommand { gradient.map { .strokeGradient(path, style: style, $0) } ?? .strokePath(path, style: style, color) }
        switch symbol.glyph.mode {
        case 1:
            let whole = path(0..<ops.count)
            list.append(fill(whole))
            list.append(stroke(whole))
        case 2:
            let first = path(0..<min(symbol.outline.firstElement, ops.count))
            list.append(fill(first))
            list.append(stroke(first))
            if symbol.outline.firstElement < ops.count {
                list.append(.strokePath(path(symbol.outline.firstElement..<ops.count), style: style, knockout))
            }
        default:
            list.append(stroke(path(0..<ops.count)))
        }
    }
}
