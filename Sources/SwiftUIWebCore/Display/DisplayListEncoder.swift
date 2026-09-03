/// Flat encoding of a display list for a painter that lives across a bridge (JS, C): opcodes and
/// operands in one `[Double]`, strings interned in a side table. Decoders: SwiftUIWebCanvas
/// (`Canvas2DPainter` JS) and tests (`DisplayListDecoder`).
public enum DisplayOp: Double, Sendable {
    case save = 1, restore = 2
    /// clipPath: path, eoFill
    case clipRect = 3, clipRRect = 4, clipPath = 5
    case beginGroup = 6, endGroup = 7
    /// fillPath: path, colour, eoFill. strokePath: path, width, cap, join, miter limit, dash count, dashes, phase, colour
    case fillRect = 8, fillRRect = 9, fillPath = 10, strokePath = 11
    case drawText = 12
    /// file, scale, pixel w/h, rect, tile, insets (top, leading, bottom, trailing), smoothing, hasTint, colour
    case drawImage = 13
    /// a, b, c, d, tx, ty
    case concat = 14
}

/// Path element tags inside an encoded path: tag, then coordinates.
public enum DisplayPathOp: Double, Sendable {
    case move = 0, line = 1, quad = 2, curve = 3, close = 4
}

public struct EncodedDisplayList: Equatable, Sendable {
    public var ops: [Double] = []
    /// Interned strings: text runs and CSS font strings.
    public var strings: [String] = []

    public init() {}
}

public enum DisplayListEncoder {
    /// Encodes `list`. Colours are emitted as r,g,b (0…255) and alpha (0…1).
    public static func encode(_ list: DisplayList, font fontString: (DisplayFont) -> String) -> EncodedDisplayList {
        var out = EncodedDisplayList()
        var stringIndex: [String: Int] = [:]
        func intern(_ s: String) -> Double {
            if let i = stringIndex[s] { return Double(i) }
            let i = out.strings.count
            out.strings.append(s)
            stringIndex[s] = i
            return Double(i)
        }
        func rect(_ r: CGRect) { out.ops += [r.minX, r.minY, r.width, r.height] }
        func color(_ c: RGBA) { out.ops += [(c.red * 255).rounded(), (c.green * 255).rounded(), (c.blue * 255).rounded(), c.alpha] }
        func path(_ p: Path) {
            out.ops.append(Double(p.elements.count))
            for element in p.elements {
                switch element {
                case .move(let to): out.ops += [DisplayPathOp.move.rawValue, to.x, to.y]
                case .line(let to): out.ops += [DisplayPathOp.line.rawValue, to.x, to.y]
                case .quadCurve(let to, let c): out.ops += [DisplayPathOp.quad.rawValue, to.x, to.y, c.x, c.y]
                case .curve(let to, let c1, let c2): out.ops += [DisplayPathOp.curve.rawValue, to.x, to.y, c1.x, c1.y, c2.x, c2.y]
                case .closeSubpath: out.ops.append(DisplayPathOp.close.rawValue)
                }
            }
        }
        for command in list.commands {
            switch command {
            case .save: out.ops.append(DisplayOp.save.rawValue)
            case .restore: out.ops.append(DisplayOp.restore.rawValue)
            case .clipRect(let r): out.ops.append(DisplayOp.clipRect.rawValue); rect(r)
            case .clipRRect(let r, let radius): out.ops.append(DisplayOp.clipRRect.rawValue); rect(r); out.ops.append(radius)
            case .clipPath(let p, let eo): out.ops.append(DisplayOp.clipPath.rawValue); path(p); out.ops.append(eo ? 1 : 0)
            case .beginGroup(let opacity): out.ops += [DisplayOp.beginGroup.rawValue, opacity]
            case .endGroup: out.ops.append(DisplayOp.endGroup.rawValue)
            case .concat(let t): out.ops += [DisplayOp.concat.rawValue, t.a, t.b, t.c, t.d, t.tx, t.ty]
            case .fillRect(let r, let c): out.ops.append(DisplayOp.fillRect.rawValue); rect(r); color(c)
            case .fillRRect(let r, let radius, let c): out.ops.append(DisplayOp.fillRRect.rawValue); rect(r); out.ops.append(radius); color(c)
            case .fillPath(let p, let c, let eo): out.ops.append(DisplayOp.fillPath.rawValue); path(p); color(c); out.ops.append(eo ? 1 : 0)
            case .strokePath(let p, let style, let c):
                out.ops.append(DisplayOp.strokePath.rawValue)
                path(p)
                out.ops += [style.lineWidth, Double(style.lineCap.rawValue), Double(style.lineJoin.rawValue), style.miterLimit, Double(style.dash.count)]
                out.ops += style.dash.map { Double($0) }
                out.ops.append(style.dashPhase)
                color(c)
            case .drawText(let text, let font, let origin, let c):
                out.ops += [DisplayOp.drawText.rawValue, intern(text), intern(fontString(font)), origin.x, origin.y]
                color(c)
            case .drawImage(let draw):
                out.ops += [DisplayOp.drawImage.rawValue, intern(draw.file), draw.scale, draw.pixelSize.width, draw.pixelSize.height]
                rect(draw.rect)
                out.ops += [draw.tiles ? 1 : 0, draw.capInsets.top, draw.capInsets.leading, draw.capInsets.bottom, draw.capInsets.trailing,
                            draw.smoothing ? 1 : 0, draw.tint == nil ? 0 : 1]
                color(draw.tint ?? .clear)
            }
        }
        return out
    }

