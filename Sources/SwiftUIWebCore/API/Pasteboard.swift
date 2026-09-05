// The pasteboard: `copyable` and `cuttable` put Transferable values on the app's pasteboard
// on ⌘C / ⌘X when the view is in the focused chain, `pasteDestination` takes them on ⌘V,
// `PasteButton` offers them as a button. Hosts that can write the system clipboard get the
// text export of every copy; reading the system clipboard is not attempted.

public struct _CopyableModifier<T: Transferable> {
    package let payload: () -> [T]
}

extension _CopyableModifier: ViewModifier {
    public typealias Body = Never
    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        CopyableNode(context)
    }
}

public struct _CuttableModifier<T: Transferable> {
    package let action: () -> [T]
}

extension _CuttableModifier: ViewModifier {
    public typealias Body = Never
    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        CuttableNode(context)
    }
}

public struct _PasteDestinationModifier<T: Transferable> {
    package let action: ([T]) -> Void
    package let validator: ([T]) -> [T]
}

extension _PasteDestinationModifier: ViewModifier {
    public typealias Body = Never
    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        PasteDestinationNode(context)
    }
}

extension View {
    /// Copies `payload` to the pasteboard on ⌘C while this view (or a view inside it) is focused.
    nonisolated public func copyable<T: Transferable>(_ payload: @autoclosure @escaping () -> [T]) -> some View {
        modifier(_CopyableModifier(payload: payload))
    }

    /// Cuts on ⌘X: `action` removes the values and returns what goes on the pasteboard.
    nonisolated public func cuttable<T: Transferable>(for payloadType: T.Type = T.self, action: @escaping () -> [T]) -> some View {
        modifier(_CuttableModifier(action: action))
    }

    /// Takes pasted values of `payloadType` on ⌘V while this view is focused.
    nonisolated public func pasteDestination<T: Transferable>(for payloadType: T.Type = T.self, action: @escaping ([T]) -> Void,
                                                              validator: @escaping ([T]) -> [T] = { $0 }) -> some View {
        modifier(_PasteDestinationModifier(action: action, validator: validator))
    }
}

/// A button that pastes the pasteboard's values of a type; disabled while there are none.
public struct PasteButton<T: Transferable>: View {
    package let onPaste: ([T]) -> Void
    @Environment(\._pasteboardGeneration) private var generation
    @Environment(\._pasteboardProbe) private var probe

    public init(payloadType: T.Type = T.self, onPaste: @escaping ([T]) -> Void) {
        self.onPaste = onPaste
    }

    public var body: some View {
        let available = probe.items().compactMap { $0.load(as: T.self) }
        Button {
            onPaste(available)
        } label: {
            Label("Paste", systemImage: "doc.on.clipboard")
        }
        .disabled(available.isEmpty)
        .id(generation)
    }
}

/// Lets views read the runtime's pasteboard (installed by the runtime).
package struct _PasteboardProbe {
    package var items: () -> [_TransferItem] = { [] }
}

package struct PasteboardProbeKey: EnvironmentKey {
    package nonisolated(unsafe) static let defaultValue = _PasteboardProbe()
}

package struct PasteboardGenerationKey: EnvironmentKey {
    package static let defaultValue = 0
}

extension EnvironmentValues {
    package var _pasteboardProbe: _PasteboardProbe {
        get { self[PasteboardProbeKey.self] }
        set { self[PasteboardProbeKey.self] = newValue }
    }
    /// Bumped on every copy or cut so paste buttons re-evaluate.
    package var _pasteboardGeneration: Int {
        get { self[PasteboardGenerationKey.self] }
        set { self[PasteboardGenerationKey.self] = newValue }
    }
}
