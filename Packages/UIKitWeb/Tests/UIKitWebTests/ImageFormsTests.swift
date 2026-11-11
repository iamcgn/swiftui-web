// The image and colour initializers apps call off the main actor and with the forms SFSafeSymbols
// wraps (`init(systemName:compatibleWith:)`, `UIImage.Configuration`), and the symbol
// configuration's merging.
import Testing
import UIKit

@Suite struct ImageFormsTests {
    /// Not on the main actor: a model or a background task makes images as well.
    nonisolated func symbol(_ name: String) -> UIImage? { UIImage(systemName: name) }

    @Test func initializersOffTheMainActor() {
        #expect(symbol("star.fill") != nil)
        #expect(symbol("no.such.symbol") == nil)
        #expect(UIImage(named: "no-such-image") == nil)
        #expect(UIColor(named: "NoSuchColor") == nil)
    }

    @Test func symbolForms() {
        #expect(UIImage(systemName: "star", compatibleWith: nil) != nil)
        let configuration: UIImage.Configuration = UIImage.SymbolConfiguration(pointSize: 24)
        let image = UIImage(systemName: "star", withConfiguration: configuration)
        #expect(image?.configuration?.pointSize == 24)
        #expect(image?.size.width == 30)
        #expect(UIImage(systemName: "wifi", variableValue: 0.5, configuration: nil) != nil)
        #expect(UIImage(named: "no-such-image", in: nil, with: configuration) == nil)
        #expect(UIImage(named: "no-such-image", in: nil, compatibleWith: nil) == nil)
    }

    @Test func mergingConfigurations() {
        let merged = UIImage.SymbolConfiguration(pointSize: 20).applying(UIImage.SymbolConfiguration(weight: .bold))
        #expect(merged.pointSize == 20)
        #expect(merged.weight == .bold)
        #expect(merged.configurationWithoutPointSizeAndWeight().pointSize == nil)
        #expect(UIImage.SymbolConfiguration(font: .systemFont(ofSize: 15)).pointSize == 15)
    }
}