    /// The CSS `font` shorthand for a display font (browser painters and text engines).
    public static func cssFont(_ font: DisplayFont) -> String {
        let family: String
        switch font.family {
        case "system": family = "-apple-system, BlinkMacSystemFont, system-ui, 'Segoe UI', Roboto, sans-serif"
        case "system-rounded": family = "ui-rounded, -apple-system, system-ui, sans-serif"
        case "system-serif": family = "ui-serif, 'New York', Georgia, serif"
        case "system-monospaced": family = "ui-monospace, 'SF Mono', Menlo, Consolas, monospace"
        default: family = "'\(font.family)', -apple-system, system-ui, sans-serif"
        }
        let size = font.size == font.size.rounded() ? "\(Int(font.size))" : "\(font.size)"
        return "\(font.italic ? "italic " : "")\(font.weight) \(size)px \(family)"
    }
}

/// Decodes the flat encoding back into commands (tests, and a reference for the JS decoder).
public enum DisplayListDecoder {
    public static func decode(_ encoded: EncodedDisplayList) -> [String] {
        var out: [String] = []
        var i = 0
        let ops = encoded.ops
        func next() -> Double { defer { i += 1 }; return ops[i] }
        func rect() -> CGRect { CGRect(x: next(), y: next(), width: next(), height: next()) }
        func color() -> String {
            let r = Int(next()), g = Int(next()), b = Int(next()), a = next()
            return a == 1 ? "rgb(\(r),\(g),\(b))" : "rgba(\(r),\(g),\(b),\(a))"
        }
        func path() -> String {
            let count = Int(next())
            var parts: [String] = []
            for _ in 0..<count {
                switch DisplayPathOp(rawValue: next())! {
                case .move: parts.append("M\(next()),\(next())")
                case .line: parts.append("L\(next()),\(next())")
                case .quad: parts.append("Q\(next()),\(next()) \(next()),\(next())")
                case .curve: parts.append("C\(next()),\(next()) \(next()),\(next()) \(next()),\(next())")
                case .close: parts.append("Z")
                }
            }
            return parts.joined(separator: " ")
        }
        func f(_ r: CGRect) -> String { "\(r.minX),\(r.minY),\(r.width),\(r.height)" }
        while i < ops.count {
            switch DisplayOp(rawValue: next())! {
            case .save: out.append("save")
            case .restore: out.append("restore")
            case .clipRect: out.append("clipRect \(f(rect()))")
            case .clipRRect: out.append("clipRRect \(f(rect())) r\(next())")
            case .clipPath: let p = path(); out.append("clipPath \(p)\(next() == 1 ? " eo" : "")")
            case .beginGroup: out.append("beginGroup \(next())")
            case .endGroup: out.append("endGroup")
            case .concat: out.append("concat \(next()),\(next()),\(next()),\(next()),\(next()),\(next())")
            case .fillRect: out.append("fillRect \(f(rect())) \(color())")
            case .fillRRect: let r = rect(); out.append("fillRRect \(f(r)) r\(next()) \(color())")
            case .fillPath: let p = path(); let c = color(); out.append("fillPath \(p) \(c)\(next() == 1 ? " eo" : "")")
            case .strokePath:
                let p = path()
                let width = next(), cap = Int(next()), join = Int(next()), miter = next()
                let dashes = (0..<Int(next())).map { _ in next() }
                let phase = next()
                var text = "strokePath \(p) w\(width)"
                if cap != 0 || join != 0 || miter != 10 { text += " cap\(cap) join\(join) miter\(miter)" }
                if !dashes.isEmpty { text += " dash\(dashes) phase\(phase)" }
                out.append("\(text) \(color())")
            case .drawText:
                let text = encoded.strings[Int(next())], font = encoded.strings[Int(next())]
                out.append("drawText '\(text)' [\(font)] \(next()),\(next()) \(color())")
            case .drawImage:
                let file = encoded.strings[Int(next())]
                let scale = next(), pw = next(), ph = next()
                let r = rect()
                let tile = next() == 1
                let insets = "\(next()),\(next()),\(next()),\(next())"
                let smoothing = next() == 1, hasTint = next() == 1
                let tint = color()
                out.append("drawImage \(file) @\(scale)x \(Int(pw))x\(Int(ph)) \(f(r))\(tile ? " tile" : "") insets \(insets)\(smoothing ? "" : " nearest")\(hasTint ? " tint " + tint : "")")
            }
        }
        return out
    }
}
