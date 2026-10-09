// UIVisualEffectView (Docs/elements/UIKit/UIView.md): a blur of what lies beneath (the
// substrate's backdropBlur) under a tint, with a content view over it. The materials' sigmas
// and tints are fitted to the iPhone SE simulator's capture of each style over black, blue,
// white and red bands (uikit/view/materials, 2026-10-09): a Gaussian of the ground mixed with
// a flat tint at an alpha. UIKit's saturation boosts are not modelled, so the plain blur
// styles are approximate; a vibrancy effect view is a transparent container (its content
// draws in its own colours).

/// An object that provides a visual effect to a visual effect view.
open class UIVisualEffect: NSObject {
    public override init() { super.init() }
}

/// A blur effect in one of the system styles.
open class UIBlurEffect: UIVisualEffect {
    public enum Style: Int, Sendable {
        case extraLight = 0, light, dark, regular, prominent
        case systemUltraThinMaterial, systemThinMaterial, systemMaterial, systemThickMaterial, systemChromeMaterial
        case systemUltraThinMaterialLight, systemThinMaterialLight, systemMaterialLight, systemThickMaterialLight, systemChromeMaterialLight
        case systemUltraThinMaterialDark, systemThinMaterialDark, systemMaterialDark, systemThickMaterialDark, systemChromeMaterialDark
    }
    public let style: Style
    public init(style: Style) {
        self.style = style
        super.init()
    }

    /// The fitted look: the blur's sigma in points and the tint over it, per appearance.
    struct Look {
        let sigma: CGFloat
        let light: RGBA
        let dark: RGBA
        /// The ground's saturation under the tint (the plain styles boost it by 1.6).
        var saturation: Double = 1
    }

    var look: Look {
        func rgba(_ r: Int, _ g: Int, _ b: Int, _ a: Double) -> RGBA { RGBA(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, alpha: a) }
        let ultraThin = Look(sigma: 20, light: rgba(222, 222, 226, 0.44), dark: rgba(28, 28, 30, 0.55))
        let thin = Look(sigma: 32, light: rgba(245, 250, 252, 0.56), dark: rgba(30, 30, 32, 0.7))
        let material = Look(sigma: 28, light: rgba(245, 249, 249, 0.78), dark: rgba(37, 37, 39, 0.82))
        let thick = Look(sigma: 32, light: rgba(246, 248, 249, 0.93), dark: rgba(44, 44, 46, 0.93))
        let chrome = Look(sigma: 32, light: rgba(255, 255, 255, 0.73), dark: rgba(28, 28, 30, 0.75))
        switch style {
        case .systemUltraThinMaterial: return ultraThin
        case .systemThinMaterial: return thin
        case .systemMaterial: return material
        case .systemThickMaterial: return thick
        case .systemChromeMaterial: return chrome
        case .systemUltraThinMaterialLight: return Look(sigma: ultraThin.sigma, light: ultraThin.light, dark: ultraThin.light)
        case .systemThinMaterialLight: return Look(sigma: thin.sigma, light: thin.light, dark: thin.light)
        case .systemMaterialLight: return Look(sigma: material.sigma, light: material.light, dark: material.light)
        case .systemThickMaterialLight: return Look(sigma: thick.sigma, light: thick.light, dark: thick.light)
        case .systemChromeMaterialLight: return Look(sigma: chrome.sigma, light: chrome.light, dark: chrome.light)
        case .systemUltraThinMaterialDark: return Look(sigma: ultraThin.sigma, light: ultraThin.dark, dark: ultraThin.dark)
        case .systemThinMaterialDark: return Look(sigma: thin.sigma, light: thin.dark, dark: thin.dark)
        case .systemMaterialDark: return Look(sigma: material.sigma, light: material.dark, dark: material.dark)
        case .systemThickMaterialDark: return Look(sigma: thick.sigma, light: thick.dark, dark: thick.dark)
        case .systemChromeMaterialDark: return Look(sigma: chrome.sigma, light: chrome.dark, dark: chrome.dark)
        // The plain styles saturate the ground by 1.6 under a thin tint (regular and light fitted;
        // extra light and prominent are approximate).
        case .regular, .prominent: return Look(sigma: 24, light: rgba(239, 239, 255, 0.33), dark: rgba(25, 26, 29, 0.73), saturation: 1.6)
        case .light: return Look(sigma: 24, light: rgba(239, 239, 255, 0.33), dark: rgba(239, 239, 255, 0.33), saturation: 1.6)
        case .extraLight: return Look(sigma: 24, light: rgba(255, 255, 255, 0.6), dark: rgba(255, 255, 255, 0.6), saturation: 1.6)
        case .dark: return Look(sigma: 16, light: rgba(25, 26, 29, 0.73), dark: rgba(25, 26, 29, 0.73))
        }
    }
}

