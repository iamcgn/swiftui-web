// Canvas runtime: a flexible leaf that runs its renderer at paint time with a GraphicsContext
// recording into the display list, translated to the canvas's origin and clipped to its bounds.

@MainActor
package final class CanvasNode<Symbols: View>: LeafNode<Canvas<Symbols>> {
    override package func paintSelf(into list: inout DisplayList, context: PaintContext) {
        let bounds = absoluteBounds(context)
        let recorder = _GraphicsRecorder(environment: environment, textEngine: runtime.textEngine, scale: context.scale)
        var graphics = GraphicsContext(recorder: recorder)
        graphics.translateBy(x: bounds.minX, y: bounds.minY)
        view.renderer.draw(&graphics, bounds.size)
        guard !recorder.list.commands.isEmpty else { return }
        list.append(.save)
        list.append(.clipRect(bounds))
        list.commands.append(contentsOf: recorder.list.commands)
        list.append(.restore)
    }

    override package var nodeDescription: String { "Canvas" }
}
