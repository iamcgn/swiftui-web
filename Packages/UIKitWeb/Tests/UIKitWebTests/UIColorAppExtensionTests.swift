// An app's own UIColor initializer with light and dark colours (GistHub's DesignSystem declares
// one) is the only `UIColor(light:dark:)`: UIKit's own per-appearance initializer is underscored,
// as no such initializer is public on Apple's UIColor, so `.black` and `.white` mean UIColor's.
import Testing
import UIKit

extension UIColor {
    convenience init(light: UIColor, dark: UIColor) {
        self.init { $0.userInterfaceStyle == .dark ? dark : light }
    }
}

@Suite struct UIColorAppExtensionTests {
    @Test func anAppsLightDarkInitializerIsTheOneCalled() {
        let color = UIColor(light: .black, dark: .white)
        #expect(color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)) == UIColor.black)
        #expect(color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark)) == UIColor.white)
    }
}
