// Symbol images drawn from the substrate's glyph table (Lucide outlines standing in for SF
// Symbols, as `Image(systemName:)` does in SwiftUIWeb): the 24-unit outline scaled into the
// rect, stroked 2 units wide with round caps.

enum SymbolPainter {
    @MainActor
    static func paint(name: String, in rect: CGRect, color: RGBA, weight: Int, into list: inout DisplayList) {
        guard let (glyph, outline) = SystemSymbolGlyphs.glyph(named: name) else { return }
        let scale = min(rect.width, rect.height) / 24
        let origin = CGPoint(x: rect.midX - 12 * scale, y: rect.midY - 12 * scale)
        var path = Path()
        var first = Path()
        var i = 0
        var count = 0
        func point(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: origin.x + x * scale, y: origin.y + y * scale) }
        while i < outline.ops.count {
            let tag = Int(outline.ops[i]); i += 1
            var target: Path
            let intoFirst = count < outline.firstElement
            target = intoFirst ? first : path
            switch tag {
            case 0: target.move(to: point(outline.ops[i], outline.ops[i + 1])); i += 2; count += 3
            case 1: target.addLine(to: point(outline.ops[i], outline.ops[i + 1])); i += 2; count += 3
            case 2:
                target.addCurve(to: point(outline.ops[i + 4], outline.ops[i + 5]), control1: point(outline.ops[i], outline.ops[i + 1]), control2: point(outline.ops[i + 2], outline.ops[i + 3]))
                i += 6; count += 7
            case 3: target.closeSubpath(); count += 1
            default: break
            }
            if intoFirst { first = target } else { path = target }
        }
        let stroke = StrokeStyle(lineWidth: (weight >= 600 ? 2.5 : 2) * scale, lineCap: .round, lineJoin: .round)
        switch glyph.mode {
        case 1:
            list.append(.fillPath(first, color))
            list.append(.strokePath(first, style: stroke, color))
            list.append(.fillPath(path, color))
            list.append(.strokePath(path, style: stroke, color))
        case 2:
            list.append(.fillPath(first, color))
            list.append(.strokePath(first, style: stroke, color))
            list.append(.strokePath(path, style: stroke, RGBA.white))
        default:
            list.append(.strokePath(first, style: stroke, color))
            list.append(.strokePath(path, style: stroke, color))
        }
    }
}
