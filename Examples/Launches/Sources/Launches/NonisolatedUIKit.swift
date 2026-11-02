// UIKit reached from nonisolated code, as packages written before Swift concurrency do
// (Kingfisher's placeholders and drawing, SwiftyForm's cells): Apple's UIKit is imported as
// `@preconcurrency @MainActor`, so a Swift 5 mode module calls it synchronously from anywhere.
// UIKitWebCore's main-actor declarations carry `@preconcurrency` for the same reason.
// Compiled by `scripts/build-wasm.sh Examples/Launches` in CI; an isolation error here is a build error.
import UIKit

enum NonisolatedUIKit {
    static func placeholder(in container: UIView) -> UIImageView {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(imageView)
        imageView.centerXAnchor.constraint(equalTo: container.centerXAnchor).isActive = true
        imageView.image = draw(size: CGSize(width: 2, height: 2))
        return imageView
    }

    static func draw(size: CGSize) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(size, false, 1)
        defer { UIGraphicsEndImageContext() }
        UIColor.red.setFill()
        UIRectFill(CGRect(origin: .zero, size: size))
        return UIGraphicsGetImageFromCurrentImageContext()
    }
}
