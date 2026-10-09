// UIImage and UIImageView (uk-images, Docs/elements/UIKit/Drawing.md): every content mode of
// a clipped image view, rendering modes and tints on catalog images and a symbol, an image
// made from PNG data and one round-tripped through pngData().
#if canImport(UIKit)
import UIKit
import UIKitFixtureKit

public enum ImageFixtures {
    public static let all = [modes, tints]

    /// A 4 × 4 checker of red and blue 2 × 2 squares, as PNG bytes.
    static let checkerPNG = "iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAYAAACp8Z5+AAAAJ0lEQVR4nGO8o6Hxn4GBgcFHYwuIYmACk0iAUSPgDljFlhs+2FUAAEYLB4VoDJZLAAAAAElFTkSuQmCC"

    /// The 80 × 60 photo in 100 × 70 clipped views, one per content mode, on a grey ground.
    public static let modes = UIKitFixture("uikit/imageview/modes", size: CGSize(width: 320, height: 420)) {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 420))
        root.backgroundColor = .white
        let modes: [(UIView.ContentMode, String)] = [
            (.scaleToFill, "fill"), (.scaleAspectFit, "fit"), (.scaleAspectFill, "aspectFill"),
            (.center, "center"), (.top, "top"), (.bottom, "bottom"),
            (.left, "left"), (.right, "right"), (.topLeft, "topLeft"),
            (.topRight, "topRight"), (.bottomLeft, "bottomLeft"), (.bottomRight, "bottomRight"),
            (.redraw, "redraw"),
        ]
        for (index, (mode, probe)) in modes.enumerated() {
            let view = UIImageView(image: UIKitFixtureImage.named("photo"))
            view.contentMode = mode
            view.clipsToBounds = true
            view.backgroundColor = .systemGray5
            view.frame = CGRect(x: 10 + CGFloat(index % 3) * 103, y: 10 + CGFloat(index / 3) * 80, width: 100, height: 70)
            root.addSubview(view.probe(probe))
        }
        // An unclipped aspect-fill view draws past its frame (the 20 × 64 tall image over the
        // empty cell beside "redraw").
        let unclipped = UIImageView(image: UIKitFixtureImage.named("tall"))
        unclipped.contentMode = .scaleAspectFill
        unclipped.frame = CGRect(x: 153, y: 358, width: 20, height: 8)
        root.addSubview(unclipped.probe("unclipped"))
        return root
    }

    /// Rendering modes and tints: the template icon with the view's tint and as original, the
    /// badge as a template in red and tinted green as original, a bold symbol in orange, a
    /// checker from PNG data scaled up, and the badge through pngData() and back.
    public static let tints = UIKitFixture("uikit/imageview/tints", size: CGSize(width: 320, height: 200)) {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 200))
        root.backgroundColor = .white
        @MainActor func add(_ image: UIImage?, x: CGFloat, y: CGFloat, size: CGFloat = 48, tint: UIColor? = nil, mode: UIView.ContentMode = .scaleAspectFit, probe: String) {
            let view = UIImageView(image: image)
            view.contentMode = mode
            if let tint { view.tintColor = tint }
            view.frame = CGRect(x: x, y: y, width: size, height: size)
            root.addSubview(view.probe(probe))
        }
        add(UIKitFixtureImage.named("icon"), x: 16, y: 16, probe: "template")
        add(UIKitFixtureImage.named("icon")?.withRenderingMode(.alwaysOriginal), x: 88, y: 16, probe: "original")
        add(UIKitFixtureImage.named("badge")?.withRenderingMode(.alwaysTemplate), x: 160, y: 16, tint: .systemRed, probe: "badgeTemplate")
        add(UIKitFixtureImage.named("badge")?.withTintColor(.systemGreen), x: 232, y: 16, probe: "badgeTinted")
        add(UIImage(systemName: "star.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 32, weight: .bold)), x: 16, y: 96, tint: .systemOrange, probe: "symbol")
        let checker = Data(base64Encoded: checkerPNG).flatMap { UIImage(data: $0) }
        add(checker, x: 88, y: 96, mode: .scaleToFill, probe: "data")
        // pngData() needs a rasteriser (nil headless): the badge itself stands in.
        let badge = UIKitFixtureImage.named("badge")
        let round = badge?.pngData().flatMap { UIImage(data: $0, scale: 2) } ?? badge
        add(round, x: 160, y: 96, probe: "roundTrip")
        let sized = UIImageView(image: UIKitFixtureImage.named("swatch"))
        sized.frame.origin = CGPoint(x: 232, y: 96)
        root.addSubview(sized.probe("sized"))   // an image view sized to its image (64 × 40)
        return root
    }
}
#endif
