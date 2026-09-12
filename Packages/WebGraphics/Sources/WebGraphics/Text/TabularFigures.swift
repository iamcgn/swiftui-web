/// Tabular figures without a font feature: Canvas2D has no `font-variant-numeric`, so a painter
/// puts every digit on one slot derived from the proportional "0" advance it can measure.
/// Measured with CoreText on macOS 26 (SF Pro, 2026-09-11): the tabular advance over the
/// proportional "0" advance depends on the weight and, slightly, on the optical size — the
/// regular text face's tabular digit is exactly its "0" (17 pt: 10.2764 both), the semibold's
/// 0.987 of it, the bold's 0.980, the black's 0.963; the display face (28 pt) runs 1.018 at
/// ultralight down to 0.978 at black. Between 17 and 28 pt the ratio interpolates linearly.
public enum TabularFigures {
    /// Slot ÷ proportional "0" advance for the text face (≤ 17 pt) and the display face (≥ 28 pt), by weight.
    static let textRatios: [Int: CGFloat] = [100: 0.9893, 200: 0.9917, 300: 0.9964, 400: 1.0, 500: 0.9923, 600: 0.9869, 700: 0.9800, 800: 0.9706, 900: 0.9631]
    static let displayRatios: [Int: CGFloat] = [100: 1.0181, 200: 1.0133, 300: 1.0039, 400: 0.9968, 500: 0.9930, 600: 0.9904, 700: 0.9869, 800: 0.9821, 900: 0.9783]

    /// The tabular slot as a multiple of the font's proportional "0" advance.
    public static func slotRatio(size: CGFloat, weight: Int) -> CGFloat {
        let key = min(900, max(100, (weight / 100) * 100))
        let text = textRatios[key] ?? 1
        let display = displayRatios[key] ?? 1
        let t = min(1, max(0, (size - 17) / 11))
        return text + (display - text) * t
    }
}
