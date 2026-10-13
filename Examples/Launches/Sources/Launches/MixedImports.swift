// A file that imports UIKit, Foundation and SwiftUI together, as app files do, naming the
// types every one of those modules could claim (decision 0021): `Selector` is one declaration
// (WebFoundation's where there is no Objective-C runtime, re-exported by UIKit and the
// Foundation shadow), so a `nil` selector argument and a selector by name both type-check.
// Compiled by `scripts/build-wasm.sh Examples/Launches` in CI; an ambiguity here is a build error.
import UIKit
import Foundation
import SwiftUI

enum MixedImports {
    static let copySelector: Selector = Selector("copy:")

    @MainActor static func check() -> String {
        let bounds = UIScreen.main.bounds
        let image = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        // A nil selector type-checks against the one `Selector`; the save itself is not run here (a download).
        let save: (UIImage, Any?, Selector?, UnsafeMutableRawPointer?) -> Void = UIImageWriteToSavedPhotosAlbum
        _ = save
        _ = image
        return "\(copySelector) \(Int(bounds.width)) \(Bundle.main.localizations.joined(separator: ","))"
    }
}
