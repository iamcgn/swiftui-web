// Core Image's recipes as the recordings a context makes of them: extents, the flip to a
// top-left origin, and each filter as the display-list group the painters run.
#if !canImport(CoreGraphics) || os(WASI)
import Testing
import WebCoreImage
import WebFoundation
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

    /// Nuke applies `filter.copy() as? CIFilter` so that requests sharing a processor don't
    /// share inputs: the copy keeps the name and inputs and changes on its own.
    @Test func aCopyHasTheInputsAndChangesOnItsOwn() throws {
        let controls = try #require(CIFilter(name: "CIColorControls"))
        controls.setValue(2.0, forKey: kCIInputContrastKey)
        let copy = try #require(controls.copy() as? CIFilter)
        #expect(copy !== controls)
        #expect(copy.name == "CIColorControls")
        #expect(copy.value(forKey: kCIInputContrastKey) as? Double == 2)
        copy.setValue(CIImage(cgImage: bitmap(1, 1)), forKey: kCIInputImageKey)
        #expect(copy.outputImage != nil)
        #expect(controls.outputImage == nil)
        copy.setDefaults()
        #expect(controls.value(forKey: kCIInputContrastKey) as? Double == 2)
    }

    @Test func colorsAndVectors() {
        let color = CIColor(string: "0.5 0.25 1")
        #expect(color.red == 0.5 && color.green == 0.25 && color.blue == 1 && color.alpha == 1)
        let rect = CIVector(cgRect: CGRect(x: 1, y: 2, width: 3, height: 4))
        #expect(rect.cgRectValue == CGRect(x: 1, y: 2, width: 3, height: 4) && rect.count == 4)
        #expect(CIVector(x: 7).value(at: 3) == 0)
    }
}

// QR codes: the generator's symbols read back by the detector, through scaling, rotation and
// damage, and ISO/IEC 18004's worked example ("01234567" at level M) for the data codewords.
private func qrCode(_ message: String, level: String = "M") throws -> CIImage {
    let filter = try #require(CIFilter(name: "CIQRCodeGenerator"))
    filter.setValue(Data(message.utf8), forKey: "inputMessage")
    filter.setValue(level, forKey: "inputCorrectionLevel")
    return try #require(filter.outputImage)
}

private func readQRCode(_ image: CIImage) throws -> CIQRCodeFeature? {
    let detector = try #require(CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
    return detector.features(in: image).first as? CIQRCodeFeature
}

@Suite struct QRCodeTests {
    @Test func generatorDrawsOnePixelAModuleWithAMargin() throws {
        let image = try qrCode("01234567")
        #expect(image.extent == CGRect(x: 0, y: 0, width: 23, height: 23))
        #expect(CIFilter(name: "CIQRCodeGenerator")?.outputImage == nil)
    }

    @Test func standardExample() throws {
        let feature = try #require(try readQRCode(qrCode("01234567").transformed(by: CGAffineTransform(scaleX: 8, y: 8))))
        #expect(feature.type == CIFeatureTypeQRCode)
        #expect(feature.messageString == "01234567")
        let descriptor = try #require(feature.symbolDescriptor)
        #expect(descriptor.symbolVersion == 1)
        #expect(descriptor.errorCorrectionLevel == .levelM)
        #expect([UInt8](descriptor.errorCorrectedPayload) == [0x10, 0x20, 0x0C, 0x56, 0x61, 0x80, 0xEC, 0x11,
                                                             0xEC, 0x11, 0xEC, 0x11, 0xEC, 0x11, 0xEC, 0x11])
    }

    @Test func everyLevelAndModeReadsBack() throws {
        let messages = ["HELLO WORLD", "https://example.com/a?b=c&d=e", "Grüße aus Köln", String(repeating: "7", count: 300),
                        String(repeating: "Claude Duet ", count: 40)]
        for message in messages {
            for level in ["L", "M", "Q", "H"] {
                let image = try qrCode(message, level: level).transformed(by: CGAffineTransform(scaleX: 3, y: 3))
                let feature = try readQRCode(image)
                #expect(feature?.messageString == message, "\(level) \(message.prefix(12))")
            }
        }
    }

    @Test func cornersAreInTheImagesCoordinates() throws {
        let feature = try #require(try readQRCode(qrCode("corners").transformed(by: CGAffineTransform(scaleX: 10, y: 10))))
        // A 21-module code with a one-module margin, ten pixels a module, y up.
        #expect(abs(feature.topLeft.x - 10) < 2 && abs(feature.topLeft.y - 220) < 2)
        #expect(abs(feature.bottomRight.x - 220) < 2 && abs(feature.bottomRight.y - 10) < 2)
        #expect(abs(feature.bounds.width - 210) < 3)
    }

    @Test func rotatedOnAWhiteBackground() throws {
        let code = try qrCode("https://example.com/rotated", level: "Q")
            .transformed(by: CGAffineTransform(scaleX: 6, y: 6))
            .transformed(by: CGAffineTransform(rotationAngle: 0.6))
        let page = code.composited(over: CIImage.white).cropped(to: code.extent.insetBy(dx: -20, dy: -20))
        #expect(try readQRCode(page)?.messageString == "https://example.com/rotated")
    }

    @Test func damagedModulesAreCorrected() throws {
        let image = try qrCode("error correction", level: "H")
        let cgImage = try #require(image.cgImage)
        var pixels = [UInt8](try #require(cgImage.dataProvider?.data))
        let side = cgImage.width
        // Flip eight data modules away from the finders: fewer than either block can correct.
        for (x, y) in [(10, 10), (12, 14), (14, 11), (10, 15), (16, 16), (17, 13), (12, 18), (18, 18)] {
            let i = (y * side + x) * 4
            for c in 0..<3 { pixels[i + c] = 255 - pixels[i + c] }
        }
        let provider = try #require(CGDataProvider(data: Data(pixels)))
        let damaged = try #require(CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
                                           space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(alphaInfo: .premultipliedLast),
                                           provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let scaled = CIImage(cgImage: damaged).transformed(by: CGAffineTransform(scaleX: 4, y: 4))
        #expect(try readQRCode(scaled)?.messageString == "error correction")
    }

    @Test func nothingToFind() throws {
        #expect(CIDetector(ofType: CIDetectorTypeFace, context: nil, options: nil) == nil)
        #expect(try readQRCode(CIImage(cgImage: bitmap(64, 64))) == nil)
        #expect(try readQRCode(CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 50, height: 50))) == nil)
    }
}
#endif
