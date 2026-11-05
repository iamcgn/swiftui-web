// Filters by name, Docs/elements/CoreImage.md. A filter holds its inputs by key, as Apple's
// does, and its output image is the input's recipe with one more step. The built-in filters
// here are the ones a display list can draw: colour matrices (colour controls, exposure,
// colour matrix, invert, monochrome effects, sepia), Gaussian blur, source-over and blend-mode
// composites, constant colours, affine transforms and crops. Any other name gives nil.

#if !canImport(CoreGraphics) || os(WASI)
import WebFoundation
import WebGraphics

public let kCIInputImageKey = "inputImage"
public let kCIInputBackgroundImageKey = "inputBackgroundImage"
public let kCIInputColorKey = "inputColor"
public let kCIInputBrightnessKey = "inputBrightness"
public let kCIInputContrastKey = "inputContrast"
public let kCIInputSaturationKey = "inputSaturation"
public let kCIInputEVKey = "inputEV"
public let kCIInputRadiusKey = "inputRadius"
public let kCIInputIntensityKey = "inputIntensity"
public let kCIInputTransformKey = "inputTransform"
public let kCIInputExtentKey = "inputExtent"
public let kCIInputAngleKey = "inputAngle"
public let kCIInputCenterKey = "inputCenter"
public let kCIInputScaleKey = "inputScale"
public let kCIInputAmountKey = "inputAmount"
public let kCIInputBiasVectorKey = "inputBiasVector"
public let kCIOutputImageKey = "outputImage"
public let kCICategoryBuiltIn = "CICategoryBuiltIn"
public let kCICategoryColorAdjustment = "CICategoryColorAdjustment"
public let kCICategoryColorEffect = "CICategoryColorEffect"
public let kCICategoryBlur = "CICategoryBlur"
public let kCICategoryCompositeOperation = "CICategoryCompositeOperation"
public let kCICategoryGenerator = "CICategoryGenerator"
public let kCICategoryGeometryAdjustment = "CICategoryGeometryAdjustment"

/// An image filter: inputs set by key, and the image they make.
open class CIFilter: CustomStringConvertible {
    struct Kind {
        let category: String
        let defaults: [String: Any]
        let make: (CIFilter) -> CIImage?
    }

    /// The filter's name ("CIColorControls").
    open var name: String
    private let kind: Kind?
    private var inputs: [String: Any] = [:]

    /// A built-in filter with its default inputs; nil for a name this module does not know.
    public init?(name: String) {
        guard let kind = CIFilter.kinds[name] else { return nil }
        self.name = name
        self.kind = kind
        inputs = kind.defaults
    }

    public convenience init?(name: String, parameters params: [String: Any]?) {
        self.init(name: name)
        for (key, value) in params ?? [:] { setValue(value, forKey: key) }
    }

    public convenience init?(name: String, withInputParameters params: [String: Any]?) {
        self.init(name: name, parameters: params)
    }

    /// A filter for a subclass to make its own output image.
    public init() {
        name = "CIFilter"
        kind = nil
    }

    open var inputKeys: [String] { inputs.keys.sorted() }
    open var outputKeys: [String] { [kCIOutputImageKey] }
    open var attributes: [String: Any] { ["CIAttributeFilterName": name, "CIAttributeFilterCategories": [kind?.category ?? kCICategoryBuiltIn]] }

    open func setValue(_ value: Any?, forKey key: String) {
        if key == "name", let value = value as? String { name = value; return }
        inputs[key] = value
    }

    open func value(forKey key: String) -> Any? {
        if key == kCIOutputImageKey { return outputImage }
        if key == "name" { return name }
        return inputs[key]
    }

    open func setValuesForKeys(_ keyedValues: [String: Any]) {
        for (key, value) in keyedValues { setValue(value, forKey: key) }
    }

    /// Puts every input back to its default.
    open func setDefaults() { inputs = kind?.defaults ?? [:] }

    /// The filtered image; nil when a required input is missing.
    open var outputImage: CIImage? { kind?.make(self) }

    open var description: String { "<CIFilter \(name)>" }

    public static func filterNames(inCategory category: String?) -> [String] {
        kinds.filter { category == nil || category == kCICategoryBuiltIn || $0.value.category == category }.keys.sorted()
    }

    public static func filterNames(inCategories categories: [String]?) -> [String] {
        guard let categories, !categories.isEmpty else { return filterNames(inCategory: nil) }
        return categories.flatMap { filterNames(inCategory: $0) }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
    }

    // MARK: Reading inputs

    func image(_ key: String) -> CIImage? { inputs[key] as? CIImage }

    func number(_ key: String) -> Double {
        switch inputs[key] {
        case let v as Double: return v
        case let v as Float: return Double(v)
        case let v as Int: return Double(v)
        #if !os(WASI)
        case let v as CGFloat: return Double(v)
        #endif
        case let v as NSNumber: return v.doubleValue
        default: return 0
        }
    }

    func color(_ key: String) -> CIColor { inputs[key] as? CIColor ?? .black }

    func vector(_ key: String) -> CIVector? { inputs[key] as? CIVector }

    // MARK: The built-ins

    private static func matrix(_ defaults: [String: Any] = [:], category: String = kCICategoryColorAdjustment,
                               _ m: @escaping (CIFilter) -> ColorMatrix) -> Kind {
        Kind(category: category, defaults: defaults) { f in
            f.image(kCIInputImageKey).map { CIImage(.matrix(m(f), $0.recipe)) }
        }
    }

    private static func blend(_ mode: BlendMode) -> Kind {
        Kind(category: kCICategoryCompositeOperation, defaults: [:]) { f in
            guard let top = f.image(kCIInputImageKey), let bottom = f.image(kCIInputBackgroundImageKey) else { return nil }
            return CIImage(.blend(mode, top.recipe, bottom.recipe))
        }
    }

