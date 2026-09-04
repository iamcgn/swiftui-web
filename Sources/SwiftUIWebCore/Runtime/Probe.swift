/// Debug facility: records the laid-out frame of a view under an identifier, in root
/// coordinates. Used by the fixture harness (`probe`) and the browser debug bridge.
public struct _ProbeModifier: Equatable {
    public let id: String

    public init(id: String) { self.id = id }
}

extension _ProbeModifier: ViewModifier {
    public typealias Body = Never

    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        ProbeNode(context)
    }
}

extension View {
    /// Records this view's frame under `id` after every layout pass.
    nonisolated public func _probe(_ id: String) -> some View {
        modifier(_ProbeModifier(id: id))
    }
}

@MainActor
package final class ProbeNode<Content: View>: UnaryLayoutModifierNode<Content, _ProbeModifier> {
    override package var readsGeometry: Bool { true }
    override package func placeTarget(_ target: ViewNode, in bounds: CGRect, proposal: ProposedViewSize, by placer: ViewNode) {
        super.placeTarget(target, in: bounds, proposal: proposal, by: placer)
        runtime.probeFrames[modifier.id] = placer.frameInRoot
    }
}
