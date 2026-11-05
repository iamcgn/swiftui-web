// Core Image's recipes as the recordings a context makes of them: extents, the flip to a
// top-left origin, and each filter as the display-list group the painters run.
#if !canImport(CoreGraphics) || os(WASI)
import Testing
import WebCoreImage
import WebGraphics

private func bitmap(_ width: Int, _ height: Int) -> CGImage {
    CGImage(_content: .bitmap(DisplayBitmap(width: width, height: height, pixels: [UInt8](repeating: 255, count: width * height * 4))))
}

private func recording(_ image: CGImage?) -> [DisplayCommand] {
    guard let image, case .recording(let commands, _, _) = image._content else { return [] }
    return commands
}

private func filters(_ commands: [DisplayCommand]) -> [DisplayFilter] {
    commands.compactMap { if case .beginFilter(let filter, _) = $0 { return filter } else { return nil } }
}

@Suite struct CoreImageTests {
    @Test func extents() {
        let image = CIImage(cgImage: bitmap(4, 2))
        #expect(image.extent == CGRect(x: 0, y: 0, width: 4, height: 2))
        #expect(CIImage(color: .red).extent.isInfinite)
        #expect(CIImage.empty().extent.isNull)
        #expect(image.cropped(to: CGRect(x: 1, y: 0, width: 10, height: 1)).extent == CGRect(x: 1, y: 0, width: 3, height: 1))
        #expect(image.applyingGaussianBlur(sigma: 2).extent == CGRect(x: -6, y: -6, width: 16, height: 14))
        #expect(image.transformed(by: CGAffineTransform(translationX: 5, y: 1)).extent == CGRect(x: 5, y: 1, width: 4, height: 2))
        #expect(image.oriented(.right).extent == CGRect(x: 0, y: 0, width: 2, height: 4))
        #expect(CIImage(color: .red).composited(over: image).extent.isInfinite)
    }

    @Test func contextFlipsToTopLeft() throws {
        let context = CIContext(options: [.cacheIntermediates: false])
        let made = try #require(context.createCGImage(CIImage(cgImage: bitmap(4, 2)), from: CGRect(x: 1, y: 0, width: 2, height: 2)))
        #expect(made.width == 2 && made.height == 2)
        let commands = recording(made)
        #expect(Array(commands.prefix(3)) == [.save, .clipRect(CGRect(x: 0, y: 0, width: 2, height: 2)),
                                              .concat(CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: -1, ty: 2))])
        #expect(commands.contains { if case .drawBitmap = $0 { return true } else { return false } })
        #expect(context.createCGImage(CIImage(color: .blue), from: .infinite) == nil)
        #expect(context.createCGImage(.empty(), from: .zero) == nil)
    }

    /// Kingfisher's tint: a constant colour over the image, cropped back to the image.
    @Test func tintComposite() throws {
        let input = CIImage(cgImage: bitmap(3, 3))
        let color = try #require(CIFilter(name: "CIConstantColorGenerator"))
        color.setValue(CIColor(red: 1, green: 0, blue: 0, alpha: 0.5), forKey: kCIInputColorKey)
        let over = try #require(CIFilter(name: "CISourceOverCompositing"))
        over.setValue(color.outputImage, forKey: kCIInputImageKey)
        over.setValue(input, forKey: kCIInputBackgroundImageKey)
        let output = try #require(over.outputImage).cropped(to: input.extent)
        let commands = recording(CIContext().createCGImage(output, from: output.extent))
        let fill = commands.firstIndex { if case .fillRect(_, let c) = $0 { return c == RGBA(red: 1, green: 0, blue: 0, alpha: 0.5) } else { return false } }
        let draw = commands.firstIndex { if case .drawBitmap = $0 { return true } else { return false } }
        #expect(fill != nil && draw != nil && draw! < fill!)
    }

    @Test func colorFilters() {
        let input = CIImage(cgImage: bitmap(2, 2))
        let mono = input.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.0])
        #expect(filters(recording(CIContext().createCGImage(mono, from: mono.extent))) == [.colorMatrix(.saturation(0))])
        let brighter = input.applyingFilter("CIColorControls", parameters: [kCIInputBrightnessKey: 0.25])
        #expect(filters(recording(CIContext().createCGImage(brighter, from: brighter.extent))) == [.colorMatrix(.brightness(0.25))])
        let exposed = input.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: 1.0])
        #expect(filters(recording(CIContext().createCGImage(exposed, from: exposed.extent)))
                == [.colorMatrix(ColorMatrix([2, 0, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 1, 0]))])
        let matrix = input.applyingFilter("CIColorMatrix", parameters: ["inputRVector": CIVector(x: 0, y: 1, z: 0, w: 0),
                                                                       kCIInputBiasVectorKey: CIVector(x: 0.1, y: 0, z: 0, w: 0)])
        #expect(filters(recording(CIContext().createCGImage(matrix, from: matrix.extent)))
                == [.colorMatrix(ColorMatrix([0, 1, 0, 0, 0.1, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0]))])
        let blurred = input.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 3])
        #expect(filters(recording(CIContext().createCGImage(blurred, from: input.extent))) == [.blur(radius: 3, opaque: false)])
    }

    @Test func filterInputs() throws {
        #expect(CIFilter(name: "CINoSuchFilter") == nil)
        #expect(CIImage(cgImage: bitmap(1, 1)).applyingFilter("CINoSuchFilter").extent.isNull)
        let controls = try #require(CIFilter(name: "CIColorControls"))
        #expect(controls.value(forKey: kCIInputContrastKey) as? Double == 1)
        #expect(controls.outputImage == nil)
        controls.setValue(2.0, forKey: kCIInputContrastKey)
        controls.setDefaults()
        #expect(controls.value(forKey: kCIInputContrastKey) as? Double == 1)
        #expect(CIFilter.filterNames(inCategory: kCICategoryBlur) == ["CIGaussianBlur"])
        let multiply = try #require(CIFilter(name: "CIMultiplyCompositing", parameters: [
            kCIInputImageKey: CIImage(color: .red), kCIInputBackgroundImageKey: CIImage(cgImage: bitmap(2, 2)),
        ]))
        let output = try #require(multiply.outputImage)
        let commands = recording(CIContext().createCGImage(output, from: CGRect(x: 0, y: 0, width: 2, height: 2)))
        #expect(commands.contains(.beginBlend(.multiply, bounds: CGRect(x: 0, y: 0, width: 2, height: 2))))
    }

    @Test func colorsAndVectors() {
        let color = CIColor(string: "0.5 0.25 1")
        #expect(color.red == 0.5 && color.green == 0.25 && color.blue == 1 && color.alpha == 1)
        let rect = CIVector(cgRect: CGRect(x: 1, y: 2, width: 3, height: 4))
        #expect(rect.cgRectValue == CGRect(x: 1, y: 2, width: 3, height: 4) && rect.count == 4)
        #expect(CIVector(x: 7).value(at: 3) == 0)
    }
}
#endif
