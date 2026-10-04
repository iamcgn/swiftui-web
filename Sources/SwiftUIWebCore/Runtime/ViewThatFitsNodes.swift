// ViewThatFits runtime (API/ViewThatFits.swift): the candidates are the content's layout
// children; each is asked its ideal size and the first whose size fits the proposal on the
// chosen axes is the one laid out, painted and reporting preferences (the last when none fits).

@MainActor
package final class ViewThatFitsNode<Content: View>: LayoutNode<ViewThatFits<Content>> {
    package private(set) var content: TypedNode<Content>!
    /// The candidate chosen by the last layout (for tests and painting).
    package private(set) var chosenIndex: Int?

    package init(_ context: _NodeContext<ViewThatFits<Content>>) {
        super.init(view: context.view, parent: context.parent, runtime: context.runtime, environment: context.environment)
        content = Content._makeNode(_NodeContext(view: context.view.content, parent: self, environment: context.environment))
    }

    override package func update(view: ViewThatFits<Content>, environment: EnvironmentValues, force: Bool) {
        self.view = view
        self.environment = environment
        clearNeedsUpdate()
        content.update(view: view.content, environment: environment, force: force)
    }

    package var candidates: [ViewNode] { content.layoutChildren }

    /// The first candidate whose ideal size fits the proposal on the constrained axes (an
    /// unproposed axis always fits), else the last.
    package func choose(for proposal: ProposedViewSize) -> ViewNode? {
        let candidates = candidates
        for candidate in candidates {
            let ideal = candidate.sizeThatFits(.unspecified)
            let fitsWidth = !view.axes.contains(.horizontal) || proposal.width.map { !$0.isFinite || ideal.width <= $0 + 0.001 } ?? true
            let fitsHeight = !view.axes.contains(.vertical) || proposal.height.map { !$0.isFinite || ideal.height <= $0 + 0.001 } ?? true
            if fitsWidth && fitsHeight { return candidate }
        }
        return candidates.last
    }

    private var chosen: ViewNode? {
        guard let chosenIndex, chosenIndex < candidates.count else { return nil }
        return candidates[chosenIndex]
    }

    override package func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        choose(for: proposal)?.sizeThatFits(proposal) ?? .zero
    }

    override package func dimensions(in proposal: ProposedViewSize) -> ViewDimensions {
        choose(for: proposal)?.dimensions(in: proposal) ?? ViewDimensions(size: .zero)
    }

    override package var layoutSpacing: ViewSpacing { chosen?.layoutSpacing ?? candidates.first?.layoutSpacing ?? ViewSpacing() }

    override package func layoutContents(proposal: ProposedViewSize) {
        guard let node = choose(for: proposal) else { chosenIndex = nil; return }
        chosenIndex = candidates.firstIndex { $0 === node }
        node.place(at: .zero, anchor: .topLeading, proposal: proposal, by: self)
    }

    /// Only the chosen child reports preferences (the others are not in the hierarchy).
    override package func preferenceValue<K: PreferenceKey>(for key: K.Type) -> K.Value? {
        guard let chosen, let value = chosen.preferenceValue(for: key) else { return nil }
        return transformPreference(key, value)
    }

    override package var paintedChildren: [ViewNode] { chosen.map { [$0] } ?? [] }
    override package var structuralChildren: [ViewNode] { [content] }
    override package var nodeDescription: String { "ViewThatFits" }
}
