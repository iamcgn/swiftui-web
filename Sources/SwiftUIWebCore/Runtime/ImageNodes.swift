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

    private func resolve() {
        switch view.source {
        case .named(let name): resource = environment.assetCatalog.image(named: name)
        case .system: resource = nil
        }
    }

    /// The image's size in points, or zero when the name did not resolve.
    package var pointSize: CGSize {
        resource?.pointSize(scheme: environment.colorScheme, idiom: environment.assetIdiom) ?? .zero
    }

    override package func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        let size = pointSize
        guard view.resizing != nil else { return size }
        return proposal.replacingUnspecifiedDimensions(by: size)
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

@MainActor
package final class AspectRatioNode<Content: View>: UnaryLayoutModifierNode<Content, _AspectRatioLayout> {
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
