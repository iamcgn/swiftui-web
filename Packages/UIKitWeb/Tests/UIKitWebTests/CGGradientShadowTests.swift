// `CGGradient` as apps see it: a file importing only UIKit gets UIKitWeb's class (the thin
// module declares the name beside its re-export of CoreGraphics, so it shadows CoreGraphics's
// opaque class on Apple platforms); `locations: nil` resolves to it. A file that also imports
// WebGraphics (which re-exports CoreGraphics) sees both and must write locations as an array.
import Testing
import UIKit

@Suite @MainActor struct CGGradientShadowTests {
    @Test func gradientNameResolvesToTheRecordersClass() {
        let gradient: UIGraphicsGradient? = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [UIColor.red.cgColor, UIColor.blue.cgColor] as CFArray, locations: nil)
        #expect(gradient != nil)
        #expect(CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [] as CFArray, locations: nil) == nil)
    }
}
