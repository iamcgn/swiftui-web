// `allowsHitTesting` (Docs/coverage.md: 3 apps, mostly an overlay that must let taps through
// to the view beneath, as a chart's annotation or a drawn highlight does). With hit testing off
// the view and everything in it are skipped by the hit test, so a press goes to whatever lies
// under them; a gesture or control above the modifier finds no content to hit, as SwiftUI's
// `.allowsHitTesting(false).onTapGesture` never fires. On, the modifier changes nothing.
import WebFoundation
import WebGraphics

extension View {
    /// Configures whether this view participates in hit test operations.
    nonisolated public func allowsHitTesting(_ enabled: Bool) -> some View {
        modifier(_AllowsHitTestingModifier(allowsHitTesting: enabled))
    }
}

public struct _AllowsHitTestingModifier {
    package let allowsHitTesting: Bool
    package init(allowsHitTesting: Bool) { self.allowsHitTesting = allowsHitTesting }
}

extension _AllowsHitTestingModifier: ViewModifier {
    public typealias Body = Never
    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        AllowsHitTestingNode(context)
    }
}

@MainActor
package final class AllowsHitTestingNode<Content: View>: UnaryLayoutModifierNode<Content, _AllowsHitTestingModifier>, _ContentShapeProviding {
    /// Off, no point is inside; on, a content shape beneath answers as it would without this.
    package func _interactionShapeContains(_ point: CGPoint) -> Bool? {
        modifier.allowsHitTesting ? _contentShapeContains(point) : false
    }

    override package func contains(_ point: CGPoint) -> Bool {
        modifier.allowsHitTesting && super.contains(point)
    }

    /// Off, the hit test skips the subtree.
    override package var clipsHitTesting: Bool { !modifier.allowsHitTesting }

    override package var nodeDescription: String { "AllowsHitTesting" }
}
