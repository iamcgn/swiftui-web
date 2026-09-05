// Nodes for Image and the aspect-ratio modifier (Docs/elements/Image.md).

/// A named image resolved against the runtime's catalog. Rigid at its point size unless
/// resizable; paints one `drawImage` with the variant for the paint scale.
@MainActor
package final class ImageNode: LeafNode<Image> {
    package private(set) var resource: ImageResource?

    override package init(_ context: _NodeContext<Image>) {
        super.init(context)
        resolve()
    }

    override package func update(view: Image, environment: EnvironmentValues, force: Bool) {
        super.update(view: view, environment: environment, force: force)
        resolve()
    }

    /// A system symbol's glyph (an open icon standing in for the SF Symbol) and its measured
    /// layout size at the environment's font, weight and image scale.
    package private(set) var symbol: (glyph: SymbolGlyph, outline: SymbolGlyphOutline)?
    package private(set) var symbolSize: SystemSymbolMetrics.Size?

    private func resolve() {
        switch view.source {
        case .named(let name):
            resource = environment.assetCatalog.image(named: name)
            symbol = nil
            symbolSize = nil
        case .url(let url, let pixelSize, let scale):
            // A loaded URL is a one-variant resource the painters fetch by its URL.
            resource = ImageResource(name: url, variants: [ImageVariant(file: url, scale: scale, pixelWidth: Int(pixelSize.width), pixelHeight: Int(pixelSize.height))])
            symbol = nil
            symbolSize = nil
        case .system(let name):
            resource = nil
            symbol = SystemSymbolGlyphs.glyph(named: name)
            let font = environment._resolvedFont
            let measured = SystemSymbolMetrics.size(named: name, pointSize: font.size, weight: font.weight, scale: environment.imageScale)
            if let measured {
                symbolSize = measured
            } else if symbol != nil {
                // A symbol with a glyph but no measurement takes the star's size at this font.
                let star = SystemSymbolMetricsTable.sizes["star"] ?? []
                symbolSize = star.count >= 36 ? SystemSymbolMetrics.size(values: star, pointSize: font.size, weight: font.weight, scale: environment.imageScale)
                    : SystemSymbolMetrics.fallback
            } else {
                symbolSize = nil
            }
        }
    }

    /// The image's size in points, or zero when the name did not resolve. A symbol under
    /// `redacted(reason: .placeholder)` takes the placeholder's size, the same for every symbol:
    /// 1.18 × the point size wide and 1.145 × tall, rounded (measured on `redacted/widths`).
    package var pointSize: CGSize {
        if case .system = view.source, environment._usesPlaceholderLayout {
            let size = environment._resolvedFont.size
            return CGSize(width: (size * 1.18).rounded(), height: (size * 1.145).rounded())
        }
        if let symbolSize { return CGSize(width: symbolSize.width, height: symbolSize.height) }
        return resource?.pointSize(scheme: environment.colorScheme, idiom: environment.assetIdiom) ?? .zero
    }

    override package func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        let size = pointSize
        guard view.resizing != nil else { return size }
        return proposal.replacingUnspecifiedDimensions(by: size)
    }

    /// A symbol sits on the text baseline like a glyph: its baselines are its bottom less the
    /// measured descent (scaled with the frame when resizable).
    override package func dimensions(in proposal: ProposedViewSize) -> ViewDimensions {
        let size = computeSizeThatFits(proposal)
        guard let symbolSize, symbolSize.height > 0 else { return ViewDimensions(size: size) }
        let baseline = size.height - symbolSize.descent * (size.height / symbolSize.height)
        // Labels centre a symbol half a cap height above its baseline, the cap height taken to
        // the half point (4.5 above at 13 pt, 7.75 at 22 pt: symbol/basic `labelIcon`).
        let font = environment._resolvedFont
        let measured = environment.platformProfile.systemFontMetrics(for: font).capHeight
        let capHeight = ((measured > 0 ? measured : font.size * 0.7046) * 2).rounded() / 2
        return ViewDimensions(size: size, explicit: [
            VerticalAlignment.firstTextBaseline.key: baseline,
            VerticalAlignment.lastTextBaseline.key: baseline,
            VerticalAlignment._iconCenter.key: baseline - capHeight / 2,
        ])
    }

    /// Whether the image is drawn as a mask for the foreground colour.
    package var isTemplate: Bool {
        switch view.renderingMode {
        case .template: return true
        case .original: return false
        case nil: return resource?.isTemplate ?? false
        }
    }

    override package func paintSelf(into list: inout DisplayList, context: PaintContext) {
        if environment._drawsPlaceholders {
            // A flat square for a symbol (its glyph box, about 3 pt inside the frame), the whole
            // frame for a catalog image; measured on `redacted/placeholder`.
            let bounds = absoluteBounds(context)
            guard bounds.width > 0, bounds.height > 0 else { return }
            var rect = bounds
            if case .system = view.source {
                // The grey square is the point size, centred in the placeholder frame.
                let side = min(environment._resolvedFont.size, min(bounds.width, bounds.height))
                rect = CGRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side)
            }
            list.append(.fillRect(context.absoluteRect(CGRect(x: rect.minX - context.origin.x, y: rect.minY - context.origin.y, width: rect.width, height: rect.height)), environment._placeholderColor))
            return
        }
        if case .system = view.source {
            paintSymbol(into: &list, context: context)
            return
        }
        guard let resource,
              let variant = resource.variant(scale: context.scale, scheme: environment.colorScheme, idiom: environment.assetIdiom)
        else { return }
        let bounds = absoluteBounds(context)
        guard bounds.width > 0, bounds.height > 0 else { return }
        var draw = ImageDraw(file: variant.file, scale: variant.scale,
                             pixelSize: CGSize(width: variant.pixelWidth, height: variant.pixelHeight), rect: bounds)
        if let resizing = view.resizing {
            draw.capInsets = resizing.capInsets
            draw.tiles = resizing.mode == .tile
        }
        draw.smoothing = view.interpolation != .none
        if isTemplate {
            draw.tint = (environment.foregroundColor ?? .primary).resolve(in: environment)
        }
        list.append(.drawImage(draw))
    }
}

