// Barcode descriptors and the render destination's alpha mode, as values (Docs/elements/CoreImage.md).
// Core Image reads a barcode's payload out of an image with a detector, which needs the
// platform's decoder; here there is none, so nothing produces these, and an app that builds one
// itself (a QR code's payload for a generator, swift-custom-dump's conformances) has the types,
// with Apple's raw values.

#if !canImport(CoreGraphics) || os(WASI)
import WebFoundation

/// The abstract base of the barcode descriptors.
open class CIBarcodeDescriptor: @unchecked Sendable {
    init() {}
}

/// A QR code's payload and the parameters it was encoded with.
open class CIQRCodeDescriptor: CIBarcodeDescriptor, @unchecked Sendable {
    /// How much of the code can be damaged and still read, as the letter's ASCII code.
    public enum ErrorCorrectionLevel: Int, Sendable {
        case levelL = 76
        case levelM = 77
        case levelQ = 81
        case levelH = 72
    }

    public let errorCorrectedPayload: Data
    public let symbolVersion: Int
    public let maskPattern: UInt8
    public let errorCorrectionLevel: ErrorCorrectionLevel

    /// Nil when the version is outside 1...40 or the mask outside 0...7, as Core Image refuses them.
    public init?(payload errorCorrectedPayload: Data, symbolVersion: Int, maskPattern: UInt8, errorCorrectionLevel: ErrorCorrectionLevel) {
        guard (1...40).contains(symbolVersion), maskPattern <= 7 else { return nil }
        self.errorCorrectedPayload = errorCorrectedPayload
        self.symbolVersion = symbolVersion
        self.maskPattern = maskPattern
        self.errorCorrectionLevel = errorCorrectionLevel
        super.init()
    }
}

/// A Data Matrix code's payload and the parameters it was encoded with.
open class CIDataMatrixCodeDescriptor: CIBarcodeDescriptor, @unchecked Sendable {
    /// The error-correction version (ECC 000 to 200).
    public enum ECCVersion: Int, Sendable {
        case v000 = 0
        case v050 = 50
        case v080 = 80
        case v100 = 100
        case v140 = 140
        case v200 = 200
    }

    public let errorCorrectedPayload: Data
    public let rowCount: Int
    public let columnCount: Int
    public let eccVersion: ECCVersion

    public init?(payload errorCorrectedPayload: Data, rowCount: Int, columnCount: Int, eccVersion: ECCVersion) {
        guard rowCount > 0, columnCount > 0 else { return nil }
        self.errorCorrectedPayload = errorCorrectedPayload
        self.rowCount = rowCount
        self.columnCount = columnCount
        self.eccVersion = eccVersion
        super.init()
    }
}

/// How a render destination treats alpha.
public enum CIRenderDestinationAlphaMode: UInt, Sendable {
    case none = 0
    case premultiplied = 1
    case unpremultiplied = 2
}
#endif
