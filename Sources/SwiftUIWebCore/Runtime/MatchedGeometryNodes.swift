// Runtime for matchedGeometryEffect: sources record their root frames and anchors per layout in
// the runtime's registry; a follower keeps its own layout size but lays its content out at the
// source's size and puts it on the source's anchor point (measured on `matched/anchors`,
// 2026-09-05); a newly placed matched view tweens from the recorded frame and moves a retiring
// source to its own.

/// What a source last recorded.
package struct MatchedGeometryRecord {
    package weak var node: ViewNode?
    package var frame: CGRect
    package var anchor: UnitPoint
    package var generation: UInt64
}

@MainActor
package final class MatchedGeometryNode<Content: View>: UnaryLayoutModifierNode<Content, _MatchedGeometryEffect> {
    override package var paintsOutsideFrame: Bool { !modifier.isSource }
    private var hasRecorded = false

    /// The source this follower copies (nil for sources and unmatched followers).
    private var source: MatchedGeometryRecord? {
        guard !modifier.isSource, let record = runtime.matchedGeometry[modifier.key], let node = record.node, node !== self else { return nil }
        return record
    }

    /// Followers lay their content out at the source's size (`.size`, `.frame`); the node's own
    /// size, as its parent sees it, stays the content's size for the parent's proposal.
    override package func placeTarget(_ target: ViewNode, in bounds: CGRect, proposal: ProposedViewSize, by placer: ViewNode) {
        guard let source, modifier.properties.contains(.size) || modifier.properties.contains(.position) else {
            super.placeTarget(target, in: bounds, proposal: proposal, by: placer)
            return
        }
        let contentProposal = modifier.properties.contains(.size) ? ProposedViewSize(source.frame.size) : childProposal(proposal)
        let content = target.dimensions(in: contentProposal)
        var origin = CGPoint(x: bounds.minX, y: bounds.minY)
        if modifier.properties.contains(.position) {
            // The content's anchor point lands on the source's anchor point; with the frame
            // copied as well, SwiftUI shifts it once more by the size difference at the anchor.
            let root = frameInRoot
            let anchorPoint = CGPoint(x: source.frame.minX + source.frame.width * source.anchor.x - root.minX,
                                      y: source.frame.minY + source.frame.height * source.anchor.y - root.minY)
            let a = modifier.anchor
            origin = CGPoint(x: anchorPoint.x - content.width * a.x, y: anchorPoint.y - content.height * a.y)
            if modifier.properties.contains(.size) {
                origin.x += (source.frame.width - content.width) * a.x
                origin.y += (source.frame.height - content.height) * a.y
            }
        }
        target.place(at: origin, anchor: .topLeading, proposal: contentProposal, by: placer)
    }

    override package func layoutContents(proposal: ProposedViewSize) {
        super.layoutContents(proposal: proposal)
        let key = modifier.key
        let mine = frameInRoot
        let previous = runtime.matchedGeometry[key]
        if !hasRecorded {
            hasRecorded = true
            // Arriving where another view of the group was: glide from its frame, and send a
            // retiring source along to this one.
            if let previous, previous.node !== self, let animation = runtime.effectiveLayoutAnimation(for: self) {
                beginFrameTween(from: local(previous.frame), animation: animation)
                if let ghost = previous.node, ghost.isExiting {
                    let parentOrigin = CGPoint(x: ghost.frameInRoot.minX - ghost.frame.minX, y: ghost.frameInRoot.minY - ghost.frame.minY)
                    let from = ghost.presentedFrame
                    ghost.frame = CGRect(x: mine.minX - parentOrigin.x, y: mine.minY - parentOrigin.y, width: mine.width, height: mine.height)
                    ghost.beginFrameTween(from: from, animation: animation)
                }
            }
        }
        if modifier.isSource || previous == nil || previous?.node == nil {
            runtime.matchedGeometry[key] = MatchedGeometryRecord(node: self, frame: mine, anchor: modifier.anchor, generation: runtime.layoutGeneration)
        }
    }

    /// A root frame in this node's parent's coordinates.
    private func local(_ rootFrame: CGRect) -> CGRect {
        let root = frameInRoot
        return CGRect(x: rootFrame.minX - (root.minX - frame.minX), y: rootFrame.minY - (root.minY - frame.minY),
                      width: rootFrame.width, height: rootFrame.height)
    }

    /// While the frame tweens, the content scales with it (the origin already follows).
    private var tweenScale: CGAffineTransform? {
        guard presentation?.frame != nil, frame.width > 0, frame.height > 0 else { return nil }
        let presented = presentedFrame
        let sx = presented.width / frame.width, sy = presented.height / frame.height
        return sx == 1 && sy == 1 ? nil : CGAffineTransform(scaleX: sx, y: sy)
    }

    override package func paintTarget(_ target: ViewNode, in node: ViewNode, into list: inout DisplayList, context: PaintContext) {
        guard let scale = tweenScale else {
            super.paintTarget(target, in: node, into: &list, context: context)
            return
        }
        paintTransformed(scale, into: &list) { list in
            super.paintTarget(target, in: node, into: &list, context: context)
        }
    }

    override package func unmount() {
        if runtime.matchedGeometry[modifier.key]?.node === self, !isExiting {
            // Keep the frame for a successor arriving in the same update; drop the node.
            runtime.matchedGeometry[modifier.key]?.node = nil
        }
        super.unmount()
    }

    override package var nodeDescription: String { "MatchedGeometry" }
}