extension ImageNode {
    /// Draws the symbol's stand-in glyph: the outline (on Lucide's 24 × 24 grid) scaled uniformly
    /// to fit the frame and centred, stroked in the foreground colour with a width that follows
    /// the font weight; `.fill` symbols are filled too, `.circle.fill` symbols fill their first
    /// element and stroke the rest in the knockout colour.
    private func paintSymbol(into list: inout DisplayList, context: PaintContext) {
        guard let symbol else { return }
        let bounds = absoluteBounds(context)
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
        let weight = environment._resolvedFont.weight.value
        let weightFactor: CGFloat = weight >= 700 ? 1.2 : weight >= 600 ? 1.0 : weight < 400 ? 0.6 : 0.8
        let style = StrokeStyle(lineWidth: 2 * scale * weightFactor, lineCap: .round, lineJoin: .round)
        let color = (environment.foregroundColor ?? .primary).resolve(in: environment)
        let knockout = RGBA(red: 1, green: 1, blue: 1, alpha: 1)
        switch symbol.glyph.mode {
        case 1:
            let whole = path(0..<ops.count)
            list.append(.fillPath(whole, color, eoFill: false))
            list.append(.strokePath(whole, style: style, color))
        case 2:
            let first = path(0..<min(symbol.outline.firstElement, ops.count))
            list.append(.fillPath(first, color, eoFill: false))
            list.append(.strokePath(first, style: style, color))
            if symbol.outline.firstElement < ops.count {
                list.append(.strokePath(path(symbol.outline.firstElement..<ops.count), style: style, knockout))
            }
        default:
            list.append(.strokePath(path(0..<ops.count), style: style, color))
        }
    }
}

@MainActor
package final class AspectRatioNode<Content: View>: UnaryLayoutModifierNode<Content, _AspectRatioLayout> {
    override package var changesChildSize: Bool { true }
    /// The proposal the content receives: the rectangle of the ratio that fits (or fills) the
    /// proposal; a single proposed dimension derives the other; none leaves the content its ideal.
    private func proposal(for target: ViewNode, _ proposal: ProposedViewSize) -> ProposedViewSize {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil }
        let height = proposal.height.flatMap { $0.isFinite ? $0 : nil }
        let ratio: CGFloat
        if let explicit = modifier.aspectRatio {
            ratio = explicit
        } else {
            let ideal = target.sizeThatFits(.unspecified)
            guard ideal.width > 0, ideal.height > 0 else { return proposal }
            ratio = ideal.width / ideal.height
        }
        guard ratio > 0, ratio.isFinite else { return proposal }
        switch (width, height) {
        case (nil, nil):
            return proposal
        case (let w?, nil):
            return ProposedViewSize(width: w, height: w / ratio)
        case (nil, let h?):
            return ProposedViewSize(width: h * ratio, height: h)
        case (let w?, let h?):
            let wider = h > 0 ? w / h > ratio : true
            let fitToHeight = modifier.contentMode == .fit ? wider : !wider
            return fitToHeight ? ProposedViewSize(width: h * ratio, height: h) : ProposedViewSize(width: w, height: w / ratio)
        }
    }

    override package func measure(_ target: ViewNode, proposal: ProposedViewSize) -> CGSize {
        target.sizeThatFits(self.proposal(for: target, proposal))
    }

    override package func dimensions(of target: ViewNode, in proposal: ProposedViewSize) -> ViewDimensions {
        target.dimensions(in: self.proposal(for: target, proposal))
    }

    override package func placeTarget(_ target: ViewNode, in bounds: CGRect, proposal: ProposedViewSize, by placer: ViewNode) {
        target.place(at: bounds.origin, anchor: .topLeading, proposal: self.proposal(for: target, proposal), by: placer)
    }
}
