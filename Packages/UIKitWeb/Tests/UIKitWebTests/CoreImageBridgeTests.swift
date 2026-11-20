// What Apple's UIKit brings with Core Image (UIKit/CoreImageBridges.swift): a file that imports
// only UIKit names CIImage, CIFilter and CIContext (Nuke's processors), a UIImage made from a
// Core Image recipe keeps it as `ciImage`, and `preparingForDisplay()` hands an image back (nil
// for a recipe-backed one, as on iOS), and its completion-handler form hands it back later.
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

    @Test func preparingForDisplayHandsTheImageBack() async throws {
        let cgImage = try #require(CIContext().createCGImage(recipe, from: recipe.extent))
        let image = UIImage(cgImage: cgImage)
        #expect(image.preparingForDisplay() === image)
        #expect(await image.byPreparingForDisplay() === image)
    }

    @Test func aRecipeBackedImageHasNothingToPrepare() async {
        let image = UIImage(ciImage: recipe)
        #expect(image.preparingForDisplay() == nil)
        #expect(await image.byPreparingForDisplay() == nil)
    }

    /// Called later means outside this call, so in a task of its own: an inline call would run
    /// in the test's task.
    @Test func theHandlerIsCalledLater() async throws {
        let cgImage = try #require(CIContext().createCGImage(recipe, from: recipe.extent))
        let image = UIImage(cgImage: cgImage)
        let caller = withUnsafeCurrentTask { $0.map { $0.hashValue } }
        let (prepared, handlerTask): (UIImage?, Int?) = await withCheckedContinuation { done in
            image.prepareForDisplay { done.resume(returning: ($0, withUnsafeCurrentTask { $0.map { $0.hashValue } })) }
        }
        #expect(prepared === image)
        #expect(caller != nil)
        #expect(handlerTask != caller)
    }
}
#endif