    nonisolated(unsafe) static let kinds: [String: Kind] = {
        var k: [String: Kind] = [
            "CIConstantColorGenerator": Kind(category: kCICategoryGenerator, defaults: [kCIInputColorKey: CIColor.black]) { f in
                CIImage(color: f.color(kCIInputColorKey))
            },
            "CISourceOverCompositing": Kind(category: kCICategoryCompositeOperation, defaults: [:]) { f in
                guard let top = f.image(kCIInputImageKey), let bottom = f.image(kCIInputBackgroundImageKey) else { return nil }
                return top.composited(over: bottom)
            },
            "CIColorControls": matrix([kCIInputSaturationKey: 1.0, kCIInputBrightnessKey: 0.0, kCIInputContrastKey: 1.0]) { f in
                // Saturation, then brightness, then contrast; a step at its neutral value is left out.
                let (s, b, c) = (f.number(kCIInputSaturationKey), f.number(kCIInputBrightnessKey), f.number(kCIInputContrastKey))
                var m = ColorMatrix.identity
                if s != 1 { m = m.then(.saturation(s)) }
                if b != 0 { m = m.then(.brightness(b)) }
                if c != 1 { m = m.then(.contrast(c)) }
                return m
            },
            "CIExposureAdjust": matrix([kCIInputEVKey: 0.0]) { f in
                let s = _pow(2, f.number(kCIInputEVKey))
                return ColorMatrix([s, 0, 0, 0, 0, 0, s, 0, 0, 0, 0, 0, s, 0, 0, 0, 0, 0, 1, 0])
            },
            "CIColorMatrix": matrix() { f in
                let unit: [[CGFloat]] = [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]]
                let keys = ["inputRVector", "inputGVector", "inputBVector", "inputAVector"]
                let bias = f.vector(kCIInputBiasVectorKey)
                var values: [Double] = []
                for (row, key) in keys.enumerated() {
                    let v = f.vector(key)?.values ?? unit[row]
                    values += (0..<4).map { Double($0 < v.count ? v[$0] : 0) } + [Double(bias?.value(at: row) ?? 0)]
                }
                return ColorMatrix(values)
            },
            "CIColorInvert": matrix(category: kCICategoryColorEffect) { _ in .invert },
            "CIPhotoEffectMono": matrix(category: kCICategoryColorEffect) { _ in .saturation(0) },
            "CIPhotoEffectNoir": matrix(category: kCICategoryColorEffect) { _ in .saturation(0).then(.contrast(1.3)) },
            "CIPhotoEffectTonal": matrix(category: kCICategoryColorEffect) { _ in .saturation(0).then(.contrast(0.9)) },
            "CISepiaTone": matrix([kCIInputIntensityKey: 1.0], category: kCICategoryColorEffect) { f in
                let i = max(0, min(1, f.number(kCIInputIntensityKey)))
                let sepia: [Double] = [0.393, 0.769, 0.189, 0.349, 0.686, 0.168, 0.272, 0.534, 0.131]
                var values: [Double] = []
                for row in 0..<3 {
                    for col in 0..<3 { values.append((row == col ? 1 - i : 0) + i * sepia[row * 3 + col]) }
                    values += [0, 0]
                }
                return ColorMatrix(values + [0, 0, 0, 1, 0])
            },
            "CIGaussianBlur": Kind(category: kCICategoryBlur, defaults: [kCIInputRadiusKey: 10.0]) { f in
                f.image(kCIInputImageKey).map { $0.applyingGaussianBlur(sigma: f.number(kCIInputRadiusKey)) }
            },
            "CIAffineTransform": Kind(category: kCICategoryGeometryAdjustment, defaults: [:]) { f in
                guard let input = f.image(kCIInputImageKey) else { return nil }
                let t = f.inputs[kCIInputTransformKey] as? CGAffineTransform ?? f.vector(kCIInputTransformKey)?.cgAffineTransformValue ?? .identity
                return input.transformed(by: t)
            },
            "CICrop": Kind(category: kCICategoryGeometryAdjustment, defaults: [:]) { f in
                guard let input = f.image(kCIInputImageKey) else { return nil }
                return f.vector("inputRectangle").map { input.cropped(to: $0.cgRectValue) } ?? input
            },
        ]
        let modes: [String: BlendMode] = [
            "CIMultiplyCompositing": .multiply, "CIMultiplyBlendMode": .multiply, "CIScreenBlendMode": .screen,
            "CIOverlayBlendMode": .overlay, "CIDarkenBlendMode": .darken, "CILightenBlendMode": .lighten,
            "CIColorDodgeBlendMode": .colorDodge, "CIColorBurnBlendMode": .colorBurn, "CISoftLightBlendMode": .softLight,
            "CIHardLightBlendMode": .hardLight, "CIDifferenceBlendMode": .difference, "CIExclusionBlendMode": .exclusion,
            "CIHueBlendMode": .hue, "CISaturationBlendMode": .saturation, "CIColorBlendMode": .color,
            "CILuminosityBlendMode": .luminosity, "CISourceAtopCompositing": .sourceAtop,
        ]
        for (name, mode) in modes { k[name] = blend(mode) }
        return k
    }()
}

extension ColorMatrix {
    /// This matrix followed by `next`.
    func then(_ next: ColorMatrix) -> ColorMatrix {
        let a = next.values, b = values
        var out = [Double](repeating: 0, count: 20)
        for row in 0..<4 {
            for col in 0..<5 {
                var v = col == 4 ? a[row * 5 + 4] : 0
                for k in 0..<4 { v += a[row * 5 + k] * b[k * 5 + col] }
                out[row * 5 + col] = v
            }
        }
        return ColorMatrix(out)
    }
}
#endif
