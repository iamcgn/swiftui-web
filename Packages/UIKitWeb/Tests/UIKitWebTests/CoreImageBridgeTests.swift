// What Apple's UIKit brings with Core Image (UIKit/CoreImageBridges.swift): a file that imports
// only UIKit names CIImage, CIFilter and CIContext (Nuke's processors), a UIImage made from a
// Core Image recipe keeps it as `ciImage`, and `preparingForDisplay()` hands the image back.
#if !canImport(CoreGraphics) || os(WASI)
import Testing
import UIKit

@Suite struct CoreImageBridgeTests {
    private let recipe = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 4, height: 2))

    @Test func uikitAloneNamesCoreImage() {
        let filter: CIFilter? = CIFilter(name: "CIColorControls")
        #expect(filter?.name == "CIColorControls")
        #expect(CIContext().createCGImage(recipe, from: recipe.extent) != nil)
    }

    @Test func anImageFromARecipeKeepsIt() {
        let image = UIImage(ciImage: recipe)
        #expect(image.ciImage === recipe)
        #expect(image.size == CGSize(width: 4, height: 2))
        #expect(image.cgImage != nil)
    }

    @Test func otherImagesHaveNoRecipe() throws {
        #expect(UIImage().ciImage == nil)
        let cgImage = try #require(CIContext().createCGImage(recipe, from: recipe.extent))
        #expect(UIImage(cgImage: cgImage).ciImage == nil)
    }

    @Test func preparingForDisplayHandsTheImageBack() async {
        let image = UIImage(ciImage: recipe)
        #expect(image.preparingForDisplay() === image)
        #expect(await image.byPreparingForDisplay() === image)
        var handed: UIImage?
        image.prepareForDisplay { handed = $0 }
        #expect(handed === image)
    }
}
#endif
