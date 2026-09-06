/// Modes for compositing a view with overlapping content (`View.blendMode`; a Canvas context's
/// `blendMode` is not painted yet).
public enum BlendMode: Hashable, Sendable, CaseIterable {
    case normal, multiply, screen, overlay, darken, lighten, colorDodge, colorBurn, softLight, hardLight
    case difference, exclusion, hue, saturation, color, luminosity, sourceAtop, destinationOver, destinationOut, plusDarker, plusLighter

    /// The mode's position in `allCases`, the display list's encoding.
    public var _index: Int { Self.allCases.firstIndex(of: self)! }
}
