/// Creates a preview of a SwiftUI view. Previews are an editor feature: here the macro expands
/// to nothing, so `#Preview` blocks in app sources compile and have no effect at runtime.
@freestanding(declaration)
public macro Preview(_ name: String? = nil, body: @escaping @MainActor () -> any View) =
    #externalMacro(module: "SwiftUIWebMacros", type: "PreviewMacro")

/// Creates a preview with traits (ignored).
@freestanding(declaration)
public macro Preview(_ name: String? = nil, traits: PreviewTrait, _ moreTraits: PreviewTrait..., body: @escaping @MainActor () -> any View) =
    #externalMacro(module: "SwiftUIWebMacros", type: "PreviewMacro")

/// Options a preview declares (ignored here).
public struct PreviewTrait: Sendable {
    public init() {}
    public static let sizeThatFitsLayout = PreviewTrait()
    public static let landscapeLeft = PreviewTrait()
    public static let landscapeRight = PreviewTrait()
    public static let portrait = PreviewTrait()
    public static let portraitUpsideDown = PreviewTrait()
    public static func fixedLayout(width: Double, height: Double) -> PreviewTrait { PreviewTrait() }
}

/// A type that produces previews (the older API); previews are ignored here.
public protocol PreviewProvider {
    associatedtype Previews: View
    @ViewBuilder @MainActor static var previews: Previews { get }
}
