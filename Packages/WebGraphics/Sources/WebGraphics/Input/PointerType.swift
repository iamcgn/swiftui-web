/// The kind of device behind a pointer event. Touch pointers pan scroll views; mice press.
public enum PointerType: Sendable {
    case mouse, touch, pen
}
