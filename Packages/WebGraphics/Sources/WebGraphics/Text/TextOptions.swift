// Text options the layout engine reads (`Text.TruncationMode` and `Text.Scale` in SwiftUI).

/// The type of truncation to apply to a line of text when it's too long to fit in the
/// available space.
public enum TextTruncationMode: Hashable, Sendable {
    case head, tail, middle
}

/// The scale text is drawn at: the secondary scale is smaller than the default.
public struct TextScale: Hashable, Sendable {
    public let rawValue: Int
    public static let `default` = TextScale(rawValue: 0)
    public static let secondary = TextScale(rawValue: 1)
}
