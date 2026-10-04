// Canvas runtime: a flexible leaf that runs its renderer at paint time with a GraphicsContext
// recording into the display list, translated to the canvas's origin and clipped to its bounds.

@MainActor
package final class CanvasNode<Symbols: View>: LeafNode<Canvas<Symbols>> {
    /// The `symbols` views, mounted but not laid out as children: `resolveSymbol` finds them by tag.
    package private(set) var symbols: TypedNode<Symbols>!

    override package init(_ context: _NodeContext<Canvas<Symbols>>) {
        super.init(context)
        symbols = Symbols._makeNode(_NodeContext(view: context.view.symbols, parent: self, environment: context.environment))
    }

    override package func update(view: Canvas<Symbols>, environment: EnvironmentValues, force: Bool) {
        super.update(view: view, environment: environment, force: force)
        symbols.update(view: view.symbols, environment: environment, force: force)
    }

    override package func unmount() {
        symbols.unmount()
        super.unmount()
    }

    /// The tagged symbol views (`_collectOptions`: `ForEach` ids stand in for missing tags).
    package var taggedSymbols: [(id: AnyHashable, node: ViewNode)] {
        _collectOptions(symbols).compactMap { entry in
            (entry.node.layoutValue(for: TagKey.self) ?? entry.id).map { ($0, entry.node) }
        }
    }

    /// A state read by the renderer that changes repaints the canvas (`_trackingObservation`).
    override package func performUpdate() {
        clearNeedsUpdate()
        runtime.setNeedsDisplay()
    }

    override package func paintSelf(into list: inout DisplayList, context: PaintContext) {
        let bounds = absoluteBounds(context)
        let recorder = _GraphicsRecorder(environment: environment, textEngine: runtime.textEngine, scale: context.scale)
        recorder.node = self
        recorder.symbols = taggedSymbols
        var graphics = GraphicsContext(recorder: recorder)
        graphics.translateBy(x: bounds.minX, y: bounds.minY)
        let renderer = view.renderer
        _trackingObservation(for: self) { renderer.draw(&graphics, bounds.size) }
        guard !recorder.list.commands.isEmpty else { return }
        list.append(.save)
        list.append(.clipRect(bounds))
        list.commands.append(contentsOf: recorder.list.commands)
        list.append(.restore)
    }

    override package var structuralChildren: [ViewNode] { [symbols] }
    override package var nodeDescription: String { "Canvas" }
}
