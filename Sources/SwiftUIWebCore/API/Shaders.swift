// Shaders (iOS 17): a function from an app's Metal library, its arguments, and the three effects
// that run one over a view (colorEffect, distortionEffect, layerEffect), plus a shader used as a
// shape style. A browser has no Metal, and an app's shaders are written in the Metal Shading
// Language, so none runs here: the API is all present so the app builds, a view under a shader
// effect draws as it would without the effect, and a shader used as a fill draws nothing.
// `compile(as:)` throws, as it does on a device when a shader can't be compiled.
#if os(WASI)
import WebFoundation   // never full Foundation on wasm: it links ICU (decisions 0006, 0017)
#else
import Foundation
#endif

/// A library of shader functions, from the app's Metal sources.
@dynamicMemberLookup
public struct ShaderLibrary: Equatable, Hashable, @unchecked Sendable {
    enum Source: Hashable {
        case bundle(ObjectIdentifier)
        case url(URL)
        case data(Data)
    }
    let source: Source

    /// The library in the app's main bundle.
    public static let `default` = ShaderLibrary(source: .bundle(ObjectIdentifier(Bundle.main)))

    /// The library in `bundle`.
    public static func bundle(_ bundle: Bundle) -> ShaderLibrary { ShaderLibrary(source: .bundle(ObjectIdentifier(bundle))) }

    /// The library in the Metal library file at `url`.
    public init(url: URL) { source = .url(url) }

    /// The library in `data`, a Metal library's contents.
    public init(data: Data) { source = .data(data) }

    init(source: Source) { self.source = source }

    /// The function called `name` in the default library.
    public static subscript(dynamicMember name: String) -> ShaderFunction { ShaderFunction(library: .default, name: name) }

    /// The function called `name` in this library.
    public subscript(dynamicMember name: String) -> ShaderFunction { ShaderFunction(library: self, name: name) }
}

/// A function in a shader library; call it with its arguments to make a shader.
@dynamicCallable
public struct ShaderFunction: Equatable, Hashable, Sendable {
    /// The library the function is in.
    public var library: ShaderLibrary
    /// The function's name.
    public var name: String

    public init(library: ShaderLibrary, name: String) {
        self.library = library
        self.name = name
    }

    /// The shader that runs this function with `arguments`.
    public func dynamicallyCall(withArguments arguments: [Shader.Argument]) -> Shader {
        Shader(function: self, arguments: arguments)
    }
}

/// A shader function with its arguments, to run as an effect on a view or to fill a shape.
public struct Shader: Equatable, Sendable, ShapeStyle {
    /// One argument a shader function receives after its position (and colour or layer).
    public struct Argument: Equatable, Sendable {
        enum Value: Equatable, Sendable {
            case float([Float])
            case floatArray([Float])
            case color(Color)
            case colorArray([Color])
            case image(Image)
            case data(Data)
            case boundingRect
        }
        let value: Value

        /// A `float`.
        public static func float<T: BinaryFloatingPoint>(_ x: T) -> Argument { Argument(value: .float([Float(x)])) }
        /// A `float2`.
        public static func float2<T: BinaryFloatingPoint>(_ x: T, _ y: T) -> Argument { Argument(value: .float([Float(x), Float(y)])) }
        /// A `float2` holding a point.
        public static func float2(_ point: CGPoint) -> Argument { float2(point.x, point.y) }
        /// A `float2` holding a size.
        public static func float2(_ size: CGSize) -> Argument { float2(size.width, size.height) }
        /// A `float2` holding a vector.
        public static func float2(_ vector: CGVector) -> Argument { float2(vector.dx, vector.dy) }
        /// A `float3`.
        public static func float3<T: BinaryFloatingPoint>(_ x: T, _ y: T, _ z: T) -> Argument {
            Argument(value: .float([Float(x), Float(y), Float(z)]))
        }
        /// A `float4`.
        public static func float4<T: BinaryFloatingPoint>(_ x: T, _ y: T, _ z: T, _ w: T) -> Argument {
            Argument(value: .float([Float(x), Float(y), Float(z), Float(w)]))
        }
        /// A `device const float *` and its count.
        public static func floatArray(_ array: [Float]) -> Argument { Argument(value: .floatArray(array)) }
        /// A `half4` holding a colour.
        public static func color(_ color: Color) -> Argument { Argument(value: .color(color)) }
        /// A `device const half4 *` and its count.
        public static func colorArray(_ array: [Color]) -> Argument { Argument(value: .colorArray(array)) }
        /// A `texture2d<half>` holding an image.
        public static func image(_ image: Image) -> Argument { Argument(value: .image(image)) }
        /// A `device const void *` and its size in bytes.
        public static func data(_ data: Data) -> Argument { Argument(value: .data(data)) }
        /// A `float4` holding the bounds of the view or shape being drawn.
        public static var boundingRect: Argument { Argument(value: .boundingRect) }
    }

    /// How a shader is used, for `compile(as:)`.
    public struct UsageType: Hashable, Sendable {
        let kind: Int
        /// As the shader of `colorEffect`.
        public static let colorEffect = UsageType(kind: 0)
        /// As the shader of `distortionEffect`.
        public static let distortionEffect = UsageType(kind: 1)
        /// As the shader of `layerEffect`.
        public static let layerEffect = UsageType(kind: 2)
    }

    /// The function the shader runs.
    public var function: ShaderFunction
    /// The arguments it passes the function.
    public var arguments: [Argument]
    /// Whether colours the shader returns are dithered.
    public var dithersColor: Bool = true

    public init(function: ShaderFunction, arguments: [Argument]) {
        self.function = function
        self.arguments = arguments
    }

    /// Compiles the shader ahead of its first use. Metal shaders can't run in a browser, so this
    /// always throws, as it does on a device for a shader that won't compile.
    public func compile(as type: UsageType) async throws {
        throw _ShaderUnavailable(name: function.name)
    }
}

/// The error `Shader.compile(as:)` throws: the browser can't run Metal shaders.
public struct _ShaderUnavailable: Error, Sendable {
    public let name: String
}

extension View {
    /// Runs `shader` over each pixel's colour. Shaders don't run in a browser, so the view draws
    /// without it.
    nonisolated public func colorEffect(_ shader: Shader, isEnabled: Bool = true) -> some View { self }

    /// Runs `shader` to move each pixel. Shaders don't run in a browser, so the view draws
    /// without it.
    nonisolated public func distortionEffect(_ shader: Shader, maxSampleOffset: CGSize, isEnabled: Bool = true) -> some View { self }

    /// Runs `shader` over the view's rendered layer. Shaders don't run in a browser, so the view
    /// draws without it.
    nonisolated public func layerEffect(_ shader: Shader, maxSampleOffset: CGSize, isEnabled: Bool = true) -> some View { self }
}

extension VisualEffect {
    /// Runs `shader` over each pixel's colour; it doesn't run in a browser, so this adds nothing.
    public func colorEffect(_ shader: Shader, isEnabled: Bool = true) -> some VisualEffect { _VisualEffectModified(_steps: _steps) }

    /// Runs `shader` to move each pixel; it doesn't run in a browser, so this adds nothing.
    public func distortionEffect(_ shader: Shader, maxSampleOffset: CGSize, isEnabled: Bool = true) -> some VisualEffect {
        _VisualEffectModified(_steps: _steps)
    }

    /// Runs `shader` over the view's layer; it doesn't run in a browser, so this adds nothing.
    public func layerEffect(_ shader: Shader, maxSampleOffset: CGSize, isEnabled: Bool = true) -> some VisualEffect {
        _VisualEffectModified(_steps: _steps)
    }
}