/// A vibrancy effect over a blur: its view's content shows in its own colours (approximate:
/// UIKit's vibrancy blends it with the blurred ground).
open class UIVibrancyEffect: UIVisualEffect {
    public enum Style: Int, Sendable { case label = 0, secondaryLabel, tertiaryLabel, quaternaryLabel, fill, secondaryFill, tertiaryFill, separator }
    public let blurEffect: UIBlurEffect
    public let style: Style?
    public init(blurEffect: UIBlurEffect, style: Style? = nil) {
        self.blurEffect = blurEffect
        self.style = style
        super.init()
    }
}

/// An object that implements some complex visual effects.
@MainActor
open class UIVisualEffectView: UIView {
    open var effect: UIVisualEffect? { didSet { setNeedsDisplay() } }
    /// The view for content to be placed over the effect.
    public let contentView = UIView()

    public init(effect: UIVisualEffect?) {
        self.effect = effect
        super.init(frame: .zero)
        contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(contentView)
    }

    public override convenience init(frame: CGRect) {
        self.init(effect: nil)
        self.frame = frame
    }

    override open func layoutSubviews() {
        super.layoutSubviews()
        contentView.frame = bounds
    }

    override func drawContent(into list: inout DisplayList, context: PaintContext, style: UIUserInterfaceStyle) {
        guard let blur = effect as? UIBlurEffect else { return }
        let rect = context.absoluteRect(CGRect(origin: .zero, size: bounds.size))
        let radius = min(layer.cornerRadius, min(rect.width, rect.height) / 2)
        let path = radius > 0 ? Path(roundedRect: rect, cornerRadius: radius, style: layer.cornerCurve == .continuous ? .continuous : .circular) : Path(rect)
        let look = blur.look
        list.append(.backdropBlur(path, bounds: rect, radius: look.sigma, saturation: look.saturation))
        list.append(.fillPath(path, style == .dark ? look.dark : look.light))
    }
}

/// iOS 26's glass platters (tab bar pills, bar buttons, floating toolbars, search fields): a
/// blur of what lies beneath under a thin white tint, with a soft shadow. Fitted to the
/// simulator's pill over yellow in ios/representable/hostingsafearea-tabs (the ground at 69 %
/// under white); over white it is the 252 the UIKit goldens measured. The glass's refraction
/// and highlight rim are not drawn (approximate).
@MainActor
enum GlassPainter {
    static let sigma: CGFloat = 20
    static let lightTint = RGBA(red: 1, green: 1, blue: 1, alpha: 0.31)
    static let darkTint = RGBA(red: 44.0 / 255, green: 44.0 / 255, blue: 46.0 / 255, alpha: 0.75)

    /// Paints a capsule (or `cornerRadius`-rounded) platter at `rect` (absolute).
    static func paintPlatter(_ rect: CGRect, cornerRadius: CGFloat? = nil, style: UIUserInterfaceStyle, shadow: Double = 0.08, into list: inout DisplayList) {
        let radius = min(cornerRadius ?? rect.height / 2, min(rect.width, rect.height) / 2)
        let path = Path(roundedRect: rect, cornerRadius: radius)
        list.append(.backdropBlur(path, bounds: rect, radius: sigma))
        if shadow > 0 { list.append(.beginShadow(RGBA(red: 0, green: 0, blue: 0, alpha: shadow), radius: 10, offset: CGSize(width: 0, height: 4))) }
        list.append(.fillPath(path, style == .dark ? darkTint : lightTint))
        if shadow > 0 { list.append(.endGroup) }
    }
}
